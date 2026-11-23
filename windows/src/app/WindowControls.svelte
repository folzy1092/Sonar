<script lang="ts">
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import HistoryButton from './HistoryButton.svelte'
  import ReleasesBell from './ReleasesBell.svelte'
  import { offline } from '../lib/offline.svelte'
  import { t } from '../lib/i18n.svelte'
  import { settings } from '../lib/settings.svelte'
  import { windowButtonsLook } from '../lib/window-buttons'
  import {
    closeWindow,
    isWindowMaximized,
    minimizeWindow,
    onWindowResized,
    toggleMaximizeWindow,
  } from '../lib/tauri'

  interface Props {
    /** История прослушивания (в полноэкранном плеере её нет). Кнопки «Назад» нет совсем —
     *  решение владельца 2026-11-16: назад — боковой кнопкой мыши, чёлка не меняет размер. */
    history?: boolean
  }
  let { history = true }: Props = $props()

  let maximized = $state(false)
  // Интерфейс → Вид → Кнопки окна: значки Windows или три кружка macOS
  const mac = $derived(windowButtonsLook(settings.get('appearance.window_buttons'), navigator.platform) === 'macos')

  onMount(() => {
    const sync = async () => (maximized = await isWindowMaximized())
    sync()
    return onWindowResized(sync)
  })
</script>

<div class="controls">
  <!-- история прослушивания — как часы у Dotify -->
  {#if history}
    {#if settings.get('notify.releases') && !offline.on}<ReleasesBell />{/if}
    <HistoryButton />
  {/if}
  {#if mac}
    <div class="lights">
      <button class="light close" aria-label={t('Закрыть')} title={t('Закрыть')} onclick={closeWindow}>
        <svg viewBox="0 0 12 12" aria-hidden="true"><path d="M4 4l4 4M8 4l-4 4" /></svg>
      </button>
      <button class="light min" aria-label={t('Свернуть')} title={t('Свернуть')} onclick={minimizeWindow}>
        <svg viewBox="0 0 12 12" aria-hidden="true"><path d="M3.5 6h5" /></svg>
      </button>
      <button
        class="light max"
        aria-label={maximized ? t('Восстановить') : t('Развернуть')}
        title={maximized ? t('Восстановить') : t('Развернуть')}
        onclick={toggleMaximizeWindow}
      >
        <svg viewBox="0 0 12 12" aria-hidden="true"><path d="M4 8V4h4M8 4v4H4" /></svg>
      </button>
    </div>
  {:else}
    <button class="ctl press" aria-label={t('Свернуть')} title={t('Свернуть')} onclick={minimizeWindow}>
      <Icon name="minus" size={16} stroke={1.8} />
    </button>
    <button
      class="ctl press"
      aria-label={maximized ? t('Восстановить') : t('Развернуть')}
      title={maximized ? t('Восстановить') : t('Развернуть')}
      onclick={toggleMaximizeWindow}
    >
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        {#if maximized}
          <rect x="5" y="9" width="10" height="10" rx="2" />
          <path d="M9 9V7a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-2" />
        {:else}
          <rect x="6" y="6" width="12" height="12" rx="2" />
        {/if}
      </svg>
    </button>
    <button class="ctl close press" aria-label={t('Закрыть')} title={t('Закрыть')} onclick={closeWindow}>
      <Icon name="x" size={16} stroke={1.8} />
    </button>
  {/if}
</div>

<style>
  .controls {
    display: flex;
    align-items: center;
    gap: 2px;
  }
  /* как у Dotify: 28×28, приглушённые, при наведении светлеет только значок, у «×» — красный */
  .ctl {
    display: grid;
    place-items: center;
    flex: none;
    width: 28px;
    height: 28px;
    border-radius: 8px;
    color: color-mix(in srgb, var(--text-2) 70%, transparent);
    transition:
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .ctl:hover:not(:disabled) {
    color: var(--text);
  }
  .ctl.close:hover {
    color: var(--danger);
  }
  /* macOS: три кружка 12 px, знаки проступают при наведении на группу */
  .lights {
    display: flex;
    gap: 8px;
    padding: 0 8px 0 6px;
  }
  .light {
    display: grid;
    place-items: center;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    transition:
      transform var(--fast) var(--ease),
      filter var(--fast) var(--ease);
  }
  .light.close {
    background: #ff5f57;
  }
  .light.min {
    background: #febc2e;
  }
  .light.max {
    background: #28c840;
  }
  .light:active {
    transform: scale(0.88);
    filter: brightness(0.85);
  }
  .light svg {
    width: 8px;
    height: 8px;
    fill: none;
    stroke: rgba(0, 0, 0, 0.55);
    stroke-width: 1.4;
    stroke-linecap: round;
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .lights:hover .light svg {
    opacity: 1;
  }
  .ctl:disabled {
    opacity: 0.3;
    cursor: default;
  }
</style>
