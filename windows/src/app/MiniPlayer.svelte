<script lang="ts">
  // Мини-плеер в стиле «Гибрид» (reference/pc/гибрид.png, mini.style = hybrid): прогресс — фоном,
  // по центру простые значки без кругов, справа капсула скорость · громкость · очередь · текст.
  import Icon from '../components/Icon.svelte'
  import IconButton from '../components/IconButton.svelte'
  import Cover from '../components/Cover.svelte'
  import PlayPause from '../components/PlayPause.svelte'
  import SpeedButton from '../player/SpeedButton.svelte'
  import Volume from '../player/Volume.svelte'
  import { player } from '../player/player.svelte'
  import { openRef, router } from './router.svelte'
  import { library } from '../lib/library.svelte'
  import { hasSelection } from '../lib/selection'
  import { replay } from '../lib/replay'
  import { lyrics } from '../lyrics/lyrics.svelte'

  const track = $derived(player.current)
  const duration = $derived(player.durationMs || track?.duration_ms || 0)
  const liked = $derived(library.isLiked(track?.ref))
  const openPlayer = () => !hasSelection() && router.go('player')
  const progress = $derived(duration ? Math.min(100, (player.positionMs / duration) * 100) : 0)

  // Прогресс в стиле «Гибрид» — весь фон мини-плеера: клик по пустому месту (не по кнопке, ссылке
  // или тексту) перематывает туда, как в Dotify. Тянуть тоже можно.
  let bar: HTMLElement | undefined = $state()
  let dragging = $state(false)
  const isControl = (t: EventTarget | null) =>
    !!(t as HTMLElement | null)?.closest?.('button, a, input, [role="link"], .selectable, .capsule')

  function seekAt(clientX: number) {
    if (!bar || !duration || !track) return
    const r = bar.getBoundingClientRect()
    player.seek(Math.max(0, Math.min(1, (clientX - r.left) / r.width)) * duration)
  }

  function down(e: PointerEvent) {
    if (e.button !== 0 || isControl(e.target) || !track) return
    dragging = true
    bar?.setPointerCapture(e.pointerId)
    seekAt(e.clientX)
  }
</script>

<footer
  class="mini"
  class:seekable={!!track}
  class:dragging
  bind:this={bar}
  onpointerdown={down}
  onpointermove={(e) => dragging && seekAt(e.clientX)}
  onpointerup={() => (dragging = false)}
  onpointercancel={() => (dragging = false)}
>
  <div class="fill" style:width="{progress}%" aria-hidden="true"></div>

  <div class="left">
    <div class="now">
      <button
        class="art"
        disabled={!track}
        onclick={() => lyrics.open()}
        aria-label="Полноэкранный плеер"
        title="Полноэкранный плеер"
      >
        <Cover url={track?.cover_url} size={46} />
        <span class="expand" aria-hidden="true"><Icon name="expand" size={18} /></span>
      </button>
      <span class="meta selectable" use:replay={track?.ref}>
        <span class="title" role="link" tabindex="-1" onclick={openPlayer} onkeydown={() => {}}>{track?.title ?? 'Ничего не играет'}</span>
        {#if player.error}
          <span class="artist err" title={player.error}>{player.error}</span>
        {:else if track}
          <span class="artist">
            {#each track.artists as a, i (a.ref + i)}{#if i},&nbsp;{/if}<span
                class="link"
                role="link"
                tabindex="-1"
                onclick={() => !hasSelection() && openRef(a.ref)}
                onkeydown={() => {}}>{a.name}</span
              >{:else}{track.artist}{/each}
          </span>
        {:else}
          <span class="artist">Найди трек в поиске</span>
        {/if}
      </span>
    </div>
    {#if track}
      <IconButton icon="heart" label={liked ? 'Удалить из Любимых' : 'В Любимые'} size={17} filled={liked} active={liked} pulse={liked} onclick={() => library.toggleLike(track)} />
    {/if}
  </div>

  <div class="center">
    <IconButton
      icon={player.repeat === 'one' ? 'repeatOnce' : player.repeat === 'all' ? 'repeat' : 'repeatOff'}
      label={player.repeat === 'off' ? 'Повтор: выкл' : player.repeat === 'all' ? 'Повтор: всё' : 'Повтор: трек'}
      size={18}
      active={player.repeat !== 'off'}
      disabled={!track}
      onclick={() => player.cycleRepeat()}
    />
    <IconButton icon="prev" label="Назад" size={18} filled disabled={!track} onclick={() => player.prev()} />
    <button
      class="play"
      class:loading={player.loading}
      aria-label={player.playing ? 'Пауза' : 'Играть'}
      title={player.playing ? 'Пауза' : 'Играть'}
      disabled={!track}
      onclick={() => player.toggle()}
    >
      <PlayPause playing={player.playing} size={22} />
    </button>
    <IconButton icon="next" label="Вперёд" size={18} filled disabled={!track} onclick={() => player.next()} />
    <IconButton icon="shuffle" label="Перемешать" size={18} active={player.shuffle} disabled={!track} onclick={() => player.toggleShuffle()} />
  </div>

  <div class="right">
    <div class="capsule">
      <SpeedButton />
      <Volume />
      <IconButton icon="queue" label="Очередь" size={17} disabled={!track} onclick={() => router.go('player')} />
      <IconButton icon="letterT" label="Текст и полноэкранный плеер" size={17} active={lyrics.fullscreen} disabled={!track} onclick={() => (lyrics.fullscreen ? lyrics.close() : lyrics.open())} />
    </div>
  </div>
</footer>

<style>
  .mini {
    position: relative;
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr);
    align-items: center;
    gap: 16px;
    height: var(--player-h);
    padding: 0 12px 0 8px;
    border-radius: var(--radius-l);
    background: var(--surface-1);
    border: 1px solid var(--border);
    overflow: hidden;
  }
  .fill {
    position: absolute;
    inset: 0 auto 0 0;
    background: var(--hover);
    pointer-events: none;
  }
  .mini.dragging .fill {
    transition: none;
  }
  .left,
  .center,
  .right {
    position: relative;
  }
  .left {
    display: flex;
    align-items: center;
    gap: 4px;
    min-width: 0;
  }
  .now {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
    padding: 4px;
    border-radius: var(--radius-m);
    text-align: left;
  }
  .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .title,
  .artist {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .title {
    font-weight: 600;
  }
  .art {
    position: relative;
    display: grid;
    border-radius: var(--radius-s);
    overflow: hidden;
  }
  /* при наведении на обложку — две стрелки: откроется полноэкранный плеер */
  .expand {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    background: rgba(0, 0, 0, 0.45);
    color: #fff;
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .expand :global(svg) {
    transform: scale(0.7);
    transition: transform var(--normal) var(--ease);
  }
  .art:hover:not(:disabled) .expand {
    opacity: 1;
  }
  .art:hover:not(:disabled) .expand :global(svg) {
    transform: scale(1);
  }
  .art:active:not(:disabled) .expand :global(svg) {
    transform: scale(0.9);
  }
  .title,
  .link {
    cursor: pointer;
  }
  .title:hover,
  .link:hover {
    text-decoration: underline;
    text-underline-offset: 2px;
  }
  .artist {
    font-size: 12px;
    color: var(--text-3);
  }
  .artist.err {
    color: var(--danger);
  }
  .center {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .play {
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
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
  .right {
    display: flex;
    justify-content: flex-end;
  }
  .capsule {
    display: flex;
    align-items: center;
    gap: 2px;
    padding: 3px 6px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
  }
  .capsule :global(.icon-btn) {
    width: 32px;
    height: 32px;
    border-radius: 999px;
  }
  .capsule :global(.icon-btn:hover:not(:disabled)) {
    background: none;
  }
  @media (prefers-reduced-motion: reduce) {
    .play.loading {
      animation: none;
    }
    .fill {
      transition: none;
    }
  }
</style>
