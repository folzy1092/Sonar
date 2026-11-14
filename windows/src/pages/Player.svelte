<script lang="ts">
  // Страница «Сейчас играет» по Dotify (reference/pc/Screenshot_22): обложка слева, справа название
  // по центру, ползунок на всю ширину, волна по звуку, блок кнопок, строка громкости; ниже — очередь.
  import Icon from '../components/Icon.svelte'
  import IconButton from '../components/IconButton.svelte'
  import Cover from '../components/Cover.svelte'
  import TrackRow from '../components/TrackRow.svelte'
  import SeekBar from '../player/SeekBar.svelte'
  import SpeedButton from '../player/SpeedButton.svelte'
  import EqButton from '../player/EqButton.svelte'
  import Wave from '../player/Wave.svelte'
  import { formatTime, player } from '../player/player.svelte'
  import { library } from '../lib/library.svelte'
  import { trackMenu } from '../lib/menu.svelte'
  import { hasSelection } from '../lib/selection'
  import { openRef } from '../app/router.svelte'
  import { lyrics } from '../lyrics/lyrics.svelte'

  const track = $derived(player.current)
  const duration = $derived(player.durationMs || track?.duration_ms || 0)
  const avatar = $derived(track?.artists[0]?.avatar_url ?? null)
  const liked = $derived(library.isLiked(track?.ref))
  const contextTitle = $derived(
    player.contextTitle ??
      (player.context === 'search' ? 'Из поиска' : player.context === 'favorites' ? 'Любимые' : 'Очередь'),
  )
  const contextIcon = $derived<'search' | 'heart' | 'queue'>(
    player.context === 'search' ? 'search' : player.context === 'favorites' ? 'heart' : 'queue',
  )

  function openContext() {
    const c = player.context
    if (!c) return
    if (c === 'favorites') openRef('favorites')
    else if (c.startsWith('playlist:')) openRef(c.slice(9))
    else if (c.startsWith('album:')) openRef(c.slice(6))
    else if (c.startsWith('artist:')) openRef(c.slice(7))
  }
</script>

<div class="top">
  <div class="art">
    <button class="open-full" aria-label="Полноэкранный плеер" title="Полноэкранный плеер" disabled={!track} onclick={() => lyrics.open()}>
      <Cover url={track?.cover_url} size={320} radius="18px" />
    </button>
    {#if track}
      <button
        class="on-cover left"
        class:on={liked}
        aria-label={liked ? 'Удалить из Любимых' : 'В Любимые'}
        title={liked ? 'Удалить из Любимых' : 'В Любимые'}
        onclick={() => track && library.toggleLike(track)}
      >
        <Icon name="heart" size={18} filled={liked} />
      </button>
    {/if}
  </div>

  <div class="side">
    <div class="head">
      <h1 class="selectable" title={track?.title}>{track?.title ?? 'Ничего не играет'}</h1>
      <p class="artist selectable">
        {#if avatar}<img src={avatar} alt="" />{/if}
        {#if track}
          {#each track.artists as a, i (a.ref + i)}{#if i},&nbsp;{/if}<span
              class="link"
              role="link"
              tabindex="0"
              onclick={() => !hasSelection() && openRef(a.ref)}
              onkeydown={(e) => e.key === 'Enter' && openRef(a.ref)}>{a.name}</span
            >{:else}{track.artist}{/each}
        {:else}
          Найди трек в поиске
        {/if}
      </p>
    </div>

    <div class="seek">
      <SeekBar times={false} />
      <div class="times">
        <span>{formatTime(player.positionMs)}</span>
        {#if player.quality}<span class="quality" title="Что реально играет">{player.quality}</span>{/if}
        <span>{formatTime(duration)}</span>
      </div>
    </div>

    <Wave height={52} />

    <div class="panel controls">
      <button class="menu-btn" aria-label="Меню трека" title="Меню трека" disabled={!track} onclick={(e) => track && trackMenu.openAt({ track }, e.currentTarget)}>
        <Icon name="dots" size={18} />
      </button>
      <div class="main">
        <IconButton
          icon={player.repeat === 'one' ? 'repeatOnce' : 'repeat'}
          label={player.repeat === 'off' ? 'Повтор: выкл' : player.repeat === 'all' ? 'Повтор: всё' : 'Повтор: трек'}
          active={player.repeat !== 'off'}
          disabled={!track}
          onclick={() => player.cycleRepeat()}
        />
        <IconButton icon="prev" label="Назад" filled disabled={!track} onclick={() => player.prev()} />
        <button class="play" class:loading={player.loading} aria-label={player.playing ? 'Пауза' : 'Играть'} disabled={!track} onclick={() => player.toggle()}>
          <Icon name={player.playing ? 'pause' : 'play'} size={26} filled />
        </button>
        <IconButton icon="next" label="Вперёд" filled disabled={!track} onclick={() => player.next()} />
        <IconButton icon="shuffle" label="Перемешать" active={player.shuffle} disabled={!track} onclick={() => player.toggleShuffle()} />
      </div>
      <IconButton icon="dislike" label="Не нравится — W5" size={18} disabled />
    </div>

    <div class="row">
      <div class="panel volume" onwheel={(e) => player.setVolume(player.volume + (e.deltaY < 0 ? 0.05 : -0.05))}>
        <Icon name={player.volume === 0 ? 'volumeOff' : 'volume'} size={17} />
        <input
          type="range"
          min="0"
          max="1"
          step="0.01"
          value={player.volume}
          aria-label="Громкость"
          style:--fill="{player.volume * 100}%"
          oninput={(e) => player.setVolume(Number(e.currentTarget.value))}
        />
      </div>
      <div class="panel extra">
        <SpeedButton />
        <EqButton />
      </div>
    </div>

    {#if player.error}<p class="err">{player.error}</p>{/if}
  </div>
</div>

<section class="panel queue">
  <button class="chip" onclick={openContext} title="Открыть источник очереди"><Icon name={contextIcon} size={14} filled={contextIcon === 'heart'} /> {contextTitle}{#if player.shuffle}<Icon name="shuffle" size={14} />{/if}</button>

  {#if track}
    <h3>Сейчас играет</h3>
    <TrackRow {track} variant="queue" onplay={() => player.toggle()} />
  {/if}

  <h3>Далее</h3>
  {#if player.upNext.length}
    {#each player.upNext as t, i (t.ref + i)}
      <TrackRow track={t} variant="queue" onplay={() => player.jumpTo(i)} />
    {/each}
  {:else}
    <p class="empty">Очередь пуста — включи трек из поиска.</p>
  {/if}
</section>

<style>
  .top {
    display: grid;
    grid-template-columns: 320px minmax(0, 1fr);
    gap: 18px;
    align-items: start;
  }
  .art {
    position: relative;
    border-radius: 18px;
    overflow: hidden;
  }
  .open-full {
    display: block;
    cursor: zoom-in;
  }
  .open-full:disabled {
    cursor: default;
  }
  .on-cover {
    position: absolute;
    bottom: 12px;
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: 12px;
    background: rgba(20, 20, 22, 0.55);
    backdrop-filter: blur(10px);
    color: #fff;
  }
  .on-cover.left {
    left: 12px;
  }
  button.on-cover {
    color: rgba(255, 255, 255, 0.75);
    transition:
      transform var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  button.on-cover:hover,
  button.on-cover.on {
    color: #fff;
  }
  button.on-cover:active {
    transform: scale(0.9);
  }
  .menu-btn {
    display: grid;
    place-items: center;
    width: 34px;
    height: 34px;
    border-radius: var(--radius-s);
    color: var(--text-2);
  }
  .menu-btn:hover:not(:disabled) {
    background: var(--hover);
    color: var(--text);
  }
  .menu-btn:disabled {
    opacity: 0.35;
  }
  .link {
    cursor: pointer;
  }
  .link:hover {
    color: var(--text);
    text-decoration: underline;
    text-underline-offset: 2px;
  }
  .side {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-width: 0;
    padding-top: 14px;
  }
  .head {
    text-align: center;
  }
  h1 {
    font-size: 28px;
    font-weight: 800;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .artist {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    margin: 4px 0 0;
    color: var(--text-2);
    font-size: 14px;
  }
  .artist img {
    width: 18px;
    height: 18px;
    border-radius: 50%;
    object-fit: cover;
  }
  .seek {
    margin-top: 8px;
  }
  .times {
    display: flex;
    justify-content: space-between;
    margin-top: 6px;
    font-size: 11px;
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .quality {
    padding: 1px 7px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.02em;
    color: var(--text-2);
  }
  .panel {
    border: 1px solid var(--border);
    border-radius: 16px;
    background: var(--plate);
  }
  .controls {
    display: grid;
    grid-template-columns: auto 1fr auto;
    align-items: center;
    height: 64px;
    padding: 0 12px;
  }
  .main {
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 10px;
  }
  .play {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    color: var(--text);
    transition: transform var(--fast) var(--ease);
  }
  .play:active:not(:disabled) {
    transform: scale(0.9);
  }
  .play:disabled {
    opacity: 0.35;
    cursor: default;
  }
  .play.loading {
    animation: pulse 1s ease-in-out infinite;
  }
  @keyframes pulse {
    50% {
      opacity: 0.5;
    }
  }
  .row {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 10px;
  }
  .volume {
    display: flex;
    align-items: center;
    gap: 14px;
    height: 40px;
    padding: 0 16px;
    color: var(--text-2);
  }
  .volume input {
    flex: 1;
    height: 3px;
    margin: 0;
    appearance: none;
    border-radius: 3px;
    background: linear-gradient(to right, var(--text) var(--fill), var(--surface-3) var(--fill));
    cursor: pointer;
  }
  .volume input::-webkit-slider-thumb {
    appearance: none;
    width: 3px;
    height: 3px;
  }
  .extra {
    display: flex;
    align-items: center;
    height: 40px;
    padding: 0 4px;
  }
  .err {
    margin: 0;
    color: var(--danger);
    font-size: 13px;
    text-align: center;
  }
  .queue {
    margin-top: 18px;
    padding: 14px 12px 10px;
    border-radius: 18px;
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 32px;
    padding: 0 14px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
    font-size: 12px;
    color: var(--text-2);
  }
  h3 {
    margin: 16px 6px 6px;
    font-size: 12px;
    font-weight: 600;
    color: var(--text-3);
  }
  .empty {
    margin: 4px 6px;
    color: var(--text-3);
  }
  @media (prefers-reduced-motion: reduce) {
    .play.loading {
      animation: none;
    }
  }
</style>
