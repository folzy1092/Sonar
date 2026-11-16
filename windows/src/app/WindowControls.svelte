<script lang="ts">
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import HistoryButton from './HistoryButton.svelte'
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

  onMount(() => {
    const sync = async () => (maximized = await isWindowMaximized())
    sync()
    return onWindowResized(sync)
  })
</script>

<div class="controls">
  <!-- история прослушивания — как часы у Dotify -->
  {#if history}<HistoryButton />{/if}
  <button class="ctl press" aria-label="Свернуть" title="Свернуть" onclick={minimizeWindow}>
    <Icon name="minus" size={16} stroke={1.8} />
  </button>
  <button
    class="ctl press"
    aria-label={maximized ? 'Восстановить' : 'Развернуть'}
    title={maximized ? 'Восстановить' : 'Развернуть'}
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
  <button class="ctl close press" aria-label="Закрыть" title="Закрыть" onclick={closeWindow}>
    <Icon name="x" size={16} stroke={1.8} />
  </button>
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
  .ctl:disabled {
    opacity: 0.3;
    cursor: default;
  }
</style>
