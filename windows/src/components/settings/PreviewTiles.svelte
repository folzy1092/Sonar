<script lang="ts" generics="T extends string">
  // Карточки-превью сеткой (SETTINGS_NEXT «Общие приёмы вида»): сверху живой рисунок варианта, под ним
  // название. Все варианты видны сразу — без ряда вбок; рамка выбранной переезжает (`use:indicator`).
  import type { Snippet } from 'svelte'
  import { indicator } from '../../lib/indicator'

  interface Props {
    title?: string
    hint?: string
    value: T
    options: { id: T; label: string }[]
    onchange: (v: T) => void
    /** Рисунок варианта: id и выбран ли он. */
    tile: Snippet<[T, boolean]>
    /** Сколько карточек в ряд. */
    cols?: number
  }
  let { title, hint, value, options, onchange, tile, cols = 4 }: Props = $props()
</script>

<div class="block">
  {#if title}<b class="title">{title}</b>{/if}
  {#if hint}<small>{hint}</small>{/if}
  <div class="grid" role="radiogroup" aria-label={title} style:--cols={cols} use:indicator={{ key: value, kind: 'pill' }}>
    {#each options as o (o.id)}
      <button class="tile" class:on={value === o.id} role="radio" aria-checked={value === o.id} onclick={() => onchange(o.id)}>
        <span class="pic">{@render tile(o.id, value === o.id)}</span>
        <span class="label">{o.label}</span>
      </button>
    {/each}
  </div>
</div>

<style>
  .block {
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 9px 0;
  }
  .title {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  small {
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
  .grid {
    position: relative;
    display: grid;
    grid-template-columns: repeat(var(--cols), minmax(0, 1fr));
    gap: 8px;
    margin-top: 10px;
    padding: 3px;
  }
  .tile {
    display: flex;
    flex-direction: column;
    gap: 7px;
    min-width: 0;
    padding: 8px 8px 7px;
    border-radius: 13px;
    background: var(--surface-2);
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .tile:hover {
    background: var(--hover);
  }
  .tile:active {
    transform: scale(0.97);
  }
  .tile.on {
    background: var(--surface-3);
    color: var(--text);
  }
  .pic {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    height: 54px;
    overflow: hidden;
    border-radius: 9px;
    background: var(--bg);
  }
  .label {
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    text-align: center;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    transition: font-weight var(--fast) var(--ease);
  }
  .on .label {
    font-weight: 700;
  }
  .grid :global(.tab-ind.pill) {
    z-index: 2;
    border-radius: 13px;
    background: transparent;
    box-shadow: 0 0 0 2px var(--accent);
    pointer-events: none;
    transition:
      transform var(--normal) var(--ease),
      top var(--normal) var(--ease),
      width var(--normal) var(--ease),
      height var(--normal) var(--ease),
      opacity var(--fast) var(--ease);
  }
  @media (prefers-reduced-motion: reduce) {
    .tile:active {
      transform: none;
    }
  }
</style>
