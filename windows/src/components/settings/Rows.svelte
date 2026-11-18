<script lang="ts" generics="T extends string | number">
  // Выбор строками (SETTINGS_NEXT «Аудио»): значок, название и подпись слева, справа — крупное число и
  // мелкая единица («320 kbps»). Выбранная строка светлее, у неё значок в акценте. Без прокрутки вбок:
  // сколько вариантов, столько строк.
  import Icon from '../Icon.svelte'
  import type { IconName } from '../icons'

  interface Option {
    id: T
    label: string
    sub?: string
    icon?: IconName
    /** Крупно справа (число), `unit` — мелко рядом. */
    value?: string
    unit?: string
  }

  interface Props {
    title?: string
    hint?: string
    value: T | null
    options: Option[]
    onchange?: (v: T) => void
  }
  let { title, hint, value, options, onchange }: Props = $props()
</script>

<div class="block">
  {#if title}<b class="title">{title}</b>{/if}
  {#if hint}<small>{hint}</small>{/if}
  <div class="rows" role="radiogroup" aria-label={title}>
    {#each options as o (o.id)}
      <button class="row" class:on={value === o.id} role="radio" aria-checked={value === o.id} onclick={() => onchange?.(o.id)}>
        {#if o.icon}<span class="ic"><Icon name={o.icon} size={17} /></span>{/if}
        <span class="txt">
          <span class="label">{o.label}</span>
          {#if o.sub}<span class="sub">{o.sub}</span>{/if}
        </span>
        {#if o.value}
          <span class="num"><b>{o.value}</b>{#if o.unit}<i>{o.unit}</i>{/if}</span>
        {/if}
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
  .rows {
    display: flex;
    flex-direction: column;
    gap: 4px;
    margin-top: 9px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 48px;
    padding: 7px 14px 7px 12px;
    border-radius: 12px;
    background: transparent;
    color: var(--text-3);
    text-align: left;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .row:hover {
    background: var(--hover);
    color: var(--text-2);
  }
  .row:active {
    transform: scale(0.985);
  }
  .row.on {
    background: var(--surface-3);
    color: var(--text);
  }
  .ic {
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    border-radius: 9px;
    background: var(--plate);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .on .ic {
    background: var(--accent);
    color: var(--accent-ink);
  }
  .txt {
    display: flex;
    flex: 1;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
  }
  .label {
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .on .label {
    color: var(--text);
  }
  .sub {
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-3);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .num {
    display: flex;
    align-items: baseline;
    gap: 4px;
    flex: none;
  }
  .num b {
    font-size: calc(20px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    letter-spacing: -0.02em;
  }
  .num i {
    font-size: calc(11px * var(--fs, 1));
    font-style: normal;
    color: var(--text-3);
  }
  @media (prefers-reduced-motion: reduce) {
    .row:active {
      transform: none;
    }
  }
</style>
