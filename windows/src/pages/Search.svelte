<script lang="ts">
  import EmptyState from '../components/EmptyState.svelte'
  import { search } from '../app/search.svelte'

  const tabs = ['Все', 'Треки', 'Артисты', 'Альбомы', 'Плейлисты'] as const
  let tab = $state<(typeof tabs)[number]>('Все')
  const source = $derived(search.source === 'sc' ? 'SoundCloud' : 'Яндекс Музыке')
</script>

<div class="chips">
  {#each tabs as t (t)}
    <button class="chip" class:on={tab === t} onclick={() => (tab = t)}>{t}</button>
  {/each}
</div>

{#if search.query.trim()}
  <EmptyState
    icon="search"
    title={`«${search.query.trim()}»`}
    text={`Поиск по ${source} заработает, когда подключим сервисы (W2).`}
  />
{:else}
  <EmptyState icon="search" title="Что включить?" text="Ищи треки, артистов, альбомы и плейлисты в SoundCloud и Яндекс Музыке." />
{/if}

<style>
  .chips {
    display: flex;
    gap: 8px;
  }
  .chip {
    height: 34px;
    padding: 0 16px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--border);
    color: var(--text-2);
    font-weight: 600;
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .chip:hover {
    color: var(--text);
    background: var(--hover);
  }
  .chip.on {
    background: var(--accent);
    border-color: transparent;
    color: var(--accent-ink);
  }
</style>
