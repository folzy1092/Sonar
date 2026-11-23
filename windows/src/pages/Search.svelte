<script lang="ts">
  import type { Snippet } from 'svelte'
  import Shelf from '../components/Shelf.svelte'
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
  import { api, errorText, looksLikeLink, rawError, type SearchMore, type Track } from '../lib/api'
  import SearchLink from './SearchLink.svelte'
  import { player } from '../player/player.svelte'
  import { playStation } from '../player/autoplay.svelte'
  import { settings } from '../lib/settings.svelte'
  import { searchHistory } from '../lib/search-history.svelte'
  import { t } from '../lib/i18n.svelte'
  import { byId, type ServiceId } from '../lib/services'
  import { mergeMore, mergeTracks, searchOrder } from '../lib/unified-search'
  import { offline } from '../lib/offline.svelte'
  import { searchOffline } from '../lib/offline-core'

  /** Сколько файлов с компьютера показать в поиске. */
  const LOCAL_LIMIT = 20
  /** Сколько треков показать в офлайн-поиске (docs/OFFLINE.md §8.3). */
  const OFFLINE_LIMIT = 100
  const tabs = ['Все', 'Треки', 'Артисты', 'Альбомы', 'Плейлисты'] as const
  let tab = $state<(typeof tabs)[number]>('Все')
  /** Какая вкладка на деле: в офлайне вкладок нет — только треки целиком. */
  const view = $derived(offline.on ? 'Треки' : tab)
  const sourceName = $derived(search.source === 'all' ? t('подключённых сервисах') : t(byId(search.source)?.nameIn ?? 'Яндекс Музыке'))

  let results = $state<Track[]>([])
  /** Совпадения среди файлов «Папок с музыкой» — отдельным блоком над результатами сервиса. */
  let localHits = $state<Track[]>([])
  let more = $state<SearchMore>({ artists: [], albums: [], playlists: [] })
  let loading = $state(false)
  let error = $state<string | null>(null)
  /** Сервис не подключён (узнаём по исходному тексту ошибки, на любом языке) — кнопка «Сервисы». */
  let notConnected = $state(false)
  let seq = 0

  /** Трек из поиска: с «Авто похожими» — как в SoundCloud, он и следом похожие на него;
   *  без них — весь список результатов с этого трека. */
  function playTrack(i: number) {
    const t = results[i]
    if (t) searchHistory.add({ kind: 'track', query: search.query, ref: t.ref, title: t.title, subtitle: t.artist, cover_url: t.cover_url })
    if (settings.get('general.similar_autoplay')) void playStation(results[i])
    else void player.playList(results, i, 'search')
  }

  /** Вставили ссылку — вместо поиска карточка того, что за ней (SearchLink). */
  // в офлайне ссылку не открыть — ищем её текст среди своего, как обычный запрос
  const link = $derived(!offline.on && looksLikeLink(search.query) ? search.query.trim() : null)

  // Поиск с задержкой 350 мс после ввода; устаревшие ответы отбрасываются.
  $effect(() => {
    const q = search.query.trim()
    const src = search.source
    const off = offline.on
    error = null
    if (!q || (!off && looksLikeLink(q))) {
      results = []
      localHits = []
      more = { artists: [], albums: [], playlists: [] }
      loading = false
      return
    }
    const my = ++seq
    loading = true
    const timer = setTimeout(async () => {
      if (off) {
        await searchLocalOnly(q, my)
        return
      }
      api
        .localSearch(q, LOCAL_LIMIT)
        .then((found) => my === seq && (localHits = found))
        .catch(() => my === seq && (localHits = []))
      if (src === 'all') {
        await searchAll(q, my)
        return
      }
      api
        .searchMore(q, src)
        .then((m) => my === seq && (more = m))
        .catch(() => my === seq && (more = { artists: [], albums: [], playlists: [] }))
      try {
        const found = await api.search(q, src)
        if (my === seq) {
          results = found
          // запрос с результатами — в историю (только если 1.2 с его не меняли)
          if (found.length) setTimeout(() => my === seq && searchHistory.add({ kind: 'query', query: q }), 1200)
        }
      } catch (e) {
        if (my === seq) {
          results = []
          error = errorText(e)
          notConnected = rawError(e).includes('не подключ')
        }
      } finally {
        if (my === seq) loading = false
      }
    }, 350)
    return () => clearTimeout(timer)
  })

  /** Единый поиск: все сервисы параллельно, выдача пересобирается по мере ответов — предпочтительный
   *  сервис всегда сверху, повторы склеиваются (lib/unified-search.ts). Не подключён — молча пропуск. */
  async function searchAll(q: string, my: number) {
    const order = searchOrder(settings.get('search.preferred'), settings.get('audio.fallback_order'))
    const tracks: Partial<Record<ServiceId, Track[]>> = {}
    const extra: Partial<Record<ServiceId, SearchMore>> = {}
    let failed = 0
    let lastError: unknown = null
    const one = async (id: ServiceId) => {
      api
        .searchMore(q, id)
        .then((m) => {
          extra[id] = m
          if (my === seq) more = mergeMore(extra, order)
        })
        .catch(() => {})
      try {
        tracks[id] = await api.search(q, id)
        if (my === seq) results = mergeTracks(tracks, order)
      } catch (e) {
        failed++
        lastError = e
      }
    }
    await Promise.all(order.map(one))
    if (my !== seq) return
    results = mergeTracks(tracks, order)
    if (failed === order.length && lastError) {
      error = errorText(lastError)
      notConnected = true
    } else if (results.length) setTimeout(() => my === seq && searchHistory.add({ kind: 'query', query: q }), 1200)
    loading = false
  }

  /** Офлайн: только скачанное и локальное, без сети и без вкладок сервисов. */
  async function searchLocalOnly(q: string, my: number) {
    localHits = []
    more = { artists: [], albums: [], playlists: [] }
    try {
      const found = searchOffline(await offline.pool(), q, OFFLINE_LIMIT)
      if (my === seq) results = found
    } catch (e) {
      if (my === seq) {
        results = []
        error = errorText(e)
      }
    } finally {
      if (my === seq) loading = false
    }
  }

  function playLocal(i: number) {
    void player.playList(localHits, i, 'search')
  }

  function openServices() {
    settingsPanel.show('services')
  }
</script>

{#snippet localBlock(short: boolean)}
  {#if localHits.length}
    <h2>{t('На этом компьютере')} {#if short && localHits.length > 3}<button class="more" onclick={() => (tab = 'Треки')}>{t('Показать все')}</button>{/if}</h2>
    <div class="list" use:cascade={localHits}>
      {#each short ? localHits.slice(0, 3) : localHits as lt, i (lt.ref)}
        <TrackRow track={lt} onplay={() => playLocal(i)} />
      {/each}
    </div>
  {/if}
{/snippet}

{#if !link && !offline.on}
  <div class="chips" use:indicator={{ key: tab, kind: 'pill' }}>
    {#each tabs as tb (tb)}
      <button class="chip" class:on={tab === tb} onclick={() => (tab = tb)}>{t(tb)}</button>
    {/each}
  </div>
{/if}

{#if link}
  <SearchLink url={link} />
{:else if offline.on && (!search.query.trim() || (!loading && !results.length))}
  <EmptyState
    icon="wifiOff"
    title={search.query.trim() ? t('Ничего не нашлось') : t('Офлайн-режим')}
    text={t('В офлайне ищем только среди скачанного и локального.')}
  />
{:else if !search.query.trim()}
  <EmptyState icon="search" title={t('Что включить?')} text={t('Ищи треки в SoundCloud и Яндекс Музыке — или вставь ссылку на трек, альбом или плейлист.')} />
{:else if error}
  {@render localBlock(false)}
  <div class="err">
    <EmptyState icon="key" title={t('Не получилось')} text={error} />
    {#if notConnected}
      <button class="cta" onclick={openServices}>{t('Открыть «Сервисы»')}</button>
    {/if}
  </div>
{:else if loading && !results.length}
  <div class="skeleton" aria-label={t('Ищу…')}>
    {#each { length: 6 } as _, i (i)}<div class="sk"></div>{/each}
  </div>
{:else if !results.length && !localHits.length && !more.artists.length && !more.albums.length && !more.playlists.length}
  <EmptyState icon="search" title={t('Ничего не нашлось')} text={t('По запросу «{query}» в {source} пусто.', { query: search.query.trim(), source: sourceName })} />
{:else}
  {@const all = view === 'Все'}
  {#key view}<div class="tab-in">
  {#if all || view === 'Треки'}{@render localBlock(all)}{/if}
  {#if (all || view === 'Треки') && results.length}
    <h2>{t('Треки')} {#if all && results.length > 5}<button class="more" onclick={() => (tab = 'Треки')}>{t('Показать все')}</button>{/if}</h2>
    <div class="list" class:stale={loading} use:cascade={results}>
      {#each all ? results.slice(0, 5) : results as t, i (t.ref)}
        <TrackRow track={t} index={i} onplay={() => playTrack(i)} />
      {/each}
    </div>
  {/if}
  {#if (all || view === 'Артисты') && more.artists.length}
    <h2>{t('Артисты')}</h2>
    {@render rowOrGrid(all, artistsTiles)}
  {/if}
  {#if (all || view === 'Альбомы') && more.albums.length}
    <h2>{t('Альбомы')}</h2>
    {@render rowOrGrid(all, albumsTiles)}
  {/if}
  {#if (all || view === 'Плейлисты') && more.playlists.length}
    <h2>{t('Плейлисты')}</h2>
    {@render rowOrGrid(all, playlistsTiles)}
  {/if}
  {#if !all && ((view === 'Треки' && !results.length && !localHits.length) || (view === 'Артисты' && !more.artists.length) || (view === 'Альбомы' && !more.albums.length) || (view === 'Плейлисты' && !more.playlists.length))}
    <EmptyState icon="search" title={t('Ничего не нашлось')} text={t('{what} по запросу «{query}» не нашлись.', { what: t(view), query: search.query.trim() })} />
  {/if}
  </div>{/key}
{/if}

<!-- «Все»: ряд — полка со стрелками (общая логика стрелок, Shelf); вкладка раздела — сетка -->
{#snippet rowOrGrid(all: boolean, items: Snippet)}
  {#if all}
    <Shelf key={more}>{@render items()}</Shelf>
  {:else}
    <div class="grid" use:cascade={more}>{@render items()}</div>
  {/if}
{/snippet}

{#snippet artistsTiles()}
  {#each more.artists as a (a.ref)}
    <Tile
      title={a.name}
      subtitle={a.followers != null ? t('{n} подп.', { n: compact(a.followers) }) : undefined}
      image={a.avatar_url}
      icon="user"
      round
      onclick={() => (searchHistory.add({ kind: 'artist', query: search.query, ref: a.ref, title: a.name, cover_url: a.avatar_url }), openRef(a.ref))}
    />
  {/each}
{/snippet}

{#snippet albumsTiles()}
  {#each more.albums as a (a.ref)}
    <Tile title={a.title} subtitle={a.artist} meta={a.year ? String(a.year) : undefined} image={a.cover_url} icon="disc" onclick={() => (searchHistory.add({ kind: 'album', query: search.query, ref: a.ref, title: a.title, subtitle: a.artist, cover_url: a.cover_url }), openRef(a.ref))} />
  {/each}
{/snippet}

{#snippet playlistsTiles()}
  {#each more.playlists as p (p.ref)}
    <Tile title={p.title} subtitle={p.owner} meta={p.track_count ? tracksText(p.track_count) : undefined} image={p.cover_url} onclick={() => (searchHistory.add({ kind: 'playlist', query: search.query, ref: p.ref, title: p.title, subtitle: p.owner, cover_url: p.cover_url }), openRef(p.ref))} />
  {/each}
{/snippet}

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
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
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
