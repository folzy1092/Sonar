<script lang="ts">
  import Icon from '../components/Icon.svelte'
  import IconButton from '../components/IconButton.svelte'
  import Cover from '../components/Cover.svelte'
  import TrackRow from '../components/TrackRow.svelte'
  import SeekBar from '../player/SeekBar.svelte'
  import { player, speedModes } from '../player/player.svelte'

  const track = $derived(player.current)
  const contextTitle = $derived(
    player.context === 'search' ? 'Из поиска' : player.context === 'favorites' ? 'Любимые' : 'Очередь',
  )
</script>

<div class="player">
  <div class="cover-wrap">
    <Cover url={track?.cover_url} size={300} radius="var(--radius-xl)" />
  </div>

  <div class="info">
    <h1 title={track?.title}>{track?.title ?? 'Ничего не играет'}</h1>
    <p class="artist">{track ? track.artist : 'Включи трек — здесь будут обложка, текст и очередь'}</p>
    {#if player.speedMode !== 'normal'}
      <span class="mode">{speedModes[player.speedMode].label} · {speedModes[player.speedMode].rate}×</span>
    {/if}
    {#if player.error}<p class="err">{player.error}</p>{/if}

    <div class="seek"><SeekBar /></div>

    <div class="controls">
      <IconButton
        icon={player.repeat === 'one' ? 'repeatOnce' : 'repeat'}
        label="Повтор"
        active={player.repeat !== 'off'}
        disabled={!track}
        onclick={() => player.cycleRepeat()}
      />
      <IconButton icon="prev" label="Назад" filled disabled={!track} onclick={() => player.prev()} />
      <button class="play" aria-label={player.playing ? 'Пауза' : 'Играть'} disabled={!track} onclick={() => player.toggle()}>
        <Icon name={player.playing ? 'pause' : 'play'} size={26} filled />
      </button>
      <IconButton icon="next" label="Вперёд" filled disabled={!track} onclick={() => player.next()} />
      <IconButton icon="shuffle" label="Перемешать" active={player.shuffle} disabled={!track} onclick={() => player.toggleShuffle()} />
    </div>
  </div>
</div>

<section class="queue">
  {#if track}
    <p class="ctx">{contextTitle}{player.shuffle ? ' · перемешано' : ''}</p>
    <h2>Сейчас играет</h2>
    <TrackRow {track} onplay={() => player.toggle()} />
  {/if}
  <h2>Далее</h2>
  {#if player.upNext.length}
    <div class="list">
      {#each player.upNext as t, i (t.ref + i)}
        <TrackRow track={t} onplay={() => player.jumpTo(i)} />
      {/each}
    </div>
  {:else}
    <p class="empty">Очередь пуста.</p>
  {/if}
</section>

<style>
  .player {
    display: flex;
    align-items: center;
    gap: 40px;
    padding-top: 8px;
  }
  .cover-wrap {
    border-radius: var(--radius-xl);
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.5);
  }
  .info {
    flex: 1;
    min-width: 0;
    max-width: 560px;
  }
  h1 {
    font-size: 34px;
    font-weight: 800;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .artist {
    margin: 6px 0 0;
    color: var(--text-2);
  }
  .mode {
    display: inline-block;
    margin-top: 10px;
    padding: 3px 10px;
    border-radius: 999px;
    background: var(--accent-soft);
    font-size: 12px;
    font-weight: 700;
  }
  .err {
    margin: 10px 0 0;
    color: var(--danger);
    font-size: 13px;
  }
  .seek {
    margin-top: 28px;
  }
  .controls {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    margin-top: 18px;
  }
  .play {
    display: grid;
    place-items: center;
    width: 56px;
    height: 56px;
    border-radius: 50%;
    background: var(--accent);
    color: var(--accent-ink);
    transition: transform var(--fast) var(--ease);
  }
  .play:hover:not(:disabled) {
    transform: scale(1.05);
  }
  .play:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .queue {
    margin-top: 40px;
  }
  .ctx {
    margin: 0 0 6px;
    font-size: 12px;
    color: var(--text-3);
  }
  h2 {
    margin: 18px 0 8px;
    font-size: 20px;
    font-weight: 800;
  }
  .list {
    display: flex;
    flex-direction: column;
  }
  .empty {
    color: var(--text-3);
  }
</style>
