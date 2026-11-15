<script lang="ts" generics="T extends string | number">
  // Карточки-выбор (pc/Screenshot_4 «Качество», 6 «Стиль плеера», 8 «Стиль / Фон / Прогресс»): значок,
  // название, подпись. `scroll` — ряд листается вбок, как у Dotify (три карточки на ширину панели);
  // `list` — вертикальный список строк (pc/31 «Стиль вкладок»). Вариант с `soon` неактивен.
  import Icon from '../Icon.svelte'
  import type { IconName } from '../icons'
  import Soon from './Soon.svelte'
  import { hscroll } from '../../lib/hscroll'
  import { edges } from '../../lib/edges'

  interface Props {
    title?: string
    hint?: string
    value: T | null
    options: { id: T; label: string; sub?: string; icon?: IconName; soon?: boolean }[]
    onchange?: (v: T) => void
    cols?: number
    scroll?: boolean
    list?: boolean
    soon?: boolean
  }
  let { title, hint, value, options, onchange, cols = 3, scroll = false, list = false, soon = false }: Props = $props()
</script>

<div class="block">
  {#if title}<b class="title">{title}{#if soon}<Soon />{/if}</b>{/if}
  {#if hint}<small>{hint}</small>{/if}
  <div class="cards" class:scroll class:list style:--cols={cols} use:hscroll use:edges>
    {#each options as o (o.id)}
      <button
        class="card"
        class:on={value === o.id}
        class:off={o.soon}
        disabled={soon || o.soon}
        onclick={() => onchange?.(o.id)}
        title={o.soon ? `${o.label} — скоро` : o.label}
      >
        {#if o.icon}<span class="ic"><Icon name={o.icon} size={list ? 17 : 16} /></span>{/if}
        <span class="txt">
          <span class="label">{o.label}</span>
          {#if o.sub}<span class="sub">{o.sub}</span>{/if}
        </span>
        {#if o.soon && list}<Soon />{/if}
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
    font-size: 14px;
    font-weight: 600;
  }
  small {
    font-size: 12px;
    line-height: 1.45;
    color: var(--text-3);
  }
  .cards {
    display: grid;
    grid-template-columns: repeat(var(--cols), minmax(0, 1fr));
    gap: 8px;
    margin-top: 9px;
  }
  .cards.scroll {
    display: flex;
    overflow-x: auto;
    scrollbar-width: none;
    /* край ряда уходит в тень — видно, что можно листать */
    mask-image: linear-gradient(90deg, #000 88%, transparent);
  }
  .cards.scroll::-webkit-scrollbar {
    display: none;
  }
  .cards.scroll .card {
    flex: 0 0 calc((100% - 16px) / 3);
  }
  .cards.list {
    grid-template-columns: 1fr;
    gap: 6px;
  }
  .card {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    min-height: 72px;
    padding: 12px 8px;
    border-radius: 12px;
    background: var(--plate);
    color: var(--text-2);
    text-align: center;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .list .card {
    flex-direction: row;
    justify-content: flex-start;
    gap: 12px;
    min-height: 54px;
    padding: 8px 12px;
    text-align: left;
  }
  .card:hover:not(:disabled) {
    background: var(--hover);
  }
  .card:active:not(:disabled) {
    transform: scale(0.96);
  }
  .card.on {
    background: var(--surface-3);
    color: var(--text);
  }
  .card.off {
    opacity: 0.45;
  }
  .card:disabled {
    cursor: default;
  }
  .ic {
    display: grid;
    place-items: center;
  }
  .txt {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .list .txt {
    flex: 1;
  }
  .label {
    font-size: 12px;
    font-weight: 600;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .list .label {
    font-size: 13px;
  }
  .sub {
    font-size: 10px;
    color: var(--text-3);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .list .sub {
    font-size: 11px;
  }
</style>
