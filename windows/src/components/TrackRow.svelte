<script lang="ts">
  // Строка трека (pc/Screenshot_28): обложка со значком источника, название, исполнители
  // (ссылки на их страницы), прослушивания, ❤, длительность, ⋮. Правый клик — то же меню трека.
  import Cover from './Cover.svelte'
  import Icon from './Icon.svelte'
  import { pulse } from '../lib/pulse'
  import type { Track } from '../lib/api'
  import { library } from '../lib/library.svelte'
  import { trackMenu } from '../lib/menu.svelte'
  import { hasSelection } from '../lib/selection'
  import { openRef } from '../app/router.svelte'
  import { formatTime, player } from '../player/player.svelte'
  import { settings } from '../lib/settings.svelte'
  import { compact } from '../lib/format'

  interface Props {
    track: Track
    index?: number
    /** list — поиск и списки (колонка альбома); queue — очередь плеера (компактно); top — популярное артиста;
     *  album — внутри альбома (pc/album.png): номер, без обложки и ❤, длительность в капсуле. */
    variant?: 'list' | 'queue' | 'top' | 'album'
    /** Когда добавлен (Любимые, плейлист) — для шапки меню. */
    addedAt?: number
    /** Строка своего плейлиста — в меню появится «Убрать из плейлиста». */
    playlistId?: string
    itemId?: string
    onplay: () => void
  }

  let { track, index, variant = 'list', addedAt, playlistId, itemId, onplay }: Props = $props()
  const isCurrent = $derived(player.current?.ref === track.ref)
  const liked = $derived(library.isLiked(track.ref))
  const target = $derived({ track, addedAt, playlistId, itemId })

  function activate() {
    if (hasSelection()) return
    if (isCurrent) player.toggle()
    // «Добавлять следующие» выключено — играет только нажатый трек, без хвоста списка
    else if (!settings.get('queue.add_following') && variant !== 'queue') void player.playList([track], 0, null)
    else onplay()
  }

  function onKey(e: KeyboardEvent) {
    if (e.target !== e.currentTarget) return
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault()
      activate()
    }
  }

  function openArtist(e: MouseEvent, ref: string) {
    e.stopPropagation()
    if (!hasSelection()) openRef(ref)
  }
</script>

<div
  class="row {variant}"
  class:current={isCurrent}
  class:off={!track.available}
  class:numbered={index !== undefined}
  role="button"
  tabindex="0"
  onclick={activate}
  onkeydown={onKey}
  oncontextmenu={(e) => {
    e.preventDefault()
    trackMenu.open(target, e.clientX, e.clientY)
  }}
>
  {#if index !== undefined}
    <span class="num">
      {#if isCurrent && player.playing}
        <span class="eq idle-pause" aria-label="Играет"><i></i><i></i><i></i></span>
      {:else}
        {index + 1}
      {/if}
    </span>
  {/if}
  {#if variant !== 'album'}
    <span class="art">
      <Cover url={track.cover_url} size={variant === 'list' ? 44 : 42} source={track.ref} />
      <span class="hover-play"><Icon name={isCurrent && player.playing ? 'pause' : 'play'} size={16} filled /></span>
    </span>
  {/if}
  <span class="meta">
    <span class="title">{track.title}{#if track.explicit}<span class="e" title="Нецензурная лексика">E</span>{/if}</span>
    <span class="artist">
      {#each track.artists as a, i (a.ref + i)}{#if i},&nbsp;{/if}<span
          class="link"
          role="link"
          tabindex="-1"
          onclick={(e) => openArtist(e, a.ref)}
          onkeydown={() => {}}>{a.name}</span
        >{:else}{track.artist}{/each}
    </span>
  </span>
  {#if variant === 'list'}
    <span class="album">{track.album?.title ?? ''}</span>
  {/if}
  <span class="end">
    {#if track.plays && variant !== 'queue'}
      <!-- число прослушиваний на сервисе (SoundCloud отдаёт, Яндекс — нет) -->
      <span class="plays" title="{track.plays.toLocaleString('ru-RU')} прослушиваний">
        <Icon name="play" size={11} filled stroke={0} />{compact(track.plays)}
      </span>
    {/if}
    {#if variant !== 'album'}
    <button
      class="like"
      class:on={liked}
      aria-label={liked ? 'Удалить из Любимых' : 'В Любимые'}
      title={liked ? 'Удалить из Любимых' : 'В Любимые'}
      onclick={(e) => (e.stopPropagation(), library.toggleLike(track))}
    >
      <span class="ic" use:pulse={liked}><Icon name="heart" size={15} filled={liked} /></span>
    </button>
    {/if}
    {#if variant === 'list'}
      <span class="dur">{formatTime(track.duration_ms)}</span>
    {:else}
      <span class="pill">
        {#if isCurrent && player.playing}
          <span class="eq small idle-pause"><i></i><i></i><i></i></span>
        {:else}
          {formatTime(track.duration_ms)}
        {/if}
      </span>
    {/if}
    <button
      class="dots"
      aria-label="Меню трека"
      title="Меню трека"
      onclick={(e) => (e.stopPropagation(), trackMenu.openAt(target, e.currentTarget))}
    >
      <Icon name="dots" size={16} />
    </button>
  </span>
</div>

<style>
  .row {
    display: grid;
    grid-template-columns: auto minmax(0, 2fr) minmax(0, 1fr) auto;
    align-items: center;
    gap: 14px;
    width: 100%;
    padding: 6px 8px 6px 8px;
    border-radius: var(--radius-m);
    text-align: left;
    cursor: pointer;
    outline-offset: -2px;
    transition: background var(--fast) var(--ease);
  }
  .row.numbered {
    grid-template-columns: auto auto minmax(0, 2fr) minmax(0, 1fr) auto;
  }
  .row.queue,
  .row.top {
    grid-template-columns: auto minmax(0, 1fr) auto;
    padding: 6px 6px 6px 6px;
  }
  .row.queue.numbered,
  .row.top.numbered {
    grid-template-columns: auto auto minmax(0, 1fr) auto;
  }
  .row.album {
    grid-template-columns: auto minmax(0, 1fr) auto;
    gap: 18px;
    padding: 9px 8px 9px 4px;
  }
  .row.album .title {
    font-weight: 500;
  }
  .row.album .dots {
    opacity: 1;
  }
  .row:hover {
    background: var(--hover);
  }
  .row.off {
    opacity: 0.45;
  }
  .end {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .like,
  .dots {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: var(--radius-s);
    color: var(--text-3);
    transition:
      color var(--fast) var(--ease),
      opacity var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .like:hover,
  .dots:hover {
    color: var(--text);
  }
  .dots:active {
    transform: scale(0.88);
  }
  .like.on {
    color: var(--text);
  }
  /* ❤ без лайка и ⋮ — только при наведении, чтобы список был спокойным (как в Dotify) */
  .like:not(.on),
  .dots {
    opacity: 0;
  }
  .row:hover .like,
  .row:hover .dots,
  .row:focus-within .like,
  .row:focus-within .dots {
    opacity: 1;
  }
  .pill {
    display: grid;
    place-items: center;
    min-width: 40px;
    height: 24px;
    padding: 0 8px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-2);
    font-variant-numeric: tabular-nums;
  }
  .eq.small {
    height: 9px;
  }
  .num {
    width: 26px;
    text-align: center;
    font-variant-numeric: tabular-nums;
    color: var(--text-3);
  }
  .art {
    position: relative;
    border-radius: var(--radius-s);
    overflow: hidden;
  }
  .hover-play {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    background: rgba(0, 0, 0, 0.5);
    color: #fff;
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .row:hover .hover-play {
    opacity: 1;
  }
  .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .title,
  .artist,
  .album {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .title {
    font-weight: 600;
  }
  .current .title {
    color: var(--accent);
  }
  .e {
    display: inline-block;
    margin-left: 6px;
    padding: 0 4px;
    border-radius: 3px;
    background: var(--surface-3);
    color: var(--text-2);
    font-size: calc(10px * var(--fs, 1));
    font-weight: 700;
    vertical-align: 2px;
  }
  .artist,
  .album {
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-3);
  }
  .link:hover {
    color: var(--text-2);
    text-decoration: underline;
    text-underline-offset: 2px;
  }
  .plays {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    min-width: 54px;
    justify-content: flex-end;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .dur {
    min-width: 36px;
    text-align: right;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .eq {
    display: inline-flex;
    align-items: flex-end;
    gap: 2px;
    height: 12px;
  }
  .eq i {
    width: 3px;
    background: var(--accent);
    border-radius: 1px;
    animation: eq 0.9s ease-in-out infinite;
  }
  .eq i:nth-child(2) {
    animation-delay: -0.3s;
  }
  .eq i:nth-child(3) {
    animation-delay: -0.6s;
  }
  @keyframes eq {
    0%,
    100% {
      height: 30%;
    }
    50% {
      height: 100%;
    }
  }
  .ic {
    display: grid;
    place-items: center;
  }
</style>
