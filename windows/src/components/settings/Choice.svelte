<script lang="ts" generics="T extends string | number">
  // Сегменты (pc/Screenshot_7 «Ничего / Трек / Очередь», 16 «В начало / В конец»): капсула выбранного
  // переезжает (lib/indicator). `wide` — сегменты под названием; `icons` — только значки (позиция,
  // выравнивание). Вариант с `soon` неактивен («скоро» во всплывающей подсказке).
  import { indicator } from '../../lib/indicator'
  import Icon from '../Icon.svelte'
  import type { IconName } from '../icons'
  import Soon from './Soon.svelte'
  import Flag from '../Flag.svelte'

  interface Props {
    title: string
    hint?: string
    value: T
    options: { id: T; label: string; icon?: IconName; flag?: string; soon?: boolean; sub?: string; font?: string }[]
    onchange?: (v: T) => void
    wide?: boolean
    icons?: boolean
    /** Сегменты на всю ширину (с `wide`). */
    fill?: boolean
    soon?: boolean
  }
  let { title, hint, value, options, onchange, wide = false, icons = false, fill = false, soon = false }: Props = $props()
</script>

<div class="row" class:wide class:fill>
  <span class="text">
    <b>{title}{#if soon}<Soon />{/if}</b>
    {#if hint}<small>{hint}</small>{/if}
  </span>
  <div class="seg" class:icons class:dim={soon} use:indicator={{ key: value, kind: 'pill' }}>
    {#each options as o (o.id)}
      <button
        class:on={value === o.id}
        class:off={o.soon}
        disabled={soon || o.soon}
        onclick={() => onchange?.(o.id)}
        title={o.soon ? `${o.label} — скоро` : o.label}
        aria-label={o.label}
      >
        {#if o.flag}<Flag lang={o.flag} size={17} />{:else if o.icon}<Icon name={o.icon} size={15} />{/if}
        {#if !icons}<span>{o.label}{#if o.sub}<i>{o.sub}</i>{/if}</span>{/if}
      </button>
    {/each}
  </div>
</div>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 9px 0;
  }
  .row.wide {
    flex-direction: column;
    align-items: stretch;
    gap: 10px;
  }
  .text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }
  b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  small {
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
  .seg {
    display: flex;
    flex-shrink: 0;
    padding: 3px;
    border-radius: 10px;
    border: 1px solid var(--border);
  }
  .wide .seg {
    align-self: flex-start;
    max-width: 100%;
  }
  .wide.fill .seg {
    align-self: stretch;
  }
  .seg.dim {
    opacity: 0.45;
  }
  .seg :global(.tab-ind.pill) {
    border-radius: 7px;
    background: var(--surface-3);
  }
  button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    flex: 1;
    height: 30px;
    padding: 0 12px;
    border-radius: 7px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    white-space: nowrap;
    transition: color var(--fast) var(--ease);
  }
  .icons button {
    width: 34px;
    padding: 0;
  }
  button:hover:not(:disabled) {
    color: var(--text-2);
  }
  button.on {
    color: var(--text);
    font-weight: 600;
  }
  button.off {
    opacity: 0.4;
  }
  button:disabled {
    cursor: default;
  }
  i {
    margin-left: 4px;
    font-style: normal;
    font-size: calc(10px * var(--fs, 1));
    font-weight: 500;
    color: var(--text-3);
  }
</style>
