<script lang="ts" generics="T extends string | number">
  // Карточки-выбор (pc/Screenshot_4 «Качество», 6 «Стиль плеера», 8 «Стиль / Фон / Прогресс»): значок,
  // название, подпись. `scroll` — ряд листается вбок, как у Dotify (три карточки на ширину панели);
  // `list` — вертикальный список строк (pc/31 «Стиль вкладок»). Вариант с `soon` неактивен.
  import Icon from '../Icon.svelte'
  import type { IconName } from '../icons'
  import Soon from './Soon.svelte'
  import { hscroll } from '../../lib/hscroll'
  import { edges } from '../../lib/edges'
  import { t } from '../../lib/i18n.svelte'

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
  <!-- плитки настроек (качество, устройство вывода…) листаются колесом вбок; пока курсор над
       рядом, страница не едет даже у края (решение владельца 2026-11-17) -->
  <div class="cards" class:scroll class:list style:--cols={cols} use:hscroll={{ wheel: true, trap: scroll }} use:edges>
    {#each options as o (o.id)}
      <button
        class="card"
        class:on={value === o.id}
        class:off={o.soon}
        disabled={soon || o.soon}
        onclick={() => onchange?.(o.id)}
        title={o.soon ? t('{label} — скоро', { label: o.label }) : o.label}
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
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  small {
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
  /* не больше `--cols` в ряд и не уже 112px: в узком окне карточки переносятся */
  .cards {
    --gap: 8px;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(100%, max(112px, (100% - (var(--cols) - 1) * var(--gap)) / var(--cols))), 1fr));
    gap: var(--gap);
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
    flex: 0 0 max(124px, calc((100% - 16px) / 3));
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
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .list .label {
    font-size: calc(13px * var(--fs, 1));
  }
  .sub {
    font-size: calc(10px * var(--fs, 1));
    color: var(--text-3);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .list .sub {
    font-size: calc(11px * var(--fs, 1));
  }
</style>
