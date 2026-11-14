<script lang="ts">
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { router } from './router.svelte'
  import {
    closeWindow,
    isWindowMaximized,
    minimizeWindow,
    onWindowResized,
    toggleMaximizeWindow,
  } from '../lib/tauri'

  let maximized = $state(false)

  onMount(() => {
    const sync = async () => (maximized = await isWindowMaximized())
    sync()
    return onWindowResized(sync)
  })
</script>

<div class="controls">
  <button class="ctl" aria-label="Назад" title="Назад" disabled={!router.canGoBack} onclick={() => router.back()}>
    <Icon name="chevronLeft" size={16} />
  </button>
  <button class="ctl" aria-label="Свернуть" title="Свернуть" onclick={minimizeWindow}>
    <Icon name="minus" size={16} />
  </button>
  <button
    class="ctl"
    aria-label={maximized ? 'Восстановить' : 'Развернуть'}
    title={maximized ? 'Восстановить' : 'Развернуть'}
    onclick={toggleMaximizeWindow}
  >
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      {#if maximized}
        <rect x="5" y="9" width="10" height="10" rx="2" />
        <path d="M9 9V7a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-2" />
      {:else}
        <rect x="6" y="6" width="12" height="12" rx="2" />
      {/if}
    </svg>
  </button>
  <button class="ctl close" aria-label="Закрыть" title="Закрыть" onclick={closeWindow}>
    <Icon name="x" size={16} />
  </button>
</div>

<style>
  .controls {
    display: flex;
    gap: 2px;
  }
  .ctl {
    display: grid;
    place-items: center;
    width: 32px;
    height: 28px;
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
