<script lang="ts">
  import Icon from '../components/Icon.svelte'
  import IconButton from '../components/IconButton.svelte'
  import Cover from '../components/Cover.svelte'
  import SpeedButton from '../player/SpeedButton.svelte'
  import Volume from '../player/Volume.svelte'
  import { player } from '../player/player.svelte'
  import { router } from './router.svelte'

  const track = $derived(player.current)
  const duration = $derived(player.durationMs || track?.duration_ms || 0)
  const progress = $derived(duration ? Math.min(100, (player.positionMs / duration) * 100) : 0)

  function seekFromBar(e: MouseEvent) {
    const el = e.currentTarget as HTMLElement
    const r = el.getBoundingClientRect()
    player.seek(((e.clientX - r.left) / r.width) * duration)
  }
</script>

<footer class="mini">
  <button class="progress" aria-label="Перемотка" disabled={!track} onclick={seekFromBar}>
    <span style:width="{progress}%"></span>
  </button>

  <button class="now" onclick={() => router.go('player')} title="Открыть плеер">
    <Cover url={track?.cover_url} size={44} />
    <div class="meta">
      <span class="title">{track?.title ?? 'Ничего не играет'}</span>
      {#if player.error}
        <span class="artist err" title={player.error}>{player.error}</span>
      {:else}
        <span class="artist">{track?.artist ?? 'Найди трек в поиске или медиатеке'}</span>
      {/if}
    </div>
  </button>

  <div class="center">
    <IconButton icon="heart" label="В Любимые (W3)" size={18} disabled />
    <span class="sep"></span>
    <IconButton
      icon={player.repeat === 'one' ? 'repeatOnce' : 'repeat'}
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
      <Icon name={player.playing ? 'pause' : 'play'} size={18} filled />
    </button>
    <IconButton icon="next" label="Вперёд" size={18} filled disabled={!track} onclick={() => player.next()} />
    <IconButton icon="shuffle" label="Перемешать" size={18} active={player.shuffle} disabled={!track} onclick={() => player.toggleShuffle()} />
  </div>

  <div class="right">
    <SpeedButton />
    <Volume />
    <IconButton icon="lyrics" label="Текст (W4)" size={18} disabled />
    <IconButton icon="queue" label="Очередь" size={18} disabled={!track} onclick={() => router.go('player')} />
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
    padding: 0 12px 0 10px;
    border-radius: var(--radius-l);
    background: var(--surface-1);
    border: 1px solid var(--border);
  }
  .progress {
    position: absolute;
    left: 14px;
    right: 14px;
    bottom: -1px;
    height: 7px;
    padding: 3px 0 2px;
    background-clip: content-box;
    background-color: var(--border);
    cursor: pointer;
  }
  .progress:disabled {
    cursor: default;
  }
  .progress span {
    display: block;
    height: 100%;
    background: var(--accent);
    border-radius: 2px;
    transition: width 0.25s linear;
  }
  .now {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
    text-align: left;
    border-radius: var(--radius-m);
    padding: 4px 8px 4px 4px;
    justify-self: start;
    max-width: 100%;
    transition: background var(--fast) var(--ease);
  }
  .now:hover {
    background: var(--hover);
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
    gap: 4px;
  }
  .sep {
    width: 1px;
    height: 18px;
    margin: 0 6px;
    background: var(--border-strong);
  }
  .play {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    margin: 0 4px;
    border-radius: 50%;
    background: var(--accent);
    color: var(--accent-ink);
    transition:
      transform var(--fast) var(--ease),
      opacity var(--fast) var(--ease);
  }
  .play:hover:not(:disabled) {
    transform: scale(1.06);
  }
  .play:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .play.loading {
    animation: pulse 1s ease-in-out infinite;
  }
  @keyframes pulse {
    50% {
      opacity: 0.6;
    }
  }
  .right {
    display: flex;
    justify-content: flex-end;
    align-items: center;
    gap: 2px;
  }
  @media (prefers-reduced-motion: reduce) {
    .play.loading {
      animation: none;
    }
  }
</style>
