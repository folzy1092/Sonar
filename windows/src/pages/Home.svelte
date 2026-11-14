<script lang="ts">
  import Icon from '../components/Icon.svelte'
  import Tile from '../components/Tile.svelte'

  function greeting(hour: number) {
    if (hour < 5) return 'Доброй ночи'
    if (hour < 12) return 'Доброе утро'
    if (hour < 18) return 'Добрый день'
    if (hour < 23) return 'Добрый вечер'
    return 'Доброй ночи'
  }

  const hello = greeting(new Date().getHours())
  const ghosts = Array.from({ length: 6 })
</script>

<section class="wave">
  <div class="collage" aria-hidden="true">
    <span></span><span></span><span></span><span></span>
  </div>
  <div class="wave-text">
    <h1>Моя<br />волна</h1>
    <span class="mode"><Icon name="bolt" size={15} /> Спокойная</span>
  </div>
  <button class="wave-play" aria-label="Включить волну" title="Волна заработает после подключения сервисов">
    <Icon name="play" size={30} filled />
  </button>
</section>

<section class="block">
  <h2>{hello}</h2>
  <div class="row">
    {#each ghosts as _, i (i)}
      <Tile title="Пока пусто" subtitle="Здесь будет недавнее" ghost />
    {/each}
  </div>
</section>

<section class="block">
  <h2>Релизы</h2>
  <div class="row">
    {#each ghosts as _, i (i)}
      <Tile title="Скоро" subtitle="Новинки исполнителей" ghost />
    {/each}
  </div>
</section>

<style>
  .wave {
    position: relative;
    display: flex;
    align-items: center;
    gap: 28px;
    padding: 24px;
    border-radius: var(--radius-xl);
    background:
      radial-gradient(120% 140% at 0% 0%, rgba(255, 255, 255, 0.08), transparent 55%),
      radial-gradient(90% 120% at 100% 100%, rgba(255, 255, 255, 0.05), transparent 60%),
      var(--surface-1);
    border: 1px solid var(--border);
    overflow: hidden;
  }
  .collage {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 4px;
    width: 156px;
    height: 156px;
    flex-shrink: 0;
    border-radius: var(--radius-l);
    overflow: hidden;
  }
  .collage span {
    background: var(--surface-3);
  }
  .collage span:nth-child(2),
  .collage span:nth-child(3) {
    background: var(--surface-2);
  }
  .wave-text {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  h1 {
    font-size: 48px;
    line-height: 0.95;
    font-weight: 800;
  }
  .mode {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    color: var(--text-2);
    font-size: 13px;
  }
  .wave-play {
    display: grid;
    place-items: center;
    width: 72px;
    height: 72px;
    margin-left: auto;
    padding-left: 4px;
    border-radius: 50%;
    background: var(--accent);
    color: var(--accent-ink);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.45);
    transition: transform var(--normal) var(--ease);
  }
  .wave-play:hover {
    transform: scale(1.06);
  }
  .wave-play:active {
    transform: scale(0.96);
  }
  .block {
    margin-top: 32px;
  }
  h2 {
    font-size: 24px;
    font-weight: 800;
    margin-bottom: 14px;
  }
  .row {
    display: flex;
    gap: 18px;
    overflow: hidden;
  }
</style>
