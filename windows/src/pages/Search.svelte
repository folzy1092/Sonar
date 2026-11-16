<script lang="ts">
  import { hscroll } from '../lib/hscroll'
  import { edges } from '../lib/edges'
  import { cascade } from '../lib/cascade'
  import { indicator } from '../lib/indicator'
  import EmptyState from '../components/EmptyState.svelte'
  import TrackRow from '../components/TrackRow.svelte'
  import Tile from '../components/Tile.svelte'
  import { compact, tracksText } from '../lib/format'
  import { openRef } from '../app/router.svelte'
  import { search } from '../app/search.svelte'
  import { router } from '../app/router.svelte'
  import { settingsPanel } from './settings-section.svelte'
  import { api, errorText, looksLikeLink, type SearchMore, type Track } from '../lib/api'
  import SearchLink from './SearchLink.svelte'
  import { player } from '../player/player.svelte'
  import { playStation } from '../player/autoplay.svelte'
  import { settings } from '../lib/settings.svelte'

  const tabs = ['Все', 'Треки', 'Артисты', 'Альбомы', 'Плейлисты'] as const
  let tab = $state<(typeof tabs)[number]>('Все')
  const sourceName = $derived(search.source === 'sc' ? 'SoundCloud' : 'Яндекс Музыке')

  let results = $state<Track[]>([])
  let more = $state<SearchMore>({ artists: [], albums: [], playlists: [] })
  let loading = $state(false)
  let error = $state<string | null>(null)
  let seq = 0

  /** Трек из поиска: с «Авто похожими» — как в SoundCloud, он и следом похожие на него;
   *  без них — весь список результатов с этого трека. */
  function playTrack(i: number) {
    if (settings.get('general.similar_autoplay')) void playStation(results[i])
    else void player.playList(results, i, 'search')
  }

  /** Вставили ссылку — вместо поиска карточка того, что за ней (SearchLink). */
  const link = $derived(looksLikeLink(search.query) ? search.query.trim() : null)

  // Поиск с задержкой 350 мс после ввода; устаревшие ответы отбрасываются.
  $effect(() => {
    const q = search.query.trim()
    const src = search.source
    error = null
    if (!q || looksLikeLink(q)) {
      results = []
      more = { artists: [], albums: [], playlists: [] }
      loading = false
      return
    }
    const my = ++seq
    loading = true
    const timer = setTimeout(async () => {
      api
        .searchMore(q, src)
        .then((m) => my === seq && (more = m))
        .catch(() => my === seq && (more = { artists: [], albums: [], playlists: [] }))
      try {
        const found = await api.search(q, src)
        if (my === seq) results = found
      } catch (e) {
        if (my === seq) {
          results = []
          error = errorText(e)
        }
      } finally {
        if (my === seq) loading = false
      }
    }, 350)
    return () => clearTimeout(timer)
  })

  function openServices() {
    settingsPanel.show('services')
  }
</script>

<div class="chips" use:indicator={{ key: tab, kind: 'pill' }}>
  {#each tabs as t (t)}
    <button class="chip" class:on={tab === t} onclick={() => (tab = t)}>{t}</button>
  {/each}
</div>

{#if link}
  <SearchLink url={link} />
{:else if !search.query.trim()}
  <EmptyState icon="search" title="Что включить?" text="Ищи треки в SoundCloud и Яндекс Музыке — или вставь ссылку на трек, альбом или плейлист." />
{:else if error}
  <div class="err">
    <EmptyState icon="key" title="Не получилось" text={error} />
    {#if error.includes('не подключ')}
      <button class="cta" onclick={openServices}>Открыть «Сервисы»</button>
    {/if}
  </div>
{:else if loading && !results.length}
  <div class="skeleton" aria-label="Ищу…">
    {#each { length: 6 } as _, i (i)}<div class="sk"></div>{/each}
  </div>
{:else if !results.length && !more.artists.length && !more.albums.length && !more.playlists.length}
  <EmptyState icon="search" title="Ничего не нашлось" text={`По запросу «${search.query.trim()}» в ${sourceName} пусто.`} />
{:else}
  {@const all = tab === 'Все'}
  {#key tab}<div class="tab-in">
  {#if (all || tab === 'Треки') && results.length}
    <h2>Треки {#if all && results.length > 5}<button class="more" onclick={() => (tab = 'Треки')}>Показать все</button>{/if}</h2>
    <div class="list" class:stale={loading} use:cascade={results}>
      {#each all ? results.slice(0, 5) : results as t, i (t.ref)}
        <TrackRow track={t} index={i} onplay={() => playTrack(i)} />
      {/each}
    </div>
  {/if}
  {#if (all || tab === 'Артисты') && more.artists.length}
    <h2>Артисты</h2>
    <div class:row={all} class:grid={!all} use:cascade={more} use:hscroll use:edges>
      {#each more.artists as a (a.ref)}
        <Tile
          title={a.name}
          subtitle={a.followers != null ? `${compact(a.followers)} подп.` : undefined}
          image={a.avatar_url}
          icon="user"
          round
          onclick={() => openRef(a.ref)}
        />
      {/each}
    </div>
  {/if}
  {#if (all || tab === 'Альбомы') && more.albums.length}
    <h2>Альбомы</h2>
    <div class:row={all} class:grid={!all} use:cascade={more} use:hscroll use:edges>
      {#each more.albums as a (a.ref)}
        <Tile title={a.title} subtitle={a.artist} meta={a.year ? String(a.year) : undefined} image={a.cover_url} icon="disc" onclick={() => openRef(a.ref)} />
      {/each}
    </div>
  {/if}
  {#if (all || tab === 'Плейлисты') && more.playlists.length}
    <h2>Плейлисты</h2>
    <div class:row={all} class:grid={!all} use:cascade={more} use:hscroll use:edges>
      {#each more.playlists as p (p.ref)}
        <Tile title={p.title} subtitle={p.owner} meta={p.track_count ? tracksText(p.track_count) : undefined} image={p.cover_url} onclick={() => openRef(p.ref)} />
      {/each}
    </div>
  {/if}
  {#if !all && ((tab === 'Треки' && !results.length) || (tab === 'Артисты' && !more.artists.length) || (tab === 'Альбомы' && !more.albums.length) || (tab === 'Плейлисты' && !more.playlists.length))}
    <EmptyState icon="search" title="Ничего не нашлось" text={`${tab} по запросу «${search.query.trim()}» не нашлись.`} />
  {/if}
  </div>{/key}
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
    /* сама капсула — индикатор (lib/indicator), он переезжает между чипами */
    background: transparent;
    border-color: transparent;
    color: var(--accent-ink);
  }
  .chips :global(.tab-ind.pill) {
    background: var(--accent);
  }
  h2 {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    margin: 22px 0 10px;
    font-size: calc(20px * var(--fs, 1));
    font-weight: 800;
  }
  .more {
    font-family: var(--font);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 400;
    color: var(--text-2);
  }
  .more:hover {
    color: var(--text);
  }
  .row {
    --fade: 64px;
    display: flex;
    gap: 18px;
    overflow-x: auto;
    padding-bottom: 4px;
    scrollbar-width: none;
  }
  .row::-webkit-scrollbar {
    display: none;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
    gap: 18px;
  }
  .grid :global(.tile) {
    width: auto;
  }
  .list {
    display: flex;
    flex-direction: column;
    transition: opacity var(--fast) var(--ease);
  }
  .list.stale {
    opacity: 0.6;
  }
  .err {
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .cta {
    height: 38px;
    padding: 0 18px;
    margin-top: -32px;
    border-radius: 999px;
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 700;
  }
  .skeleton {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-top: 22px;
  }
  .sk {
    height: 54px;
    border-radius: var(--radius-m);
    background: linear-gradient(90deg, var(--plate), var(--hover), var(--plate));
    background-size: 200% 100%;
    animation: shimmer 1.2s linear infinite;
  }
  @keyframes shimmer {
    to {
      background-position: -200% 0;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .sk {
      animation: none;
    }
  }
</style>
