<script lang="ts">
  import { cascade } from '../lib/cascade'
  // Альбом: обложка, название, исполнители (ссылки), год · треков · длительность; ❤ альбома
  // (вкладка «Альбомы» в медиатеке) и нумерованный список треков.
  import CollectionHeader from '../components/CollectionHeader.svelte'
  import EmptyState from '../components/EmptyState.svelte'
  import Icon from '../components/Icon.svelte'
  import { pulse } from '../lib/pulse'
  import TrackRow from '../components/TrackRow.svelte'
  import { api, errorText, type Album, type Track } from '../lib/api'
  import { durationText, tracksText } from '../lib/format'
  import { library } from '../lib/library.svelte'
  import { hasSelection } from '../lib/selection'
  import { openRef, router } from '../app/router.svelte'
  import { player } from '../player/player.svelte'

  const ref = router.param ?? ''
  let album = $state<Album | null>(null)
  let tracks = $state<Track[]>([])
  let error = $state<string | null>(null)

  const liked = $derived(library.isLiked(ref))
  const total = $derived(tracks.reduce((s, t) => s + t.duration_ms, 0))
  const context = `album:${ref}`

  api
    .albumPage(ref)
    .then((p) => {
      album = p.album
      tracks = p.tracks
    })
    .catch((e) => (error = errorText(e)))
  void library.load()
</script>

{#if error}
  <EmptyState icon="disc" title="Не получилось открыть альбом" text={error} />
{:else if !album}
  <div class="sk skel"></div>
{:else}
  {@const al = album}
  <CollectionHeader
    title={al.title}
    image={al.cover_url}
    icon="disc"
    meta={[al.year, tracksText(tracks.length), tracks.length ? durationText(total) : null].filter(Boolean).join(' · ')}
    disabled={!tracks.length}
    onplay={() => player.playList(tracks, 0, context, al.title)}
    onshuffle={() => player.playShuffled(tracks, context, al.title)}
    onqueue={() => player.addToQueue(tracks, false)}
  >
    {#snippet subtitle()}
      {#each al.artists as a, i (a.ref)}{#if i},&nbsp;{/if}<button class="artist" onclick={() => !hasSelection() && openRef(a.ref)}>{a.name}</button>{:else}{al.artist}{/each}
    {/snippet}
    {#snippet actions()}
      <button class="tool" class:on={liked} aria-label={liked ? 'Убрать из медиатеки' : 'В медиатеку'} title={liked ? 'Убрать из медиатеки' : 'В медиатеку'} onclick={() => library.toggleLike(al)}>
        <span class="ic" use:pulse={liked}><Icon name="heart" size={15} filled={liked} /></span>
      </button>
    {/snippet}
  </CollectionHeader>

  <div use:cascade>
  {#each tracks as t, i (t.ref + i)}
    <TrackRow track={t} index={i} onplay={() => player.playList(tracks, i, context, al.title)} />
  {:else}
    <p class="none">В альбоме нет доступных треков.</p>
  {/each}
  </div>
{/if}

<style>
  .artist {
    color: var(--text);
    font-weight: 600;
  }
  .artist:hover {
    text-decoration: underline;
    text-underline-offset: 2px;
  }
  .none {
    color: var(--text-3);
  }
  .sk {
    width: 168px;
    height: 168px;
    margin-top: 8px;
    border-radius: var(--radius-l);
    background: var(--plate);
  }
  .ic {
    display: grid;
    place-items: center;
  }
</style>
