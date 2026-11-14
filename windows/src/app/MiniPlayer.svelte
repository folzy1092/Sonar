<script lang="ts">
  import Icon from '../components/Icon.svelte'
  import IconButton from '../components/IconButton.svelte'
  import { router } from './router.svelte'

  // Заглушка: плеер появится в W2. Пока — пустое состояние «Ничего не играет».
  type NowPlaying = { title: string; artist: string }
  let track = $state<NowPlaying | null>(null)
</script>

<footer class="mini">
  <div class="progress" aria-hidden="true"><span style="width: 0%"></span></div>

  <button class="now" onclick={() => router.go('player')} title="Открыть плеер">
    <div class="cover">
      <Icon name="music" size={20} />
    </div>
    <div class="meta">
      <span class="title">{track?.title ?? 'Ничего не играет'}</span>
      <span class="artist">{track?.artist ?? 'Найди трек в поиске или медиатеке'}</span>
    </div>
  </button>

  <div class="center">
    <IconButton icon="heart" label="В Любимые" size={18} disabled={!track} />
    <span class="sep"></span>
    <IconButton icon="repeat" label="Повтор" size={18} disabled={!track} />
    <IconButton icon="prev" label="Назад" size={18} filled disabled={!track} />
    <button class="play" aria-label="Играть" title="Играть" disabled={!track}>
      <Icon name="play" size={18} filled />
    </button>
    <IconButton icon="next" label="Вперёд" size={18} filled disabled={!track} />
    <IconButton icon="shuffle" label="Перемешать" size={18} disabled={!track} />
  </div>

  <div class="right">
    <IconButton icon="history" label="История" size={18} />
    <IconButton icon="volume" label="Громкость" size={18} />
    <IconButton icon="lyrics" label="Текст" size={18} disabled={!track} />
    <IconButton icon="queue" label="Очередь" size={18} disabled={!track} />
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
    overflow: hidden;
  }
  .progress {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    height: 2px;
    background: var(--border);
  }
  .progress span {
    display: block;
    height: 100%;
    background: var(--accent);
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
  .cover {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    flex-shrink: 0;
    border-radius: var(--radius-s);
    background: linear-gradient(135deg, var(--surface-3), var(--surface-2));
    color: var(--text-3);
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
  .right {
    display: flex;
    justify-content: flex-end;
    gap: 2px;
  }
</style>
