<script lang="ts">
  import Icon from '../components/Icon.svelte'
  import IconButton from '../components/IconButton.svelte'
</script>

<div class="player">
  <div class="cover"><Icon name="music" size={72} stroke={1.3} /></div>

  <div class="info">
    <h1>Ничего не играет</h1>
    <p class="artist">Включи трек — здесь будут обложка, текст и очередь</p>

    <div class="seek">
      <span>0:00</span>
      <div class="bar"><span></span></div>
      <span>0:00</span>
    </div>

    <div class="controls">
      <IconButton icon="repeat" label="Повтор" disabled />
      <IconButton icon="prev" label="Назад" filled disabled />
      <button class="play" aria-label="Играть" disabled><Icon name="play" size={26} filled /></button>
      <IconButton icon="next" label="Вперёд" filled disabled />
      <IconButton icon="shuffle" label="Перемешать" disabled />
    </div>
  </div>
</div>

<section class="queue">
  <h2>Далее</h2>
  <p>Очередь пуста.</p>
</section>

<style>
  .player {
    display: flex;
    align-items: center;
    gap: 40px;
    padding-top: 8px;
  }
  .cover {
    display: grid;
    place-items: center;
    width: 300px;
    height: 300px;
    flex-shrink: 0;
    border-radius: var(--radius-xl);
    background: linear-gradient(145deg, var(--surface-3), var(--surface-1));
    border: 1px solid var(--border);
    color: var(--text-3);
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.5);
  }
  .info {
    flex: 1;
    min-width: 0;
    max-width: 520px;
  }
  h1 {
    font-size: 36px;
    font-weight: 800;
  }
  .artist {
    margin: 6px 0 0;
    color: var(--text-2);
  }
  .seek {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-top: 28px;
    font-size: 12px;
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .bar {
    flex: 1;
    height: 4px;
    border-radius: 4px;
    background: var(--surface-3);
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
    opacity: 0.4;
    cursor: default;
  }
  .queue {
    margin-top: 40px;
  }
  h2 {
    font-size: 22px;
    font-weight: 800;
  }
  .queue p {
    color: var(--text-3);
  }
</style>
