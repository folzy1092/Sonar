<script lang="ts">
  import { cascade } from '../lib/cascade'
  // Исполнитель (pc/Screenshot_19): круглый аватар, имя, подписчики; Слушать · Подписаться ·
  // перемешать · в очередь; «Популярные» и «Альбомы». «Подписаться» = лайк исполнителя (вкладка
  // «Исполнители» в медиатеке). Окраска шапки под аватар — вместе с темой под обложку (W5).
  import CollectionHeader from '../components/CollectionHeader.svelte'
  import EmptyState from '../components/EmptyState.svelte'
  import Icon from '../components/Icon.svelte'
  import Tile from '../components/Tile.svelte'
  import TrackRow from '../components/TrackRow.svelte'
  import { api, errorText, type Album, type Artist, type Track } from '../lib/api'
  import { compact, plural } from '../lib/format'
  import { library } from '../lib/library.svelte'
  import { openRef, router } from '../app/router.svelte'
  import { player } from '../player/player.svelte'

  const ref = router.param ?? ''
  let artist = $state<Artist | null>(null)
  let top = $state<Track[]>([])
  let albums = $state<Album[]>([])
  let error = $state<string | null>(null)
  let showAll = $state(false)

  const followed = $derived(library.isLiked(ref))
  const shown = $derived(showAll ? top : top.slice(0, 5))
  const context = `artist:${ref}`

  api
    .artistPage(ref)
    .then((p) => {
      artist = p.artist
      top = p.top
      albums = p.albums
    })
    .catch((e) => (error = errorText(e)))
  void library.load()
</script>

{#if error}
  <EmptyState icon="user" title="Не получилось открыть исполнителя" text={error} />
{:else if !artist}
  <div class="loading"><div class="sk round"></div><div class="sk line"></div></div>
{:else}
  {@const a = artist}
  <CollectionHeader
    title={a.name}
    image={a.avatar_url}
    icon="user"
    round
    meta={a.followers != null ? `${compact(a.followers)} ${plural(a.followers, ['подписчик', 'подписчика', 'подписчиков'])}` : undefined}
    disabled={!top.length}
    onplay={() => player.playList(top, 0, context, a.name)}
    onshuffle={() => player.playShuffled(top, context, a.name)}
    onqueue={() => player.addToQueue(top, false)}
  >
    {#snippet subtitle()}{ref.startsWith('sca') ? 'SoundCloud' : 'Яндекс Музыка'}{/snippet}
    {#snippet actions()}
      <button class="tool" class:on={followed} onclick={() => library.toggleLike(a)}>
        <Icon name="heart" size={15} filled={followed} /> {followed ? 'Вы подписаны' : 'Подписаться'}
      </button>
    {/snippet}
  </CollectionHeader>

  <section>
    <div class="h">
      <h2>Популярные</h2>
      {#if top.length > 5}
        <button class="all" onclick={() => (showAll = !showAll)}>{showAll ? 'Свернуть' : 'Показать все'}</button>
      {/if}
    </div>
    <div use:cascade>
    {#each shown as t, i (t.ref)}
      <TrackRow track={t} index={i} variant="top" onplay={() => player.playList(top, i, context, a.name)} />
    {:else}
      <p class="none">Треков нет.</p>
    {/each}
    </div>
  </section>

  {#if albums.length}
    <section>
      <h2>Альбомы</h2>
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
    font-size: 24px;
    font-weight: 800;
  }
  .all {
    font-size: 12px;
    color: var(--text-2);
  }
  .all:hover {
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
</style>
