<script lang="ts" generics="T extends string | number">
  // Сегменты (pc/Screenshot_7 «Ничего / Трек / Очередь», 16 «В начало / В конец»): капсула выбранного
  // переезжает (lib/indicator). `wide` — сегменты под названием; `icons` — только значки (позиция,
  // выравнивание). Вариант с `soon` неактивен («скоро» во всплывающей подсказке). `preview` — живой пример
  // между названием и сегментами (с `wide`: скругление, кнопки окна).
  // Узкое окно: сегменты не влезают рядом с названием — уходят под него на всю ширину и переносятся
  // рядами (общая раскладка settings-row.css); капсула индикатора ездит и между рядами.
  import type { Snippet } from 'svelte'
  import './settings-row.css'
  import { indicator } from '../../lib/indicator'
  import Icon from '../Icon.svelte'
  import type { IconName } from '../icons'
  import Soon from './Soon.svelte'
  import Flag from '../Flag.svelte'
  import { t } from '../../lib/i18n.svelte'

  interface Props {
    title: string
    hint?: string
    value: T
    /** `svg` — готовая разметка значка (знак сервиса из lib/service-icons). */
    options: { id: T; label: string; icon?: IconName; flag?: string; svg?: string; soon?: boolean; sub?: string; font?: string }[]
    onchange?: (v: T) => void
    wide?: boolean
    icons?: boolean
    /** Сегменты на всю ширину (с `wide`). */
    fill?: boolean
    soon?: boolean
    preview?: Snippet
  }
  let { title, hint, value, options, onchange, wide = false, icons = false, fill = false, soon = false, preview }: Props = $props()
</script>

<div class="set-row row" class:wide class:fill>
  <span class="set-text">
    <b>{title}{#if soon}<Soon />{/if}</b>
    {#if hint}<small>{hint}</small>{/if}
  </span>
  {#if preview}{@render preview()}{/if}
  <div class="seg" class:icons class:dim={soon} use:indicator={{ key: value, kind: 'pill' }}>
    {#each options as o (o.id)}
      <button
        class:on={value === o.id}
        class:off={o.soon}
        disabled={soon || o.soon}
        onclick={() => onchange?.(o.id)}
        title={o.soon ? t('{label} — скоро', { label: o.label }) : o.label}
        aria-label={o.label}
      >
        {#if o.flag}<Flag lang={o.flag} size={18} />{:else if o.svg}<span class="svg" aria-hidden="true">{@html o.svg}</span>{:else if o.icon}<Icon name={o.icon} size={15} />{/if}
        {#if !icons}<span>{o.label}{#if o.sub}<i>{o.sub}</i>{/if}</span>{/if}
      </button>
    {/each}
  </div>
</div>

<style>
  /* `wide` — всегда под названием: колонка, сегменты своей ширины (`fill` — во всю) */
  .row.wide {
    flex-direction: column;
    flex-wrap: nowrap;
    align-items: stretch;
  }
  .wide .set-text {
    flex: none;
  }
  .seg {
    position: relative;
    display: flex;
    flex-wrap: wrap;
    flex: 1 0 auto;
    max-width: 100%;
    min-width: 0;
    padding: 3px;
    border-radius: 10px;
    border: 1px solid var(--border);
  }
  .wide .seg {
    flex: none;
    align-self: flex-start;
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
    flex: 1 0 auto;
    min-width: 0;
    height: 30px;
    padding: 0 12px;
    border-radius: 7px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    white-space: nowrap;
    transition: color var(--fast) var(--ease);
  }
  /* только значки — компактный ряд своей ширины и под названием */
  .seg.icons {
    flex: 0 1 auto;
  }
  .icons button {
    flex: 0 0 34px;
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
  .svg {
    display: grid;
    width: 16px;
    height: 16px;
  }
  .svg :global(svg) {
    width: 100%;
    height: 100%;
  }
</style>
