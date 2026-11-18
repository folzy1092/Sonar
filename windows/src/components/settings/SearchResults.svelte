<script lang="ts">
  // Найденные настройки (NEXT_PROMPT «Этап 0» п. 4): путь «Раздел · Подраздел», название и подсказка
  // с подсветкой совпадений. Клик — панель открывает раздел и докручивает до пункта (SettingsPanel).
  import Icon from '../Icon.svelte'
  import { cascade } from '../../lib/cascade'
  import { markRanges, searchSettings, type CatalogEntry } from '../../lib/settings-catalog'
  import { SUBS, TABS } from '../../pages/settings-section.svelte'
  import { t } from '../../lib/i18n.svelte'

  let { query, onpick }: { query: string; onpick: (entry: CatalogEntry) => void } = $props()

  const hits = $derived(searchSettings(query, (ru) => t(ru)))

  function path(e: CatalogEntry): string {
    const tab = t(TABS.find((x) => x.id === e.tab)?.title ?? '')
    const sub = SUBS[e.tab].find((s) => s.id === e.sub)
    return !sub || SUBS[e.tab].length === 1 ? tab : `${tab} · ${t(sub.title)}`
  }
</script>

{#snippet marked(text: string)}
  {#each markRanges(text, query) as piece, i (i)}{#if piece.mark}<mark>{piece.text}</mark>{:else}{piece.text}{/if}{/each}
{/snippet}

{#if hits.length}
  <ul class="hits" use:cascade={query}>
    {#each hits as hit (hit.entry)}
      <li>
        <button class="hit" onclick={() => onpick(hit.entry)}>
          <span class="path">{path(hit.entry)}</span>
          <span class="name">{@render marked(t(hit.entry.title))}</span>
          {#if hit.entry.hint}<span class="hint">{@render marked(t(hit.entry.hint))}</span>{/if}
          <span class="go"><Icon name="chevronRight" size={16} /></span>
        </button>
      </li>
    {/each}
  </ul>
{:else}
  <div class="empty tab-in">
    <b>{t('Ничего не нашлось')}</b>
    <small>{t('Попробуй другое слово — например, «тема», «кроссфейд» или «трей»')}</small>
  </div>
{/if}

<style>
  .hits {
    display: flex;
    flex-direction: column;
    gap: 4px;
    max-width: 760px;
    margin: 0 auto;
    padding: 0;
    list-style: none;
  }
  .hit {
    position: relative;
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    width: 100%;
    padding: 10px 14px;
    gap: 2px 12px;
    border-radius: var(--radius-l);
    text-align: left;
    transition: background var(--fast) var(--ease);
  }
  .hit:hover,
  .hit:focus-visible {
    background: var(--hover);
  }
  .path {
    grid-column: 1;
    font-size: calc(11px * var(--fs, 1));
    font-weight: 600;
    letter-spacing: 0.02em;
    color: var(--text-3);
  }
  .name {
    grid-column: 1;
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
    color: var(--text);
  }
  .hint {
    grid-column: 1;
    overflow: hidden;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .go {
    grid-column: 2;
    grid-row: 1 / span 3;
    align-self: center;
    color: var(--text-3);
    opacity: 0;
    translate: -4px 0;
    transition:
      opacity var(--fast) var(--ease),
      translate var(--fast) var(--ease);
  }
  .hit:hover .go {
    opacity: 1;
    translate: 0 0;
  }
  mark {
    padding: 0 1px;
    border-radius: 3px;
    background: color-mix(in srgb, var(--accent) 32%, transparent);
    color: inherit;
  }
  .empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    padding: 48px 16px;
    text-align: center;
  }
  .empty b {
    font-size: calc(15px * var(--fs, 1));
  }
  .empty small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
</style>
