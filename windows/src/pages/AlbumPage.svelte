<script lang="ts">
  // Альбом по reference/pc/album.png: сверху свечение цвета обложки, обложка слева, справа дата выхода,
  // крупное название, исполнитель с аватаром, «11 треков, 20 мин 44 сек»; кнопки Слушать/Пауза ·
  // В очередь · [перемешать | в медиатеку] · поделиться; список — номер, название, исполнители,
  // длительность в капсуле (у играющего — эквалайзер), ⋮.
  import { cascade } from '../lib/cascade'
  import EmptyState from '../components/EmptyState.svelte'
  import Icon from '../components/Icon.svelte'
  import PlayPause from '../components/PlayPause.svelte'
  import TrackRow from '../components/TrackRow.svelte'
  import { pulse } from '../lib/pulse'
  import { replay } from '../lib/replay'
  import { api, errorText, type Album, type Track } from '../lib/api'
  import { dateLong, durationLong, tracksText } from '../lib/format'
  import { library } from '../lib/library.svelte'
  import { hasSelection } from '../lib/selection'
  import { toast } from '../lib/toast.svelte'
  import { openRef, router } from '../app/router.svelte'
  import { player } from '../player/player.svelte'
  import { colorOf } from '../theme/theme.svelte'
  import { css } from '../theme/palette'

  const ref = router.param ?? ''
  let album = $state<Album | null>(null)
  let tracks = $state<Track[]>([])
  let error = $state<string | null>(null)
  let glow = $state<string | null>(null)
  let failed = $state(false)

  const liked = $derived(library.isLiked(ref))
  const total = $derived(tracks.reduce((s, t) => s + t.duration_ms, 0))
  const context = `album:${ref}`
  const ours = $derived(player.context === context)
  const playing = $derived(ours && player.playing)
  const avatar = $derived(album?.artists[0]?.avatar_url ?? null)
  const date = $derived(album?.released ? dateLong(album.released) : album?.year ? String(album.year) : null)

  api
    .albumPage(ref)
    .then((p) => {
      album = p.album
      tracks = p.tracks
      if (p.album.cover_url) void colorOf(p.album.cover_url).then((c) => (glow = c ? css(c, 0.42) : 'rgba(255,255,255,0.16)'))
      else glow = 'rgba(255,255,255,0.12)'
    })
    .catch((e) => (error = errorText(e)))
  void library.load()

  function listen() {
    if (ours && player.current) player.toggle()
    else void player.playList(tracks, 0, context, album?.title ?? null)
  }

  async function share() {
    if (!album?.url) return
    try {
      await navigator.clipboard.writeText(album.url)
      toast.show('Ссылка скопирована')
    } catch {
      toast.show('Не получилось скопировать')
    }
  }
</script>

{#if error}
  <EmptyState icon="disc" title="Не получилось открыть альбом" text={error} />
{:else if !album}
  <div class="head">
    <div class="cover skel"></div>
    <div class="text"><div class="line skel w1"></div><div class="line skel w2"></div><div class="line skel w3"></div></div>
  </div>
{:else}
  {@const al = album}
  <div class="glow" class:on={!!glow} style:--glow={glow ?? 'transparent'} aria-hidden="true"></div>

  <header class="head">
    <div class="cover">
      {#if al.cover_url && !failed}
        <img class="fade-img" src={al.cover_url} alt="" draggable="false" onload={(e) => e.currentTarget.classList.add('loaded')} onerror={() => (failed = true)} />
      {:else}
        <Icon name="disc" size={56} stroke={1.5} />
      {/if}
    </div>
    <div class="text" use:replay={ref}>
      {#if date}<p class="date">{date}</p>{/if}
      <h1 class="selectable" title={al.title}>{al.title}</h1>
      <p class="artists">
        {#if avatar}<img class="av fade-img" src={avatar} alt="" onload={(e) => e.currentTarget.classList.add('loaded')} />{:else}<span class="av ph"><Icon name="user" size={13} /></span>{/if}
        {#each al.artists as a, i (a.ref)}{#if i},&nbsp;{/if}<button class="artist" onclick={() => !hasSelection() && openRef(a.ref)}>{a.name}</button>{:else}<span class="artist">{al.artist}</span>{/each}
      </p>
      <p class="meta">{tracksText(tracks.length)}{#if tracks.length}, {durationLong(total)}{/if}</p>
    </div>
  </header>

  <div class="bar">
    <button class="listen" disabled={!tracks.length} onclick={listen}>
      <PlayPause {playing} size={16} />
      {playing ? 'Пауза' : 'Слушать'}
    </button>
    <button class="pill" disabled={!tracks.length} onclick={() => player.addToQueue(tracks, false)}><Icon name="queue" size={16} /> В очередь</button>
    <span class="group">
      <button aria-label="Перемешать" title="Перемешать" disabled={!tracks.length} onclick={() => player.playShuffled(tracks, context, al.title)}><Icon name="shuffle" size={16} /></button>
      <button
        class:on={liked}
        aria-label={liked ? 'Убрать из медиатеки' : 'Сохранить в медиатеку'}
        title={liked ? 'Убрать из медиатеки' : 'Сохранить в медиатеку'}
        onclick={() => library.toggleLike(al)}
      >
        <span class="ic" use:pulse={liked}><Icon name="bookmark" size={16} filled={liked} /></span>
      </button>
    </span>
    {#if al.url}
      <button class="round" aria-label="Поделиться" title="Скопировать ссылку" onclick={share}><Icon name="share" size={16} /></button>
    {/if}
  </div>

  <div class="list" use:cascade>
    {#each tracks as t, i (t.ref + i)}
      <TrackRow track={t} index={i} variant="album" onplay={() => player.playList(tracks, i, context, al.title)} />
    {:else}
      <p class="none">В альбоме нет доступных треков.</p>
    {/each}
  </div>
{/if}

<style>
  /* свечение цвета обложки сверху, на всю ширину карточки (как в Dotify) */
  .glow {
    position: absolute;
    inset: -12px -28px auto;
    z-index: -1;
    height: 340px;
    background:
      radial-gradient(70% 120% at 85% 0%, var(--glow), transparent 70%),
      linear-gradient(180deg, color-mix(in srgb, var(--glow) 55%, transparent), transparent);
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.8s var(--ease);
  }
  .glow.on {
    opacity: 1;
  }
  .head {
    display: flex;
    align-items: center;
    gap: 30px;
    padding: 8px 0 24px;
  }
  .cover {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: 172px;
    height: 172px;
    overflow: hidden;
    border-radius: 18px;
    background: var(--plate);
    color: var(--text-2);
    box-shadow: 0 18px 40px rgba(0, 0, 0, 0.35);
  }
  .cover img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .text {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .date {
    margin: 0 0 6px;
    font-size: 12px;
    font-weight: 600;
    color: var(--text-3);
  }
  h1 {
    font-size: 46px;
    font-weight: 800;
    line-height: 1.08;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .artists {
    display: flex;
    align-items: center;
    margin: 10px 0 0;
    font-size: 15px;
  }
  .av {
    display: grid;
    place-items: center;
    width: 22px;
    height: 22px;
    margin-right: 8px;
    border-radius: 50%;
    object-fit: cover;
    background: var(--surface-3);
    color: var(--text-2);
  }
  .artist {
    color: var(--text);
    font-weight: 500;
  }
  button.artist:hover {
    text-decoration: underline;
    text-underline-offset: 2px;
  }
  .meta {
    margin: 6px 0 0;
    font-size: 12px;
    font-weight: 600;
    color: var(--text-3);
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 16px;
  }
  .listen,
  .pill,
  .round,
  .group {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 9px;
    height: 34px;
    border-radius: 999px;
    font-weight: 600;
  }
  .listen {
    min-width: 108px;
    padding: 0 18px;
    border-radius: 10px;
    background: var(--text);
    color: var(--on-text);
  }
  .pill {
    padding: 0 18px;
    border: 1px solid var(--border-strong);
    color: var(--text);
  }
  .group {
    gap: 0;
    padding: 0 4px;
    border: 1px solid var(--border-strong);
  }
  .group button {
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    border-radius: 999px;
    color: var(--text-2);
    transition:
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .group button:hover,
  .group button.on {
    color: var(--text);
  }
  .round {
    width: 34px;
    border: 1px solid var(--border-strong);
    color: var(--text-2);
  }
  .listen,
  .pill,
  .round {
    transition:
      transform var(--fast) var(--ease),
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .pill:hover:not(:disabled),
  .round:hover {
    background: var(--hover);
    color: var(--text);
  }
  button:active:not(:disabled) {
    transform: scale(0.95);
  }
  button:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .list {
    display: flex;
    flex-direction: column;
  }
  .none {
    color: var(--text-3);
  }
  .skel.cover {
    box-shadow: none;
  }
  .line {
    height: 14px;
    margin: 6px 0;
    border-radius: 7px;
  }
  .w1 {
    width: 90px;
  }
  .w2 {
    width: 260px;
    height: 40px;
  }
  .w3 {
    width: 160px;
  }
  .ic {
    display: grid;
    place-items: center;
  }
</style>
