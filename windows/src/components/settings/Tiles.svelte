<script lang="ts" generics="T extends string">
  // Крупные плитки-картинки (NEXT_PROMPT «Этап 0» п. 5): на каждой — схема окна, под ней короткое
  // название. Выбранная — в рамке цвета акцента; рамка переезжает к новой плитке (`use:indicator`).
  import WindowDiagram from './WindowDiagram.svelte'
  import type { DiagramInput } from '../../lib/window-diagram'
  import { indicator } from '../../lib/indicator'

  interface Option {
    id: T
    label: string
    sub?: string
    diagram: DiagramInput
  }
  interface Props {
    title: string
    hint?: string
    value: T
    options: Option[]
    onchange: (v: T) => void
    /** Наименьшая ширина плитки — столько, сколько влезет в ряд. */
    min?: number
  }
  let { title, hint, value, options, onchange, min = 132 }: Props = $props()
</script>

<div class="block">
  <b class="title">{title}</b>
  {#if hint}<small>{hint}</small>{/if}
  <div class="tiles" role="radiogroup" aria-label={title} style:--min="{min}px" use:indicator={{ key: value, kind: 'pill' }}>
    {#each options as o (o.id)}
      <button class="tile" class:on={value === o.id} role="radio" aria-checked={value === o.id} onclick={() => onchange(o.id)}>
        <WindowDiagram input={o.diagram} active={value === o.id} />
        <span class="label">{o.label}</span>
        {#if o.sub}<span class="sub">{o.sub}</span>{/if}
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
  .tiles {
    position: relative;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(var(--min), 1fr));
    gap: 10px;
    margin-top: 10px;
    padding: 3px;
  }
  .tile {
    display: flex;
    flex-direction: column;
    gap: 7px;
    padding: 10px 10px 9px;
    border-radius: 14px;
    background: var(--plate);
    color: var(--text-2);
    text-align: left;
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
  }
  .label {
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text);
  }
  .sub {
    margin-top: -4px;
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-3);
  }
  /* рамка выбранной плитки — тот же переезжающий индикатор, что у вкладок, только контуром;
     плитки бывают в несколько рядов — рамка едет и по высоте */
  .tiles :global(.tab-ind.pill) {
    border-radius: 14px;
    background: transparent;
    box-shadow: 0 0 0 2px var(--accent);
    transition:
      transform var(--normal) var(--ease),
      top var(--normal) var(--ease),
      width var(--normal) var(--ease),
      height var(--normal) var(--ease),
      opacity var(--fast) var(--ease);
  }
  .tiles :global(.tab-ind.pill) {
    z-index: 2;
  }
</style>
