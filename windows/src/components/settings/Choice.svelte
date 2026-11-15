<script lang="ts" generics="T extends string | number">
  // Выбор из нескольких вариантов капсулами (pc/Screenshot_16 «В начало / В конец», «Экономия ресурсов»):
  // капсула выбранного переезжает (lib/indicator). `wide` — варианты под названием, во всю ширину.
  import { indicator } from '../../lib/indicator'
  import Icon from '../Icon.svelte'
  import type { IconName } from '../icons'

  interface Props {
    title: string
    hint?: string
    value: T
    options: { id: T; label: string; icon?: IconName }[]
    onchange: (v: T) => void
    wide?: boolean
  }
  let { title, hint, value, options, onchange, wide = false }: Props = $props()
</script>

<div class="row" class:wide>
  <span class="text">
    <b>{title}</b>
    {#if hint}<small>{hint}</small>{/if}
  </span>
  <div class="seg" use:indicator={{ key: value, kind: 'pill' }}>
    {#each options as o (o.id)}
      <button class:on={value === o.id} onclick={() => onchange(o.id)} title={o.label}>
        {#if o.icon}<Icon name={o.icon} size={15} />{/if}
        <span>{o.label}</span>
      </button>
    {/each}
  </div>
</div>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 10px 0;
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
    font-size: 14px;
    font-weight: 600;
  }
  small {
    font-size: 12px;
    line-height: 1.45;
    color: var(--text-3);
  }
  .seg {
    display: flex;
    flex-shrink: 0;
    padding: 3px;
    border-radius: 12px;
    background: var(--plate);
    border: 1px solid var(--border);
  }
  .seg :global(.tab-ind.pill) {
    border-radius: 9px;
    background: var(--surface-3);
  }
  button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    flex: 1;
    height: 32px;
    padding: 0 12px;
    border-radius: 9px;
    font-size: 13px;
    color: var(--text-3);
    white-space: nowrap;
    transition: color var(--fast) var(--ease);
  }
  button:hover {
    color: var(--text-2);
  }
  button.on {
    color: var(--text);
    font-weight: 600;
  }
</style>
