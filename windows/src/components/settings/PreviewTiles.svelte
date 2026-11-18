<script lang="ts" generics="T extends string">
  // Карточки-превью сеткой (SETTINGS_NEXT «Общие приёмы вида»): сверху живой рисунок варианта, под ним
  // название. Все варианты видны сразу — без ряда вбок; рамка выбранной переезжает (`use:indicator`).
  // Если `value` — список, можно выбрать несколько: рамка и галочка у каждой выбранной, без переезда.
  import type { Snippet } from 'svelte'
  import { indicator } from '../../lib/indicator'

  interface Props {
    title?: string
    hint?: string
    /** Один вариант — или список, тогда выбор множественный и `onchange` получает нажатый вариант. */
    value: T | readonly T[]
    options: { id: T; label: string }[]
    onchange: (v: T) => void
    /** Рисунок варианта: id и выбран ли он. */
    tile: Snippet<[T, boolean]>
    /** Сколько карточек в ряд. */
    cols?: number
  }
  let { title, hint, value, options, onchange, tile, cols = 4 }: Props = $props()

  const multi = $derived(Array.isArray(value))
  const isOn = (id: T) => (Array.isArray(value) ? value.includes(id) : value === id)
</script>

<div class="block">
  {#if title}<b class="title">{title}</b>{/if}
  {#if hint}<small>{hint}</small>{/if}
  <div class="grid" role={multi ? 'group' : 'radiogroup'} aria-label={title} style:--cols={cols} use:indicator={{ key: multi ? null : value, kind: 'pill' }}>
    {#each options as o (o.id)}
      {@const on = isOn(o.id)}
      <button
        class="tile"
        class:on={on && !multi}
        class:picked={on && multi}
        role={multi ? 'checkbox' : 'radio'}
        aria-checked={on}
        onclick={() => onchange(o.id)}
      >
        <span class="pic">
          {@render tile(o.id, on)}
          {#if multi}
            <span class="check" class:shown={on} aria-hidden="true">
              <svg viewBox="0 0 12 12"><path d="M2.5 6.2 5 8.6l4.6-5" /></svg>
            </span>
          {/if}
        </span>
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
      transform var(--fast) var(--ease),
      box-shadow var(--normal) var(--ease);
  }
  .tile:hover {
    background: var(--hover);
  }
  .tile:active {
    transform: scale(0.97);
  }
  .tile.on,
  .tile.picked {
    background: var(--surface-3);
    color: var(--text);
  }
  /* множественный выбор: рамка у каждой выбранной, загорается на месте */
  .tile.picked {
    box-shadow: 0 0 0 2px var(--accent);
  }
  .check {
    position: absolute;
    top: 5px;
    right: 5px;
    display: grid;
    place-items: center;
    width: 16px;
    height: 16px;
    border-radius: 50%;
    background: var(--accent);
    opacity: 0;
    transform: scale(0.4);
    transition:
      opacity var(--fast) var(--ease),
      transform var(--normal) var(--ease);
  }
  .check.shown {
    opacity: 1;
    transform: scale(1);
  }
  .check svg {
    width: 10px;
    height: 10px;
    fill: none;
    stroke: var(--accent-ink);
    stroke-width: 1.8;
    stroke-linecap: round;
    stroke-linejoin: round;
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
  .on .label,
  .picked .label {
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
    .check {
      transform: none;
    }
  }
</style>
