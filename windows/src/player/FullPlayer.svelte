<script lang="ts">
  // Полноэкранный плеер (reference/pc/fullscreen_player.webp, PLATFORMS.md): фон — размытая
  // затемнённая обложка; колонкой обложка (❤ и 👎 на ней), название, исполнитель с аватаром,
  // ползунок, кнопки; громкость — тонкая полоска внизу. Нашёлся текст — колонка уходит влево,
  // справа караоке. «T» прячет/показывает текст, правый клик по тексту — меню текста.
  import { onMount } from 'svelte'
  import { cubicOut } from 'svelte/easing'
  import Icon from '../components/Icon.svelte'
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

  let menuAt = $state<{ x: number; y: number } | null>(null)

  const tTitle = $derived(
    lyrics.status === 'loading'
      ? 'Ищу текст…'
      : lyrics.status === 'none'
        ? 'Текст не найден'
        : lyrics.visible
          ? 'Скрыть текст'
          : 'Показать текст',
  )

  function openArtist(ref: string) {
    if (hasSelection()) return
    lyrics.close()
    openRef(ref)
  }

  function openMenu(e: MouseEvent) {
    e.preventDefault()
    menuAt = { x: e.clientX, y: e.clientY }
  }

  function toggleMenu(e: MouseEvent) {
    if (menuAt) return (menuAt = null)
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect()
    menuAt = { x: r.right - 340, y: r.top - 8 - 330 }
  }

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

<div class="fs" transition:zoom role="dialog" aria-label="Полноэкранный плеер">
  <div class="bg" aria-hidden="true">
    {#if track?.cover_url}<img src={track.cover_url} alt="" />{/if}
  </div>

  <header data-tauri-drag-region>
    <div></div>
    <button class="collapse" aria-label="Свернуть" title="Свернуть" onclick={() => lyrics.close()}>
      <Icon name="chevronDown" size={22} />
    </button>
    <div class="win"><WindowControls back={false} /></div>
  </header>

  <div class="body" class:text={withText}>
    <section class="col">
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
            <Icon name="heart" size={18} filled={liked} />
          </button>
          <button class="on-cover right" aria-label="Не нравится" title="Не нравится — вместе со своей волной (W5)" disabled>
            <Icon name="dislike" size={18} />
          </button>
        {/if}
      </div>

      <h1 class="selectable" title={track?.title}>{track?.title ?? ''}</h1>
      <p class="artist selectable">
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
          icon={player.repeat === 'one' ? 'repeatOnce' : 'repeat'}
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
          <Icon name={player.playing ? 'pause' : 'play'} size={30} filled />
        </button>
        <IconButton icon="next" label="Вперёд" filled disabled={!track} onclick={() => player.next()} />
        <IconButton icon="shuffle" label="Перемешать" active={player.shuffle} disabled={!track} onclick={() => player.toggleShuffle()} />
      </div>
      {#if player.error}<p class="err">{player.error}</p>{/if}
    </section>

    {#if withText}
      <section class="lyrics-col">
        <LyricsView oncontextmenu={openMenu} />
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
    <div class="tools">
      {#if lyrics.shown}
        <button class="t" data-lyrics-menu-toggle class:on={!!menuAt} aria-label="Настройки текста" title="Настройки текста" onclick={toggleMenu}>
          <Icon name="dots" size={18} />
        </button>
      {/if}
      <button
        class="t"
        class:on={lyrics.visible && lyrics.status === 'ready'}
        class:muted={lyrics.status !== 'ready'}
        aria-label={tTitle}
        title={tTitle}
        onclick={() => lyrics.toggleVisible()}
      >
        <Icon name="letterT" size={18} />
      </button>
    </div>
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
  .bg img {
    position: absolute;
    inset: -10%;
    width: 120%;
    height: 120%;
    object-fit: cover;
    filter: blur(70px) saturate(120%) brightness(0.42);
    transform: scale(1.1);
  }
  .bg::after {
    content: '';
    position: absolute;
    inset: 0;
    background:
      radial-gradient(ellipse at 50% 40%, transparent 0%, rgba(0, 0, 0, 0.45) 80%),
      linear-gradient(to bottom, rgba(0, 0, 0, 0.2), rgba(0, 0, 0, 0.5));
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
  .tools {
    display: flex;
    justify-content: flex-end;
    align-items: center;
    gap: 4px;
  }
  .t {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    border-radius: 50%;
    color: rgba(255, 255, 255, 0.6);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .t:hover {
    color: #fff;
  }
  .t.on {
    background: rgba(255, 255, 255, 0.14);
    color: #fff;
  }
  .t.muted {
    opacity: 0.45;
  }
  @media (prefers-reduced-motion: reduce) {
    .col,
    .lyrics-col,
    .play.loading {
      animation: none;
    }
  }
</style>
