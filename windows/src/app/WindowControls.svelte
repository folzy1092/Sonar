<script lang="ts">
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { router } from './router.svelte'
  import HistoryButton from './HistoryButton.svelte'
  import { fade } from 'svelte/transition'
  import {
    closeWindow,
    isWindowMaximized,
    minimizeWindow,
    onWindowResized,
    toggleMaximizeWindow,
  } from '../lib/tauri'

  interface Props {
    /** Кнопка «Назад» (в полноэкранном плеере её нет). */
    back?: boolean
  }
  let { back = true }: Props = $props()

  let maximized = $state(false)

  onMount(() => {
    const sync = async () => (maximized = await isWindowMaximized())
    sync()
    return onWindowResized(sync)
  })
</script>

<div class="controls">
  <!-- «Назад» — только когда есть куда; на его месте история прослушивания (как часы у Dotify) -->
  {#if back && router.canGoBack}
    <button class="ctl" aria-label="Назад" title="Назад" onclick={() => router.back()} transition:fade={{ duration: 160 }}>
      <Icon name="chevronLeft" size={14} stroke={1.8} />
    </button>
  {/if}
  {#if back}<HistoryButton />{/if}
  <button class="ctl" aria-label="Свернуть" title="Свернуть" onclick={minimizeWindow}>
    <Icon name="minus" size={14} stroke={1.8} />
  </button>
  <button
    class="ctl"
    aria-label={maximized ? 'Восстановить' : 'Развернуть'}
    title={maximized ? 'Восстановить' : 'Развернуть'}
    onclick={toggleMaximizeWindow}
  >
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      {#if maximized}
        <rect x="5" y="9" width="10" height="10" rx="2" />
        <path d="M9 9V7a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-2" />
      {:else}
        <rect x="6" y="6" width="12" height="12" rx="2" />
      {/if}
    </svg>
  </button>
  <button class="ctl close" aria-label="Закрыть" title="Закрыть" onclick={closeWindow}>
    <Icon name="x" size={14} stroke={1.8} />
  </button>
</div>

<style>
  .controls {
    display: flex;
    gap: 1px;
  }
  /* компактно, как у Dotify: кнопки окна почти не занимают места */
  .ctl {
    display: grid;
    place-items: center;
    width: 26px;
    height: 22px;
    border-radius: var(--radius-s);
    color: var(--text-3);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .ctl:hover:not(:disabled) {
    color: var(--text);
    background: var(--hover);
  }
  .ctl.close:hover {
    color: #fff;
    background: var(--danger);
  }
  .ctl:disabled {
    opacity: 0.3;
    cursor: default;
  }
</style>
