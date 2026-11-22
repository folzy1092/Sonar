<script lang="ts">
  // Система → Пульт: iPhone управляет музыкой на этом компьютере по Wi-Fi (remote/ в Rust). По умолчанию
  // выключен. Привязка — 6-значный код или QR с экрана (5 минут), дальше телефон входит своим ключом.
  // Звук не передаётся — только команды и что сейчас играет. Отвязать — ключ телефона перестаёт работать.
  import { onDestroy } from 'svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Group from '../../components/settings/Group.svelte'
  import Icon from '../../components/Icon.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { remote } from '../../lib/remote.svelte'
  import { api, errorText, type RemoteDevice, type RemotePairStart } from '../../lib/api'
  import { cascade } from '../../lib/cascade'
  import { pop, slide } from '../../lib/motion'
  import { confirm } from '../../lib/confirm.svelte'
  import { toast } from '../../lib/toast.svelte'
  import { dateLong } from '../../lib/format'
  import { t } from '../../lib/i18n.svelte'

  const enabled = $derived(settings.get('remote.enabled'))
  const status = $derived(remote.status)
  const devices = $derived(status?.devices ?? [])

  let pair = $state<RemotePairStart | null>(null)
  let leftMs = $state(0)
  let busy = $state(false)
  let timer: ReturnType<typeof setInterval> | null = null

  void remote.refresh()

  // код ввели (или он сгорел от неверных попыток) — Rust снял его, убираем с экрана
  $effect(() => {
    if (pair && status && !status.pairing) stopPair()
  })
  // выключили пульт — код больше не нужен
  $effect(() => {
    if (!enabled && pair) stopPair()
  })

  onDestroy(() => {
    if (pair) void api.remotePairCancel()
    stopTimer()
  })

  function stopTimer() {
    if (timer) clearInterval(timer)
    timer = null
  }

  function stopPair() {
    pair = null
    stopTimer()
  }

  async function startPair() {
    busy = true
    try {
      const p = await api.remotePairStart()
      const until = Date.now() + p.expires_in_ms
      pair = p
      leftMs = p.expires_in_ms
      stopTimer()
      timer = setInterval(() => {
        leftMs = Math.max(0, until - Date.now())
        if (!leftMs) cancelPair()
      }, 1000)
    } catch (e) {
      toast.show(errorText(e))
    } finally {
      busy = false
    }
  }

  function cancelPair() {
    stopPair()
    void api.remotePairCancel()
  }

  async function unpair(d: RemoteDevice) {
    const ok = await confirm.ask({
      title: t('Отвязать {name}?', { name: d.name }),
      text: t('Телефон больше не сможет управлять Sonar на этом компьютере, пока его не привяжут заново.'),
      yes: t('Отвязать'),
      no: t('Отмена'),
      danger: true,
    })
    if (!ok) return
    try {
      await api.remoteUnpair(d.id)
    } catch (e) {
      toast.show(errorText(e))
    }
    await remote.refresh()
  }

  const countdown = (ms: number) => {
    const s = Math.ceil(ms / 1000)
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
  }

  const day = (ms: number) => {
    const d = new Date(ms)
    return dateLong(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`)
  }
</script>

<Group title={t('Пульт')}>
  <Switch
    title={t('Пульт с iPhone')}
    hint={t('Управлять музыкой на этом компьютере с телефона по Wi-Fi')}
    on={enabled}
    onchange={(v) => settings.set('remote.enabled', v)}
  />
  <p class="note">
    <Icon name="wifi" size={15} />
    <span>{t('При первом включении Windows спросит доступ к сети — разреши для частных сетей, иначе телефон не увидит компьютер. Телефон и компьютер должны быть в одной сети Wi-Fi.')}</span>
  </p>
  {#if enabled && status}
    <div class="status" transition:slide={{ duration: 220 }}>
      {#if status.error}
        <p class="warn">{t('Не запустился: {error}', { error: status.error })}</p>
      {:else if status.running}
        <p>
          <i class="dot on"></i>
          {t('Включён: {name}', { name: status.name })}{#if status.host}<span class="addr">{status.host}:{status.port}</span>{/if}
        </p>
        {#if status.mdns_error}
          <p class="warn">{t('Компьютер не виден в сети — привяжи телефон по QR-коду')}</p>
        {/if}
      {:else}
        <p><i class="dot"></i>{t('Запускается…')}</p>
      {/if}
    </div>
  {/if}
</Group>

{#if enabled && status?.running}
  <div transition:slide={{ duration: 240 }}>
    <Group title={t('Привязка')} hint={t('В Sonar на iPhone: плеер → значок устройства → этот компьютер, затем код или QR')}>
      {#if pair}
        <div class="pair" transition:slide={{ duration: 240 }}>
          <div class="qr" in:pop={{ duration: 260 }}>{@html pair.qr_svg}</div>
          <div class="side">
            <div class="digits" use:cascade={pair.code}>
              {#each pair.code.split('') as d, i (i)}<span>{d}</span>{/each}
            </div>
            <small>{t('Код действует ещё {time}', { time: countdown(leftMs) })}</small>
            <button class="ghost" onclick={cancelPair}>{t('Отмена')}</button>
          </div>
        </div>
      {:else}
        <button class="connect" disabled={busy} onclick={startPair} in:pop={{ duration: 220 }}>
          <span class="big"><Icon name="phone" size={34} /></span>
          <b>{t('Привязать iPhone')}</b>
          <small>{t('Покажем код и QR — их нужно ввести на телефоне за 5 минут')}</small>
        </button>
      {/if}
    </Group>
  </div>
{/if}

{#if enabled}
  <div transition:slide={{ duration: 240 }}>
    <Group title={t('Устройства')}>
      {#if devices.length}
        <div class="list" use:cascade={devices.length}>
          {#each devices as d (d.id)}
            <div class="row" transition:slide={{ duration: 200 }}>
              <span class="ph" class:online={d.online}><Icon name="phone" size={18} /></span>
              <span class="text">
                <b>{d.name}</b>
                <small>
                  {#if d.online}<i class="dot on"></i>{t('Подключён сейчас')}{:else}{t('Был в сети {date}', { date: day(d.last_seen || d.paired_at) })}{/if}
                </small>
              </span>
              <button class="unpair" onclick={() => unpair(d)}>
                <Icon name="unlink" size={15} />
                {t('Отвязать')}
              </button>
            </div>
          {/each}
        </div>
      {:else}
        <p class="empty">{t('Пока ни одного телефона')}</p>
      {/if}
    </Group>
  </div>
{/if}

<style>
  .note {
    display: flex;
    gap: 8px;
    align-items: flex-start;
    margin: 6px 0 0;
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
  .note :global(svg) {
    flex: none;
    margin-top: 1px;
  }
  .status p {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 10px 0 0;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-2);
  }
  .addr {
    margin-left: 4px;
    padding: 1px 7px;
    border-radius: 6px;
    background: var(--surface-3);
    font-size: calc(12px * var(--fs, 1));
    font-variant-numeric: tabular-nums;
    user-select: text;
  }
  .warn {
    color: var(--danger, #e5484d) !important;
  }
  .dot {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--text-3);
    transition: background var(--normal) var(--ease);
  }
  .dot.on {
    background: #3ecf6e;
    box-shadow: 0 0 0 3px color-mix(in srgb, #3ecf6e 22%, transparent);
  }
  .connect {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    width: 100%;
    padding: 24px 16px 20px;
    border-radius: 16px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    text-align: center;
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .connect:hover:not(:disabled) {
    background: var(--hover);
  }
  .connect:active:not(:disabled) {
    transform: scale(0.98);
  }
  .connect:disabled {
    opacity: 0.6;
    cursor: default;
  }
  .connect b {
    font-size: calc(15px * var(--fs, 1));
  }
  .connect small {
    max-width: 300px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .big {
    color: var(--text-2);
  }
  .pair {
    display: flex;
    align-items: center;
    gap: 22px;
    padding: 16px;
    border-radius: 16px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .qr {
    flex: none;
    width: 168px;
    height: 168px;
    padding: 6px;
    border-radius: 12px;
    background: #fff;
  }
  .qr :global(svg) {
    display: block;
    width: 100%;
    height: 100%;
  }
  .side {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 10px;
  }
  .digits {
    display: flex;
    gap: 6px;
  }
  .digits span {
    display: grid;
    place-items: center;
    width: 36px;
    height: 46px;
    border-radius: 10px;
    background: var(--surface-3);
    font-size: calc(24px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    user-select: text;
  }
  .digits span:nth-child(3) {
    margin-right: 8px;
  }
  .side small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .ghost,
  .unpair {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 30px;
    padding: 0 12px;
    border-radius: 9px;
    background: var(--surface-3);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .ghost:hover,
  .unpair:hover {
    background: var(--hover);
    color: var(--text);
  }
  .unpair:hover {
    color: var(--danger, #e5484d);
  }
  .ghost:active,
  .unpair:active {
    transform: scale(0.97);
  }
  .list {
    display: flex;
    flex-direction: column;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px 0;
  }
  .ph {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    border-radius: 10px;
    background: var(--surface-3);
    color: var(--text-3);
    transition: color var(--normal) var(--ease);
  }
  .ph.online {
    color: var(--text);
  }
  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  .text b {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .text small {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .empty {
    margin: 4px 0 0;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-3);
  }
  /* ширина панели настроек, не окна (окно не уже 960) */
  @container (max-width: 460px) {
    .pair {
      flex-direction: column;
    }
  }
</style>
