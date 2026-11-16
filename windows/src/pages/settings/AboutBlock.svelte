<script lang="ts">
  // Низ Система → Общее (решение владельца 2026-11-16): знак Sonar, название и версия, ссылки
  // (сайт, Телеграм, соглашение, конфиденциальность) и сброс настроек. Двойной клик по знаку —
  // проверка обновлений: знак раскручивается, нет новых — на его месте рисуется галочка и
  // всплывает «Новых обновлений не найдено»; есть — открывается раздел «Обновления».
  import Icon from '../../components/Icon.svelte'
  import logo from '../../assets/logo-mark.svg'
  import { api } from '../../lib/api'
  import { settings } from '../../lib/settings.svelte'
  import { toast } from '../../lib/toast.svelte'
  import { updater } from '../../lib/updater.svelte'
  import { settingsPanel } from '../settings-section.svelte'

  const SITE = 'https://sonar.folzy.ru'
  const LINKS = [
    { label: 'Сайт', url: SITE },
    { label: 'Телеграм', url: 'https://t.me/SonarUpdates' },
    { label: 'Соглашение', url: `${SITE}/terms` },
    { label: 'Конфиденциальность', url: `${SITE}/privacy` },
  ]

  /** idle → spin (проверка) → done (галочка) → idle */
  let mark = $state<'idle' | 'spin' | 'done'>('idle')
  let taps = 0
  let tapTimer: ReturnType<typeof setTimeout> | undefined
  let confirm = $state(false)

  const open = (url: string) => api.openUrl(url).catch(() => toast.show(url))
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms))

  function tap() {
    if (mark !== 'idle') return
    taps++
    clearTimeout(tapTimer)
    tapTimer = setTimeout(() => (taps = 0), 450)
    if (taps >= 2) {
      taps = 0
      void check()
    }
  }

  async function check() {
    mark = 'spin'
    // крутится не меньше секунды — даже если ответ пришёл мгновенно; ждём только сам ответ,
    // не скачивание (при «Скачивать сразу» check() держит промис до конца загрузки)
    void updater.check()
    await wait(1000)
    while (updater.phase === 'checking') await wait(100)
    const p = updater.phase
    if (p === 'none') {
      mark = 'done'
      toast.show('Новых обновлений не найдено — у тебя последняя версия')
      await wait(1800)
    } else if (p === 'available' || p === 'ready' || p === 'downloading') {
      toast.show(`Доступна версия ${updater.version}`)
      settingsPanel.show('system', 'update')
    } else if (p === 'error') {
      toast.show(updater.error || 'Не удалось проверить обновления')
    }
    mark = 'idle'
  }

  async function reset() {
    try {
      await api.resetSettings()
      await settings.reload()
      toast.show('Настройки сброшены')
    } catch (e) {
      toast.show(String(e))
    }
    confirm = false
  }
</script>

<div class="about">
  <div class="id">
    <button
      class="mark {mark}"
      aria-label="Проверить обновления"
      title="Дважды нажми — проверю обновления"
      onclick={tap}
    >
      <img src={logo} alt="" draggable="false" />
      <svg class="tick" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 12.5l4 4 8-9" /></svg>
    </button>
    <div class="name">
      <b>Sonar</b>
      <small>Версия {updater.current}</small>
    </div>
  </div>

  <nav class="links">
    {#each LINKS as l (l.label)}
      <button onclick={() => open(l.url)}>{l.label}</button>
    {/each}
  </nav>

  <div class="reset">
    {#if confirm}
      <span class="ask">Сбросить все настройки? Лайки, плейлисты и сервисы останутся.</span>
      <button class="danger" onclick={reset}>Сбросить</button>
      <button onclick={() => (confirm = false)}>Отмена</button>
    {:else}
      <button onclick={() => (confirm = true)}><Icon name="refresh" size={13} /> Сбросить настройки</button>
    {/if}
  </div>
</div>

<style>
  .about {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 14px;
    margin-top: 34px;
    padding: 22px 0 6px;
    border-top: 1px solid var(--border);
    text-align: center;
  }
  .id {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
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
  .name {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .name b {
    font-family: var(--font-display);
    font-size: calc(18px * var(--fs, 1));
    font-weight: 800;
    letter-spacing: -0.01em;
  }
  .name small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .links {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 2px 4px;
  }
  .links button,
  .reset button {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 4px 8px;
    border-radius: 8px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-2);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .links button:hover,
  .reset button:hover {
    color: var(--text);
    background: var(--hover);
  }
  .reset {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: center;
    gap: 4px;
    animation: tab-in var(--normal) var(--ease);
  }
  .reset button {
    color: var(--text-3);
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
