<script lang="ts">
  // Кнопка-часы слева от громкости: режим скорости Slowed / Sped up (тон меняется вместе
  // со скоростью). Включённый режим — подпись прямо на кнопке, как «Speed» у Dotify.
  import Icon from '../components/Icon.svelte'
  import { player, speedModes, type SpeedMode } from './player.svelte'

  let open = $state(false)
  let root: HTMLElement | undefined = $state()
  const mode = $derived(speedModes[player.speedMode])
  const modes = Object.entries(speedModes) as [SpeedMode, (typeof speedModes)[SpeedMode]][]

  function pick(m: SpeedMode) {
    player.setSpeedMode(m)
    open = false
  }

  function onWindowDown(e: PointerEvent) {
    if (open && root && !root.contains(e.target as Node)) open = false
  }
</script>

<svelte:window onpointerdown={onWindowDown} onkeydown={(e) => e.key === 'Escape' && (open = false)} />

<div class="speed" bind:this={root}>
  <button
    class="btn"
    class:on={player.speedMode !== 'normal'}
    aria-label="Скорость: {mode.label}"
    title="Скорость: {mode.label}"
    aria-expanded={open}
    onclick={() => (open = !open)}
  >
    {#if mode.badge}
      <span class="badge">{mode.badge}</span>
    {:else}
      <Icon name="clock" size={18} />
    {/if}
  </button>

  {#if open}
    <div class="menu" role="menu">
      <span class="head">Скорость</span>
      {#each modes as [id, m] (id)}
        <button class="item" class:sel={player.speedMode === id} role="menuitemradio" aria-checked={player.speedMode === id} onclick={() => pick(id)}>
          <span class="name">{m.label}</span>
          <span class="rate">{m.rate}×</span>
          <span class="tick">{#if player.speedMode === id}<Icon name="check" size={16} />{/if}</span>
        </button>
      {/each}
    </div>
  {/if}
</div>

<style>
  .speed {
    position: relative;
  }
  .btn {
    display: grid;
    place-items: center;
    min-width: 34px;
    height: 34px;
    border-radius: var(--radius-s);
    color: var(--text-2);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .btn:hover {
    color: var(--text);
    background: var(--hover);
  }
  .badge {
    padding: 3px 9px;
    border-radius: 999px;
    background: var(--accent-soft);
    border: 1px solid var(--border-strong);
    color: var(--text);
    font-size: 12px;
    font-weight: 700;
  }
  .menu {
    position: absolute;
    right: 0;
    bottom: calc(100% + 10px);
    z-index: 20;
    width: 200px;
    padding: 6px;
    border-radius: var(--radius-m);
    background: var(--surface-2);
    border: 1px solid var(--border-strong);
    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.55);
    animation: pop var(--fast) var(--ease);
    transform-origin: bottom right;
  }
  @keyframes pop {
    from {
      opacity: 0;
      transform: translateY(4px) scale(0.97);
    }
  }
  .head {
    display: block;
    padding: 6px 10px 8px;
    font-size: 12px;
    color: var(--text-3);
  }
  .item {
    display: grid;
    grid-template-columns: 1fr auto 18px;
    align-items: center;
    gap: 10px;
    width: 100%;
    padding: 8px 10px;
    border-radius: var(--radius-s);
    text-align: left;
    color: var(--text-2);
  }
  .item:hover {
    background: var(--hover);
    color: var(--text);
  }
  .item.sel {
    color: var(--text);
    font-weight: 600;
  }
  .rate {
    font-size: 12px;
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  @media (prefers-reduced-motion: reduce) {
    .menu {
      animation: none;
    }
  }
</style>
