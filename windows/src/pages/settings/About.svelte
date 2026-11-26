<script lang="ts">
  // Приложение → О приложении (SETTINGS_NEXT, отдельный пункт с 2026-11-18): по центру знак и название,
  // ниже карточки — версия, приглашения · бета-версии · платежи, ссылки наружу со значком ↗ и сброс
  // настроек. Двойной клик по знаку — проверка обновлений: знак раскручивается, нет новых — на его месте
  // рисуется галочка; есть — открывается раздел «Обновления».
  import Icon from '../../components/Icon.svelte'
  import Card from '../../components/settings/Card.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Soon from '../../components/settings/Soon.svelte'
  import logo from '../../assets/logo-mark.svg'
  import { api } from '../../lib/api'
  import { settings } from '../../lib/settings.svelte'
  import { toast } from '../../lib/toast.svelte'
  import { updater } from '../../lib/updater.svelte'
  import { settingsPanel } from '../settings-section.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { SITE_URL as SITE } from '../../lib/site'
  import { offline } from '../../lib/offline.svelte'
  import { account } from '../../lib/account.svelte'
  import { betaAllowed } from '../../lib/beta'

  const LINKS = [
    { label: 'Сайт', url: SITE },
    { label: 'Телеграм', url: 'https://t.me/SonarUpdates' },
    { label: 'Подписка', url: `${SITE}/pay` },
    { label: 'Соглашение', url: `${SITE}/terms` },
    { label: 'Конфиденциальность', url: `${SITE}/privacy` },
  ]
  /** Знак крутится не меньше этого — даже если ответ пришёл мгновенно. */
  const MIN_SPIN_MS = 1000
  const TICK_MS = 1800
  const DOUBLE_TAP_MS = 450

  /** idle → spin (проверка) → done (галочка) → idle */
  let mark = $state<'idle' | 'spin' | 'done'>('idle')
  let taps = 0
  let tapTimer: ReturnType<typeof setTimeout> | undefined
  let confirm = $state(false)

  const hasUpdate = $derived(['available', 'downloading', 'ready', 'installing'].includes(updater.phase))
  const status = $derived(
    hasUpdate
      ? t('Доступно обновление')
      : updater.phase === 'checking'
        ? t('Проверяю…')
        : updater.phase === 'none'
          ? t('Последняя версия')
          : updater.phase === 'error'
            ? t('Не удалось проверить обновления')
            : t('Нажми, чтобы проверить обновления'),
  )

  const open = (url: string) => api.openUrl(url).catch(() => toast.show(url))
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms))

  function tap() {
    if (mark !== 'idle') return
    taps++
    clearTimeout(tapTimer)
    tapTimer = setTimeout(() => (taps = 0), DOUBLE_TAP_MS)
    if (taps >= 2) {
      taps = 0
      void check()
    }
  }

  async function check() {
    mark = 'spin'
    // ждём только сам ответ, не скачивание (при «Скачивать сразу» check() держит промис до конца загрузки)
    void updater.check()
    await wait(MIN_SPIN_MS)
    while (updater.phase === 'checking') await wait(100)
    const p = updater.phase
    if (p === 'none') {
      mark = 'done'
      toast.show(t('Новых обновлений не найдено — у тебя последняя версия'))
      await wait(TICK_MS)
    } else if (p === 'available' || p === 'ready' || p === 'downloading') {
      toast.show(t('Доступна версия {version}', { version: updater.version }))
      settingsPanel.show('system', 'update')
    } else if (p === 'error') {
      toast.show(updater.error || t('Не удалось проверить обновления'))
    }
    mark = 'idle'
  }

  function versionClick() {
    if (hasUpdate) settingsPanel.show('system', 'update')
    else void check()
  }

  async function reset() {
    try {
      await api.resetSettings()
      await settings.reload()
      toast.show(t('Настройки сброшены'))
    } catch (e) {
      toast.show(String(e))
    }
    confirm = false
  }
</script>

<div class="id">
  <button class="mark {mark}" aria-label={t('Проверить обновления')} title={t('Дважды нажми — проверю обновления')} onclick={tap}>
    <img src={offline.src(logo)} alt="" draggable="false" />
    <svg class="tick" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 12.5l4 4 8-9" /></svg>
  </button>
  <b class="name">Sonar</b>
</div>

<Card>
  <button class="row link" class:fresh={hasUpdate} onclick={versionClick} disabled={mark !== 'idle'}>
    <span class="ic"><Icon name={hasUpdate ? 'download' : 'check'} size={16} /></span>
    <span class="txt"><b>{status}</b><small>{t('Версия')}</small></span>
    <span class="num">{hasUpdate ? updater.version : updater.current}</span>
  </button>
</Card>

<Card>
  <div class="row">
    <span class="ic"><Icon name="user2" size={16} /></span>
    <span class="txt"><b>{t('Приглашения')} <Soon /></b><small>{t('Позови друзей в Sonar — когда появится сервер')}</small></span>
  </div>
  {#if betaAllowed(account.user?.login)}
    <Switch
      title={t('Бета-версии')}
      hint={t('Получать обновления раньше всех — они могут быть сырыми')}
      on={settings.get('update.channel') === 'beta'}
      onchange={(on) => settings.set('update.channel', on ? 'beta' : 'stable')}
    />
  {/if}
  <div class="row">
    <span class="ic"><Icon name="clock" size={16} /></span>
    <span class="txt"><b>{t('Платежи')} <Soon /></b><small>{t('История оплат Sonar Deep — когда появится сервер')}</small></span>
  </div>
</Card>

<Card>
  {#each LINKS as l (l.label)}
    <button class="row link" onclick={() => open(l.url)}>
      <span class="txt"><b>{t(l.label)}</b></span>
      <span class="out" aria-hidden="true">↗</span>
    </button>
  {/each}
</Card>

<div class="reset">
  {#if confirm}
    <span class="ask">{t('Сбросить все настройки? Лайки, плейлисты и сервисы останутся.')}</span>
    <button class="danger" onclick={reset}>{t('Сбросить')}</button>
    <button onclick={() => (confirm = false)}>{t('Отмена')}</button>
  {:else}
    <button onclick={() => (confirm = true)}><Icon name="refresh" size={13} /> {t('Сбросить настройки')}</button>
  {/if}
</div>

<style>
  .id {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    margin: 6px 0 22px;
  }
  .name {
    font-family: var(--font-display);
    font-size: calc(20px * var(--fs, 1));
    font-weight: 800;
    letter-spacing: -0.01em;
  }
  .mark {
    position: relative;
    display: grid;
    place-items: center;
    width: 64px;
    height: 64px;
    border-radius: 20px;
    background: radial-gradient(120% 120% at 30% 20%, var(--surface-3), var(--surface-1));
    border: 1px solid var(--border-strong);
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.08),
      0 10px 28px rgba(0, 0, 0, 0.45);
    transition:
      transform var(--fast) var(--ease),
      background 0.4s var(--ease),
      border-color 0.4s var(--ease);
  }
  .mark:active {
    transform: scale(0.94);
  }
  .mark img {
    grid-area: 1 / 1;
    width: 34px;
    height: 34px;
    transition:
      opacity 0.3s var(--ease),
      scale 0.4s var(--ease),
      filter 0.3s var(--ease);
  }
  /* раскрутка как у заставки: с разгоном, пока идёт проверка */
  .mark.spin img {
    animation: spin 0.9s cubic-bezier(0.55, 0, 0.45, 1) infinite;
  }
  .mark.done {
    background: color-mix(in srgb, var(--online) 22%, var(--surface-1));
    border-color: color-mix(in srgb, var(--online) 50%, transparent);
  }
  .mark.done img {
    opacity: 0;
    scale: 0.4;
    filter: blur(4px);
  }
  .tick {
    grid-area: 1 / 1;
    width: 30px;
    height: 30px;
    fill: none;
    stroke: var(--online);
    stroke-width: 2.6;
    stroke-linecap: round;
    stroke-linejoin: round;
    stroke-dasharray: 22;
    stroke-dashoffset: 22;
    opacity: 0;
  }
  .mark.done .tick {
    opacity: 1;
    animation: draw 0.5s 0.12s var(--ease) forwards;
  }
  @keyframes spin {
    to {
      rotate: 360deg;
    }
  }
  @keyframes draw {
    to {
      stroke-dashoffset: 0;
    }
  }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    min-height: 50px;
    padding: 8px 0;
    text-align: left;
  }
  .link {
    margin: 0 -10px;
    width: calc(100% + 20px);
    padding: 8px 10px;
    border-radius: 12px;
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .link:hover {
    background: var(--hover);
  }
  .link:active {
    transform: scale(0.99);
  }
  .link:disabled {
    cursor: default;
  }
  .ic {
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    flex: none;
    border-radius: 9px;
    background: var(--surface-3);
    color: var(--text-2);
    transition:
      background var(--normal) var(--ease),
      color var(--normal) var(--ease);
  }
  .fresh .ic {
    background: var(--accent);
    color: var(--accent-ink);
  }
  .txt {
    display: flex;
    flex: 1;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .txt b {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .txt small {
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
  .num {
    font-size: calc(16px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: var(--text-2);
  }
  .out {
    font-size: calc(15px * var(--fs, 1));
    color: var(--text-3);
    transition:
      transform var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .link:hover .out {
    color: var(--text);
    transform: translate(2px, -2px);
  }
  .reset {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: center;
    gap: 4px;
    margin-top: 22px;
    text-align: center;
    animation: tab-in var(--normal) var(--ease);
  }
  .reset button {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 6px 10px;
    border-radius: 9px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .reset button:hover {
    color: var(--text);
    background: var(--hover);
  }
  .reset .danger {
    color: var(--danger);
  }
  .ask {
    width: 100%;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-2);
  }
  @media (prefers-reduced-motion: reduce) {
    .mark.spin img {
      animation: breathe 1.2s ease-in-out infinite alternate;
    }
    @keyframes breathe {
      to {
        opacity: 0.35;
      }
    }
  }
</style>
