<script lang="ts">
  // Полноэкранный плеер (reference/pc/fullscreen_player.webp, PLATFORMS.md): фон — размытая
  // затемнённая обложка; колонкой обложка (❤ и 👎 на ней), название, исполнитель с аватаром,
  // ползунок, кнопки; громкость — тонкая полоска внизу. Нашёлся текст — колонка уходит влево,
  // справа караоке. Правый клик в любом месте — меню (размер, вид, синхронизация, смещение).
  // Вид: обложка и текст / только обложка / только текст (тогда сверху плашка с треком).
  import { onMount } from 'svelte'
  import { cubicOut } from 'svelte/easing'
  import { fade } from 'svelte/transition'
  import Icon from '../components/Icon.svelte'
  import PlayPause from '../components/PlayPause.svelte'
  import { pulse } from '../lib/pulse'
  import { replay } from '../lib/replay'
  import IconButton from '../components/IconButton.svelte'
  import Cover from '../components/Cover.svelte'
  import WindowControls from '../app/WindowControls.svelte'
  import SeekBar from './SeekBar.svelte'
  import LyricsView from '../lyrics/LyricsView.svelte'
  import LyricsMenu from '../lyrics/LyricsMenu.svelte'
  import { lyrics } from '../lyrics/lyrics.svelte'
  import { player } from './player.svelte'
  import { library } from '../lib/library.svelte'
  import { hasSelection } from '../lib/selection'
  import { openRef } from '../app/router.svelte'

  const track = $derived(player.current)
  const liked = $derived(library.isLiked(track?.ref))
  const avatar = $derived(track?.artists[0]?.avatar_url ?? null)
  const withText = $derived(lyrics.shown)
  const withCover = $derived(lyrics.coverShown)

  let menuAt = $state<{ x: number; y: number } | null>(null)

  function openArtist(ref: string) {
    if (hasSelection()) return
    lyrics.close()
    openRef(ref)
  }

  /** Меню — только когда у трека есть текст (решение владельца 2026-11-15): без текста правый
   *  клик ничего не открывает. */
  const hasLyrics = $derived(lyrics.status === 'ready' && !!lyrics.data?.lines.length)

  function openMenu(e: MouseEvent) {
    e.preventDefault()
    if (!hasLyrics) return
    menuAt = { x: e.clientX, y: e.clientY }
  }

  // текст пропал (сменился трек без текста) — меню закрыть
  $effect(() => {
    if (!hasLyrics) menuAt = null
  })

  /** Появление: лёгкое приближение + проявление. */
  function zoom(_node: Element, { duration = 280 } = {}) {
    return {
      duration,
      easing: cubicOut,
      css: (t: number) => `opacity: ${t}; transform: scale(${1.03 - 0.03 * t})`,
    }
  }

  onMount(() => {
    const key = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !menuAt) lyrics.close()
    }
    window.addEventListener('keydown', key)
    return () => window.removeEventListener('keydown', key)
  })

  // трек кончился и очереди нет — закрыть нечего показывать
  $effect(() => {
    if (!track) lyrics.close()
  })
</script>

<div class="fs" transition:zoom role="dialog" aria-label="Полноэкранный плеер" tabindex="-1" oncontextmenu={openMenu}>
  <!-- фон как в Dotify: одна огромная, сильно размытая копия обложки медленно плывёт и
       поворачивается — тянется силуэт, саму картинку не разобрать; под ней — средний цвет обложки -->
  <div class="bg" aria-hidden="true">
    {#key track?.cover_url}
      {#if track?.cover_url}
        <div class="layer" transition:fade={{ duration: 700 }}>
          <img class="base" src={track.cover_url} alt="" />
          <img class="float" src={track.cover_url} alt="" />
        </div>
      {/if}
    {/key}
  </div>

  <header data-tauri-drag-region>
    <div></div>
    <div class="center">
      <button class="collapse" aria-label="Свернуть" title="Свернуть" onclick={() => lyrics.close()}>
        <Icon name="chevronDown" size={22} />
      </button>
      {#if !withCover && track}
        <!-- «только текст»: сверху плашка с обложкой, названием и исполнителем -->
        <div class="pill" transition:fade={{ duration: 200 }}>
          <Cover url={track.cover_url} size={30} radius="50%" />
          <span>
            <b class="selectable">{track.title}</b>
            <small class="selectable">{track.artist}</small>
          </span>
        </div>
      {/if}
    </div>
    <div class="win"><WindowControls back={false} /></div>
  </header>

  <div class="body" class:text={withText && withCover} class:only-text={!withCover}>
    {#if withCover}
    <section class="col" transition:fade={{ duration: 220 }}>
      <div class="art">
        <Cover url={track?.cover_url} size={420} radius="14px" />
        {#if track}
          <button
            class="on-cover left"
            class:on={liked}
            aria-label={liked ? 'Удалить из Любимых' : 'В Любимые'}
            title={liked ? 'Удалить из Любимых' : 'В Любимые'}
            onclick={() => track && library.toggleLike(track)}
          >
            <span class="ic" use:pulse={liked}><Icon name="heart" size={18} filled={liked} /></span>
          </button>
          <button class="on-cover right" aria-label="Не нравится" title="Не нравится — вместе со своей волной (W5)" disabled>
            <Icon name="dislike" size={18} />
          </button>
        {/if}
      </div>

      <h1 class="selectable" title={track?.title} use:replay={track?.ref}>{track?.title ?? ''}</h1>
      <p class="artist selectable" use:replay={track?.ref}>
        {#if avatar}<img src={avatar} alt="" />{/if}
        {#if track}
          {#each track.artists as a, i (a.ref + i)}{#if i},&nbsp;{/if}<span
              class="link"
              role="link"
              tabindex="0"
              onclick={() => openArtist(a.ref)}
              onkeydown={(e) => e.key === 'Enter' && openArtist(a.ref)}>{a.name}</span
            >{:else}{track.artist}{/each}
        {/if}
      </p>

      <div class="seek"><SeekBar /></div>

      <div class="controls">
        <IconButton
          icon={player.repeat === 'one' ? 'repeatOnce' : player.repeat === 'all' ? 'repeat' : 'repeatOff'}
          label={player.repeat === 'off' ? 'Повтор: выкл' : player.repeat === 'all' ? 'Повтор: всё' : 'Повтор: трек'}
          active={player.repeat !== 'off'}
          disabled={!track}
          onclick={() => player.cycleRepeat()}
        />
        <IconButton icon="prev" label="Назад" filled disabled={!track} onclick={() => player.prev()} />
        <button
          class="play"
          class:loading={player.loading}
          aria-label={player.playing ? 'Пауза' : 'Играть'}
          title={player.playing ? 'Пауза' : 'Играть'}
          disabled={!track}
          onclick={() => player.toggle()}
        >
          <PlayPause playing={player.playing} size={30} />
        </button>
        <IconButton icon="next" label="Вперёд" filled disabled={!track} onclick={() => player.next()} />
        <IconButton icon="shuffle" label="Перемешать" active={player.shuffle} disabled={!track} onclick={() => player.toggleShuffle()} />
      </div>
      {#if player.error}<p class="err">{player.error}</p>{/if}
    </section>
    {/if}

    {#if withText}
      <section class="lyrics-col">
        <LyricsView />
      </section>
    {/if}
  </div>

  <footer>
    <div></div>
    <div
      class="volume"
      title="Громкость {Math.round(player.volume * 100)}%"
      onwheel={(e) => player.setVolume(player.volume + (e.deltaY < 0 ? 0.05 : -0.05))}
    >
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
    <div></div>
  </footer>

  {#if menuAt}
    <LyricsMenu x={menuAt.x} y={menuAt.y} onclose={() => (menuAt = null)} />
  {/if}
</div>

<style>
  .fs {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: grid;
    grid-template-rows: auto minmax(0, 1fr) auto;
    background: #070708;
    overflow: hidden;
    color: #fff;
  }
  .bg {
    position: absolute;
    inset: 0;
    pointer-events: none;
  }
  .layer {
    position: absolute;
    inset: 0;
    overflow: hidden;
  }
  .base {
    position: absolute;
    inset: -20%;
    width: 140%;
    height: 140%;
    object-fit: cover;
    filter: blur(140px) saturate(110%) brightness(0.62);
  }
  .float {
    position: absolute;
    left: 50%;
    top: 50%;
    width: 130vmax;
    height: 130vmax;
    margin: -65vmax 0 0 -65vmax;
    object-fit: cover;
    filter: blur(70px) saturate(110%) brightness(0.68);
    will-change: transform;
    animation: drift 22s ease-in-out infinite alternate;
  }
  @keyframes drift {
    0% {
      transform: translate(18vw, -6vh) rotate(-8deg) scale(1);
    }
    33% {
      transform: translate(4vw, 12vh) rotate(14deg) scale(1.12);
    }
    66% {
      transform: translate(-14vw, -4vh) rotate(-20deg) scale(0.95);
    }
    100% {
      transform: translate(-4vw, 10vh) rotate(6deg) scale(1.08);
    }
  }
  .bg::after {
    content: '';
    position: absolute;
    inset: 0;
    background:
      radial-gradient(ellipse at 50% 45%, transparent 0%, rgba(0, 0, 0, 0.22) 90%),
      linear-gradient(to bottom, rgba(0, 0, 0, 0.05), rgba(0, 0, 0, 0.25));
  }
  @media (prefers-reduced-motion: reduce) {
    .float {
      animation: none;
    }
  }
  header,
  .body,
  footer {
    position: relative;
  }
  header {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: start;
    padding: 8px 10px 0;
    min-height: 52px;
  }
  .win {
    display: flex;
    justify-content: flex-end;
  }
  .win :global(.ctl) {
    color: rgba(255, 255, 255, 0.6);
  }
  .collapse {
    display: grid;
    place-items: center;
    width: 44px;
    height: 36px;
    margin-top: 10px;
    border-radius: 12px;
    color: rgba(255, 255, 255, 0.6);
    transition: color var(--fast) var(--ease);
  }
  .collapse:hover {
    color: #fff;
  }
  .center {
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .pill {
    display: flex;
    align-items: center;
    gap: 10px;
    max-width: 420px;
    margin-top: 2px;
    padding: 5px 16px 5px 5px;
    border-radius: 999px;
    background: rgba(0, 0, 0, 0.22);
    backdrop-filter: blur(16px);
  }
  .pill span {
    display: flex;
    flex-direction: column;
    min-width: 0;
    line-height: 1.2;
  }
  .pill b,
  .pill small {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .pill b {
    font-size: 14px;
  }
  .pill small {
    font-size: 12px;
    color: rgba(255, 255, 255, 0.65);
  }

  .body {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    justify-items: center;
    align-items: center;
    min-height: 0;
    padding: 0 48px;
    gap: 64px;
  }
  .body.text {
    grid-template-columns: minmax(0, 0.9fr) minmax(0, 1.1fr);
    justify-items: stretch;
  }
  /* только текст: широкая колонка по центру */
  .body.only-text {
    justify-items: center;
  }
  .body.only-text .lyrics-col {
    width: min(900px, 100%);
    max-width: none;
  }
  .col {
    --art: min(52vh, 520px, 70vw);
    display: flex;
    flex-direction: column;
    align-items: center;
    width: var(--art);
    min-width: 0;
    animation: col-in 0.45s var(--ease);
  }
  .body.text .col {
    --art: min(48vh, 440px, 34vw);
    justify-self: end;
  }
  @keyframes col-in {
    from {
      opacity: 0.4;
      transform: translateX(24px);
    }
  }
  .lyrics-col {
    height: 100%;
    min-height: 0;
    max-width: 720px;
    animation: text-in 0.5s var(--ease);
  }
  @keyframes text-in {
    from {
      opacity: 0;
      transform: translateX(-16px);
    }
  }
  .art {
    position: relative;
    width: var(--art);
    height: var(--art);
    border-radius: 14px;
    overflow: hidden;
    box-shadow: 0 24px 60px -20px rgba(0, 0, 0, 0.8);
  }
  .art :global(.cover),
  .art :global(img) {
    width: 100% !important;
    height: 100% !important;
  }
  .on-cover {
    position: absolute;
    bottom: 12px;
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: rgba(0, 0, 0, 0.45);
    backdrop-filter: blur(12px);
    border: 1px solid rgba(255, 255, 255, 0.12);
    color: rgba(255, 255, 255, 0.8);
    transition:
      transform var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .on-cover.left {
    left: 12px;
  }
  .on-cover.right {
    right: 12px;
  }
  .on-cover:hover:not(:disabled),
  .on-cover.on {
    color: #fff;
  }
  .on-cover:active:not(:disabled) {
    transform: scale(0.9);
  }
  .on-cover:disabled {
    opacity: 0.6;
    cursor: default;
  }
  h1 {
    max-width: 100%;
    margin: 22px 0 0;
    font-size: 22px;
    font-weight: 800;
    text-align: center;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .artist {
    display: flex;
    align-items: center;
    gap: 6px;
    max-width: 100%;
    margin: 6px 0 0;
    font-size: 14px;
    color: rgba(255, 255, 255, 0.6);
    white-space: nowrap;
    overflow: hidden;
  }
  .artist img {
    width: 16px;
    height: 16px;
    border-radius: 50%;
    object-fit: cover;
  }
  .link {
    cursor: pointer;
  }
  .link:hover {
    color: #fff;
    text-decoration: underline;
    text-underline-offset: 2px;
  }
  .seek {
    width: 100%;
    margin-top: 18px;
  }
  .seek :global(.t) {
    color: rgba(255, 255, 255, 0.7);
    font-size: 11px;
    min-width: 30px;
  }
  .seek :global(input) {
    background: linear-gradient(to right, #fff var(--fill), rgba(255, 255, 255, 0.22) var(--fill));
  }
  .controls {
    display: flex;
    align-items: center;
    gap: 22px;
    margin-top: 16px;
  }
  .controls :global(.icon-btn) {
    color: rgba(255, 255, 255, 0.85);
  }
  .play {
    display: grid;
    place-items: center;
    width: 48px;
    height: 48px;
    color: #fff;
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
  .err {
    margin: 10px 0 0;
    color: var(--danger);
    font-size: 13px;
  }

  footer {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    padding: 6px 16px 14px;
  }
  .volume {
    display: flex;
    align-items: center;
    width: 200px;
    height: 20px;
  }
  .volume input {
    flex: 1;
    height: 4px;
    margin: 0;
    appearance: none;
    border-radius: 4px;
    background: linear-gradient(to right, #fff var(--fill), rgba(255, 255, 255, 0.22) var(--fill));
    cursor: pointer;
  }
  .volume input::-webkit-slider-thumb {
    appearance: none;
    width: 4px;
    height: 4px;
  }
  @media (prefers-reduced-motion: reduce) {
    .col,
    .lyrics-col,
    .play.loading {
      animation: none;
    }
  }
  .ic {
    display: grid;
    place-items: center;
  }
</style>
