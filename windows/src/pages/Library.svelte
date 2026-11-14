<script lang="ts">
  import IconButton from '../components/IconButton.svelte'
  import Icon from '../components/Icon.svelte'
  import Tile from '../components/Tile.svelte'

  const tabs = ['Все', 'Плейлисты', 'Альбомы', 'Исполнители'] as const
  let tab = $state<(typeof tabs)[number]>('Все')
</script>

<div class="tabs" role="tablist">
  {#each tabs as t (t)}
    <button class="tab" class:on={tab === t} role="tab" aria-selected={tab === t} onclick={() => (tab = t)}>
      {t}
    </button>
  {/each}
</div>

<p class="who">Сервисы не подключены — токены SoundCloud и Яндекса вставляются в настройках.</p>

{#if tab === 'Все' || tab === 'Плейлисты'}
  <section class="block">
    <h2>Плейлисты <Icon name="chevronRight" size={18} /></h2>
    <div class="row">
      <Tile title="Любимые" subtitle="Лайкнутые треки" meta="0 треков" icon="heart" />
      <Tile title="Скачанные" subtitle="Кеш и локальное" meta="0 треков" icon="download" />
      <Tile title="Новый плейлист" subtitle="SoundCloud и Яндекс вместе" icon="plus" ghost />
    </div>
  </section>
{/if}

{#if tab === 'Все' || tab === 'Исполнители'}
  <section class="block">
    <h2>Исполнители <Icon name="chevronRight" size={18} /></h2>
    <div class="row">
      {#each Array.from({ length: 4 }) as _, i (i)}
        <Tile title="—" icon="user" round ghost />
      {/each}
    </div>
  </section>
{/if}

{#if tab === 'Альбомы'}
  <section class="block">
    <h2>Альбомы</h2>
    <p class="hint">Сохранённые альбомы появятся здесь.</p>
  </section>
{/if}

<div class="actions">
  <IconButton icon="plus" label="Создать плейлист" size={16} />
  <IconButton icon="download" label="Импорт плейлистов сервисов" size={16} />
  <IconButton icon="refresh" label="Обновить" size={16} />
</div>

<style>
  .tabs {
    display: flex;
    gap: 18px;
  }
  .tab {
    font-family: var(--font-display);
    font-size: 26px;
    font-weight: 800;
    color: var(--text-3);
    transition: color var(--fast) var(--ease);
  }
  .tab:hover {
    color: var(--text-2);
  }
  .tab.on {
    color: var(--text);
  }
  .who {
    margin: 12px 0 0;
    color: var(--text-2);
  }
  .block {
    margin-top: 28px;
  }
  h2 {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 24px;
    font-weight: 800;
    margin-bottom: 14px;
  }
  h2 :global(svg) {
    color: var(--text-3);
  }
  .row {
    display: flex;
    gap: 18px;
    overflow: hidden;
  }
  .hint {
    color: var(--text-3);
  }
  .actions {
    display: inline-flex;
    gap: 2px;
    margin-top: 32px;
    padding: 4px;
    border-radius: var(--radius-m);
    background: var(--plate);
    border: 1px solid var(--border);
  }
</style>
