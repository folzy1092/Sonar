<script lang="ts">
  // Полноэкранный плеер (reference/pc/fullscreen_player.webp, PLATFORMS.md): фон — «текущая»
  // обложка в WebGL (ArtBackdrop, как у Dotify, движется только во время игры); колонкой обложка (❤ и 👎 на ней), название, исполнитель с аватаром,
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
  import { wave } from './my-wave.svelte'
  import { settings } from '../lib/settings.svelte'
  import IconButton from '../components/IconButton.svelte'
  import Cover from '../components/Cover.svelte'
  import WindowControls from '../app/WindowControls.svelte'
  import SeekBar from './SeekBar.svelte'
  import ArtBackdrop from './ArtBackdrop.svelte'
  import LyricsView from '../lyrics/LyricsView.svelte'
  import LyricsMenu from '../lyrics/LyricsMenu.svelte'
  import { lyrics } from '../lyrics/lyrics.svelte'
  import { player } from './player.svelte'
  import { library } from '../lib/library.svelte'
  import { hasSelection } from '../lib/selection'
  import { openRef } from '../app/router.svelte'

  const track = $derived(player.current)
  const liked = $derived(library.isLiked(track?.ref))
  const avatar = $derived(settings.get('player.artist_avatars') ? (track?.artists[0]?.avatar_url ?? null) : null)
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

  // Как в Dotify: курсор ушёл с окна — кнопки окна, ❤/👎 на обложке, управление и громкость плавно
  // прячутся, остаются обложка, название, таймлайн и текст; курсор вернулся — показываются.
  let away = $state(false)
</script>

<svelte:document onmouseleave={() => (away = true)} onmouseenter={() => (away = false)} />

<div class="fs" class:away onmousemove={() => (away = false)} transition:zoom role="dialog" aria-label="Полноэкранный плеер" tabindex="-1" oncontextmenu={openMenu}>
  <ArtBackdrop />

  <header data-tauri-drag-region>
    <!-- «чёлки» по углам, как у главного окна: слева — свернуть, справа — кнопки окна -->
    <div class="notch left">
      <button class="collapse" aria-label="Свернуть" title="Свернуть" onclick={() => lyrics.close()}>
        <Icon name="chevronDown" size={20} />
      </button>
    </div>
    <div class="center">
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
    <div class="win"><div class="notch right"><WindowControls history={false} /></div></div>
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
          <button
            class="on-cover right"
            class:on={wave.isDisliked(track.ref)}
            aria-label="Не нравится"
            title={wave.isDisliked(track.ref) ? 'Снова можно ставить в волну' : 'Не нравится — больше не ставить'}
            onclick={() => track && wave.dislike(track)}
          >
            <span class="ic" use:pulse={wave.isDisliked(track.ref)}><Icon name="dislike" size={18} filled={wave.isDisliked(track.ref)} /></span>
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
        <!-- на каждый текст — свежий экран: прокрутка, часы и текущая строка не тянутся с прошлого трека -->
        {#key lyrics.data}
          <div class="lyr-in"><LyricsView /></div>
        {/key}
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
  .lyr-in {
    height: 100%;
    min-height: 0;
    animation: lyr-in 0.45s var(--ease);
  }
  @keyframes lyr-in {
    from {
      opacity: 0;
    }
  }
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
  header,
  .body,
  footer {
    position: relative;
  }
  header {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: start;
    padding: 0;
    min-height: 52px;
  }
  /* чёлка: тёмная плашка в углу окна, нижний угол скруглён, а с соседними краями она сходится
     вогнутыми скруглениями (как вырез в главном окне, lib/notch) */
  .notch {
    --nb: rgba(6, 6, 8, 0.78);
    --r: 14px;
    position: relative;
    display: flex;
    align-items: center;
    padding: 4px 6px;
    background: var(--nb);
    backdrop-filter: blur(18px);
    -webkit-backdrop-filter: blur(18px);
  }
  .notch.left {
    justify-self: start;
    border-bottom-right-radius: var(--r);
  }
  .notch.right {
    border-bottom-left-radius: var(--r);
  }
  .notch::before,
  .notch::after {
    content: '';
    position: absolute;
    width: var(--r);
    height: var(--r);
    pointer-events: none;
  }
  .notch.left::before {
    top: 0;
    left: 100%;
    background: radial-gradient(circle at 100% 100%, transparent calc(var(--r) - 0.5px), var(--nb) var(--r));
  }
  .notch.left::after {
    top: 100%;
    left: 0;
    background: radial-gradient(circle at 100% 100%, transparent calc(var(--r) - 0.5px), var(--nb) var(--r));
  }
  .notch.right::before {
    top: 0;
    right: 100%;
    background: radial-gradient(circle at 0 100%, transparent calc(var(--r) - 0.5px), var(--nb) var(--r));
  }
  .notch.right::after {
    top: 100%;
    right: 0;
    background: radial-gradient(circle at 0 100%, transparent calc(var(--r) - 0.5px), var(--nb) var(--r));
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
    width: 34px;
    height: 28px;
    border-radius: 8px;
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
    font-size: calc(14px * var(--fs, 1));
  }
  .pill small {
    font-size: calc(12px * var(--fs, 1));
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
      color var(--fast) var(--ease),
      opacity 0.35s var(--ease);
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
    font-size: calc(22px * var(--fs, 1));
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
    font-size: calc(14px * var(--fs, 1));
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
    font-size: calc(11px * var(--fs, 1));
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
    font-size: calc(13px * var(--fs, 1));
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
  /* курсор вне окна — прячем управление (как в Dotify) */
  .win,
  .controls,
  .volume {
    transition:
      opacity 0.35s var(--ease),
      transform 0.35s var(--ease);
  }
  .away .win,
  .away .on-cover,
  .away .controls,
  .away .volume {
    opacity: 0;
    pointer-events: none;
  }
  .away .controls {
    transform: translateY(6px);
  }
</style>
