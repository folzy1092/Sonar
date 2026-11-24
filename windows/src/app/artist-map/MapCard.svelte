<script lang="ts">
  // Карточка исполнителя на карте: слушать, открыть страницу, связи и «плейлист по кучке».
  // Открывается кликом по кругу, закрывается крестиком или кликом по пустому месту карты.
  import Icon from '../../components/Icon.svelte'
  import { t, tn } from '../../lib/i18n.svelte'
  import { pop } from '../../lib/motion'
  import { cascade } from '../../lib/cascade'
  import { tracksText } from '../../lib/format'
  import { errorText } from '../../lib/api'
  import { toast } from '../../lib/toast.svelte'
  import { library } from '../../lib/library.svelte'
  import { player } from '../../player/player.svelte'
  import { router, openRef } from '../router.svelte'
  import { mapApi, type MapGraph, type MapNode } from '../../lib/artist-map/api'
  import type { Layout } from '../../lib/artist-map/layout'
  import { artistRef, clusterMembers, connections } from '../../lib/artist-map/graph'
  import { artistsCount, clusterTitle, strengthLabel, whyText } from '../../lib/artist-map/why'
  import { offline } from '../../lib/offline.svelte'

  interface Props {
    node: MapNode
    graph: MapGraph
    layout: Layout
    nodes: ReadonlyMap<string, MapNode>
    onclose: () => void
    /** Перелететь к соседу и выбрать его. */
    onfly: (key: string) => void
  }

  let { node, graph, layout, nodes, onclose, onfly }: Props = $props()

  /** Сколько связей показываем в карточке. */
  const LINKS_SHOWN = 8
  /** Треков исполнителя в очередь по «Слушать». */
  const PLAY_LIMIT = 100
  /** Треков в плейлист по кучке (больше Rust и не отдаст). */
  const CLUSTER_LIMIT = 200

  let busy = $state<'play' | 'cluster' | null>(null)

  const links = $derived(connections(graph, node.key, LINKS_SHOWN))
  const ref = $derived(artistRef(node))
  // одиночки без связей лежат общей россыпью — это не кучка
  const members = $derived(links.length ? clusterMembers(layout, nodes, node.key) : [])

  const stats = $derived.by(() => {
    const parts = [tracksText(node.tracks)]
    if (node.plays > 0) parts.push(`${node.plays} ${tn(node.plays, ['прослушивание', 'прослушивания', 'прослушиваний'])}`)
    return parts.join(' · ')
  })

  async function play() {
    if (busy) return
    busy = 'play'
    try {
      const tracks = await mapApi.clusterTracks([node.name], PLAY_LIMIT)
      if (!tracks.length) toast.show(t('У этого исполнителя нет треков в медиатеке'))
      else await player.playList(tracks, 0, `artist-map:${node.key}`, node.name)
    } catch (e) {
      toast.show(errorText(e))
    } finally {
      busy = null
    }
  }

  async function makePlaylist() {
    if (busy || members.length < 2) return
    busy = 'cluster'
    try {
      const tracks = await mapApi.clusterTracks(members.map((m) => m.name), CLUSTER_LIMIT)
      if (!tracks.length) {
        toast.show(t('В этой кучке нет треков из медиатеки'))
        return
      }
      const created = await library.createPlaylist(clusterTitle(members[0].name), tracks)
      if (created) router.go('playlist', created.id)
    } catch (e) {
      toast.show(errorText(e))
    } finally {
      busy = null
    }
  }
</script>

<aside class="card" transition:pop={{ y: 8 }} aria-label={node.name}>
  <header>
    <div class="ava" class:out={!node.discovered}>
      {#if node.avatar_url}
        <img src={offline.src(node.avatar_url)} alt="" referrerpolicy="no-referrer" />
      {:else}
        <span>{(Array.from(node.name.trim())[0] ?? '?').toUpperCase()}</span>
      {/if}
    </div>
    <div class="head">
      <h3 title={node.name}>{node.name}</h3>
      <p>{node.discovered ? stats : t('не в медиатеке')}</p>
    </div>
    <button class="icon close" aria-label={t('Закрыть')} onclick={onclose}><Icon name="x" size={16} /></button>
  </header>

  <div class="actions">
    {#if node.discovered}
      <button class="primary" disabled={busy !== null} onclick={play}>
        <Icon name="play" size={15} />{t('Слушать')}
      </button>
    {/if}
    {#if ref}
      <button class="ghost" onclick={() => ref && openRef(ref)}>
        <Icon name="user" size={15} />{t('Открыть исполнителя')}
      </button>
    {/if}
  </div>

  <h4>{t('Связи')}</h4>
  {#if links.length}
    <ul use:cascade={node.key}>
      {#each links as link (link.node.key)}
        <li>
          <button class="link" class:out={!link.node.discovered} onclick={() => onfly(link.node.key)}>
            <span class="name">{link.node.name}</span>
            <span class="why">{strengthLabel(link.edge.weight)} · {whyText(link.edge.reasons, link.node.name)}</span>
          </button>
        </li>
      {/each}
    </ul>
  {:else}
    <p class="none">{t('Пока без связей')}</p>
  {/if}

  {#if members.length >= 2}
    <button class="cluster" disabled={busy !== null} onclick={makePlaylist}>
      <Icon name="playlistAdd" size={16} />
      <span>{t('Собрать плейлист по кучке')}</span>
      <small>{artistsCount(members.length)}</small>
    </button>
  {/if}
</aside>

<style>
  .card {
    position: absolute;
    top: 14px;
    right: 14px;
    width: min(320px, calc(100% - 28px));
    max-height: calc(100% - 28px);
    overflow: auto;
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding: 14px;
    border-radius: var(--radius-l);
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: 0 18px 40px rgb(0 0 0 / 0.28);
    backdrop-filter: blur(18px);
    z-index: 3;
  }
  header {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .ava {
    flex: none;
    width: 52px;
    height: 52px;
    border-radius: 50%;
    overflow: hidden;
    display: grid;
    place-items: center;
    background: var(--surface-3);
    color: var(--text-3);
    font: 700 20px var(--font-display);
  }
  .ava.out {
    opacity: 0.55;
    outline: 1px dashed var(--border-strong);
    outline-offset: 2px;
  }
  .ava img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .head {
    min-width: 0;
    flex: 1;
  }
  h3 {
    margin: 0;
    font: 700 16px var(--font-display);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    user-select: text;
  }
  .head p {
    margin: 2px 0 0;
    font-size: 12px;
    color: var(--text-3);
  }
  .icon {
    flex: none;
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: 50%;
    color: var(--text-3);
    transition: background var(--fast) var(--ease), color var(--fast) var(--ease);
  }
  .icon:hover {
    background: var(--hover);
    color: var(--text);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .actions button {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 32px;
    padding: 0 12px;
    border-radius: 999px;
    font-size: 13px;
    font-weight: 600;
    transition: transform var(--fast) var(--ease), background var(--fast) var(--ease), opacity var(--fast) var(--ease);
  }
  .actions button:active:not(:disabled) {
    transform: scale(0.96);
  }
  .actions button:disabled {
    opacity: 0.6;
  }
  .primary {
    background: var(--accent);
    color: var(--accent-ink);
  }
  .ghost {
    background: var(--surface-3);
    color: var(--text);
  }
  .ghost:hover {
    background: var(--hover);
  }
  h4 {
    margin: 2px 0 -4px;
    font-size: 12px;
    font-weight: 600;
    color: var(--text-3);
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .link {
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 1px;
    padding: 7px 8px;
    border-radius: var(--radius-s);
    text-align: left;
    transition: background var(--fast) var(--ease);
  }
  .link:hover {
    background: var(--hover);
  }
  .link.out .name {
    color: var(--text-2);
  }
  .name {
    font-size: 13px;
    font-weight: 600;
  }
  .why {
    font-size: 11.5px;
    color: var(--text-3);
    line-height: 1.35;
  }
  .none {
    margin: 0;
    font-size: 12.5px;
    color: var(--text-3);
  }
  .cluster {
    display: grid;
    grid-template-columns: auto 1fr;
    align-items: center;
    column-gap: 8px;
    padding: 10px 12px;
    border-radius: var(--radius-m);
    background: var(--surface-3);
    text-align: left;
    font-size: 13px;
    font-weight: 600;
    transition: background var(--fast) var(--ease), transform var(--fast) var(--ease);
  }
  .cluster:hover {
    background: var(--hover);
  }
  .cluster:active:not(:disabled) {
    transform: scale(0.98);
  }
  .cluster:disabled {
    opacity: 0.6;
  }
  .cluster small {
    grid-column: 2;
    font-size: 11.5px;
    font-weight: 500;
    color: var(--text-3);
  }
</style>
