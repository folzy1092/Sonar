<script lang="ts">
  import { cascade } from '../lib/cascade'
  import { indicator } from '../lib/indicator'
  // Исполнитель (pc/Screenshot_19): круглый аватар, имя, подписчики; Слушать · Подписаться ·
  // перемешать · в очередь; «Треки» (все, с сортировкой) и «Альбомы». «Подписаться» = лайк исполнителя (вкладка
  // «Исполнители» в медиатеке). Шапка окрашивается в цвет аватара (как тема под обложку).
  import CollectionHeader from '../components/CollectionHeader.svelte'
  import EmptyState from '../components/EmptyState.svelte'
  import Icon from '../components/Icon.svelte'
  import SourceIcon from '../components/SourceIcon.svelte'
  import Tile from '../components/Tile.svelte'
  import TrackRow from '../components/TrackRow.svelte'
  import { api, errorText, type Album, type Artist, type ArtistTrack, type Track } from '../lib/api'
  import { compact } from '../lib/format'
  import { t, tn } from '../lib/i18n.svelte'
  import { byId, serviceOf } from '../lib/services'
  import { library } from '../lib/library.svelte'
  import { openRef, router } from '../app/router.svelte'
  import { player } from '../player/player.svelte'
  import { colorOf } from '../theme/theme.svelte'
  import { css, themeFrom } from '../theme/palette'

  const ref = router.param ?? ''
  /** Сервис исполнителя по ref (lib/services); не распознан — Яндекс, как раньше. */
  const svc = byId(serviceOf(ref)) ?? byId('ym')!
  let artist = $state<Artist | null>(null)
  let top = $state<Track[]>([])
  /** Все треки (решение владельца 2026-11-16: вместо «Популярных» — все, сортировка на выбор). */
  let all = $state.raw<ArtistTrack[] | null>(null)
  let allFailed = $state(false)
  let albums = $state<Album[]>([])
  let error = $state<string | null>(null)
  let tint = $state<string | null>(null)

  type SortId = 'plays' | 'title' | 'released' | 'duration' | 'likes'
  const SORTS: { id: SortId; label: string; asc: boolean }[] = [
    { id: 'plays', label: 'Прослушивания', asc: false },
    { id: 'title', label: 'Название', asc: true },
    { id: 'released', label: 'Дата выхода', asc: false },
    { id: 'duration', label: 'Длительность', asc: false },
    { id: 'likes', label: 'Лайки', asc: false },
  ]
  let sortId = $state<SortId>('plays')
  let asc = $state(false)
  /** Сколько строк видно: свёрнуто — 10, развёрнуто — догружаем по 100 при прокрутке. */
  const FOLD = 10
  let limit = $state(FOLD)

  const followed = $derived(library.isLiked(ref))
  const context = `artist:${ref}`
  const base = $derived<ArtistTrack[]>(all ?? top.map((t) => ({ ...t, likes: null, released: null })))
  // сортировки, для которых нет данных (лайки у Яндекса), не показываем
  const sorts = $derived(
    SORTS.filter((s) =>
      !all ? s.id !== 'likes' && s.id !== 'released' : s.id === 'likes' ? all.some((t) => t.likes != null) : s.id === 'released' ? all.some((t) => t.released) : true,
    ),
  )
  const sorted = $derived.by(() => {
    const list = base.slice()
    // у Яндекса нет числа прослушиваний — его порядок уже «по популярности», не трогаем
    if (sortId === 'plays' && !list.some((t) => t.plays != null)) return asc ? list.reverse() : list
    const k = (t: ArtistTrack): number | string | null =>
      sortId === 'plays'
        ? (t.plays ?? null)
        : sortId === 'likes'
          ? t.likes
          : sortId === 'duration'
            ? t.duration_ms
            : sortId === 'released'
              ? t.released
              : t.title
    list.sort((a, b) => {
      const x = k(a)
      const y = k(b)
      if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1 // пустые — всегда в конце
      const c = typeof x === 'string' ? x.localeCompare(y as string, 'ru', { numeric: true }) : x - (y as number)
      return asc ? c : -c
    })
    return list
  })
  const shown = $derived(sorted.slice(0, limit))
  const expanded = $derived(limit > FOLD)

  function pickSort(id: SortId) {
    if (id === sortId) asc = !asc
    else {
      sortId = id
      asc = SORTS.find((s) => s.id === id)!.asc
    }
  }

  /** Подгрузка следующей сотни, когда низ списка показался на экране. */
  function more(node: HTMLElement) {
    const io = new IntersectionObserver(
      (e) => {
        if (e[0]?.isIntersecting) limit = Math.min(limit + 100, sorted.length)
      },
      { rootMargin: '600px' },
    )
    io.observe(node)
    return { destroy: () => io.disconnect() }
  }

  api
    .artistPage(ref)
    .then((p) => {
      artist = p.artist
      top = p.top
      albums = p.albums
      if (p.artist.avatar_url)
        void colorOf(p.artist.avatar_url).then((c) => (tint = c ? css(themeFrom(c).accent, 0.22) : null))
    })
    .catch((e) => (error = errorText(e)))
  api
    .artistTracks(ref)
    .then((l) => (all = l))
    .catch(() => (allFailed = true))
  void library.load()
</script>

{#if error}
  <EmptyState icon="user" title={t('Не получилось открыть исполнителя')} text={error} />
{:else if !artist}
  <div class="loading"><div class="sk round"></div><div class="sk line"></div></div>
{:else}
  {@const a = artist}
  <div class="tint" class:on={!!tint} style:--artist-tint={tint ?? 'transparent'} aria-hidden="true"></div>
  <CollectionHeader
    title={a.name}
    image={a.avatar_url}
    icon="user"
    round
    meta={a.followers != null ? `${compact(a.followers)} ${tn(a.followers, ['подписчик', 'подписчика', 'подписчиков'])}` : undefined}
    disabled={!sorted.length}
    onplay={() => player.playList(sorted, 0, context, a.name)}
    onshuffle={() => player.playShuffled(sorted, context, a.name)}
    onqueue={() => player.addToQueue(sorted, false)}
  >
    {#snippet subtitle()}<span class="svc">{t(svc.name)}<SourceIcon service={svc.id} size={15} plain /></span>{/snippet}
    {#snippet actions()}
      <button class="tool" class:on={followed} onclick={() => library.toggleLike(a)}>
        <Icon name="heart" size={15} filled={followed} /> {followed ? t('Вы подписаны') : t('Подписаться')}
      </button>
    {/snippet}
  </CollectionHeader>

  <section>
    <div class="h">
      <h2>{t('Треки')}{#if all}<span class="count">{all.length}</span>{/if}</h2>
      {#if !all && !allFailed}<span class="wait">{t('загружаю все…')}</span>{/if}
    </div>
    {#if base.length > 1}
      <div class="sorts" use:indicator={{ key: `${sortId}${sorts.length}`, kind: 'pill' }}>
        {#each sorts as s (s.id)}
          <button
            class="sort"
            class:on={sortId === s.id}
            class:asc={sortId === s.id && asc}
            title={sortId === s.id ? t('Ещё раз — обратный порядок') : t('Сортировать: {what}', { what: t(s.label).toLowerCase() })}
            onclick={() => pickSort(s.id)}
          >
            {t(s.label)}
            {#if sortId === s.id}<span class="dir"><Icon name="chevronDown" size={13} /></span>{/if}
          </button>
        {/each}
      </div>
    {/if}
    {#key `${sortId}${asc}`}
      <div use:cascade>
        {#each shown as tr, i (tr.ref)}
          <TrackRow track={tr} index={i} variant="top" onplay={() => player.playList(sorted, i, context, a.name)} />
        {:else}
          <p class="none">{t('Треков нет.')}</p>
        {/each}
      </div>
    {/key}
    {#if expanded && limit < sorted.length}<div class="more" use:more></div>{/if}
    {#if sorted.length > FOLD}
      <button class="all" onclick={() => (limit = expanded ? FOLD : Math.min(100, sorted.length))}>
        {expanded ? t('список::Свернуть') : t('Показать все {n}', { n: sorted.length })}
      </button>
    {/if}
  </section>

  {#if albums.length}
    <section>
      <h2>{t('Альбомы')}</h2>
      <div class="grid" use:cascade>
        {#each albums as al (al.ref)}
          <Tile title={al.title} subtitle={al.year ? String(al.year) : al.artist} image={al.cover_url} icon="disc" onclick={() => openRef(al.ref)} />
        {/each}
      </div>
    </section>
  {/if}
{/if}

<style>
  section {
    margin-top: 22px;
  }
  .h {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
  }
  h2 {
    margin-bottom: 10px;
    font-size: calc(24px * var(--fs, 1));
    font-weight: 800;
  }
  .count {
    margin-left: 10px;
    font-size: calc(15px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .wait {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    animation: wait-pulse 1.4s var(--ease) infinite alternate;
  }
  @keyframes wait-pulse {
    from {
      opacity: 0.45;
    }
  }
  /* сортировка: капсула переезжает к выбранной, стрелка поворачивается при смене направления */
  .sorts {
    position: relative;
    display: inline-flex;
    flex-wrap: wrap;
    gap: 2px;
    margin-bottom: 12px;
    padding: 3px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .sort {
    position: relative;
    z-index: 1;
    display: inline-flex;
    align-items: center;
    gap: 4px;
    height: 28px;
    padding: 0 13px;
    border-radius: 999px;
    color: var(--text-2);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition:
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .sort:hover,
  .sort.on {
    color: var(--text);
  }
  .sort:active {
    transform: scale(0.96);
  }
  .sorts :global(.tab-ind.pill) {
    background: var(--hover);
  }
  .dir {
    display: inline-flex;
    margin-right: -4px;
    color: var(--accent);
    transition: transform 0.35s cubic-bezier(0.32, 0.72, 0, 1);
    animation: dir-in 0.3s var(--ease);
  }
  .asc .dir {
    transform: rotate(180deg);
  }
  @keyframes dir-in {
    from {
      opacity: 0;
      scale: 0.6;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .dir,
    .wait {
      animation: none;
      transition: none;
    }
  }
  .more {
    height: 1px;
  }
  .all {
    display: block;
    margin: 8px auto 0;
    padding: 6px 14px;
    border-radius: 999px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .all:hover {
    color: var(--text);
    background: var(--hover);
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
    gap: 18px;
  }
  .grid :global(.tile) {
    width: auto;
  }
  .none {
    color: var(--text-3);
  }
  .loading {
    display: flex;
    align-items: center;
    gap: 26px;
    padding: 8px 0;
  }
  .sk {
    background: linear-gradient(90deg, var(--plate), var(--hover), var(--plate));
    background-size: 200% 100%;
    animation: shimmer 1.2s linear infinite;
  }
  .sk.round {
    width: 168px;
    height: 168px;
    border-radius: 50%;
  }
  .sk.line {
    width: 260px;
    height: 44px;
    border-radius: var(--radius-m);
  }
  @keyframes shimmer {
    to {
      background-position: -200% 0;
    }
  }
  .tint {
    position: absolute;
    inset: 0 0 auto;
    z-index: -1;
    height: 420px;
    background: linear-gradient(180deg, var(--artist-tint), transparent);
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.8s var(--ease);
  }
  .tint.on {
    opacity: 1;
  }
  .svc {
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }
</style>
