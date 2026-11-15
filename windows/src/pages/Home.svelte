<script lang="ts">
  // Главная по reference/pc/Screenshot_20, 23: «Моя волна» (обложка, заголовок, источник, плавающие
  // обложки следующих треков, большая кнопка), приветствие с недавним, «Релизы», «Похожее».
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import Tile from '../components/Tile.svelte'
  import Cover from '../components/Cover.svelte'
  import PlayPause from '../components/PlayPause.svelte'
  import { api, type Album, type Track } from '../lib/api'
  import { tracksText } from '../lib/format'
  import { cascade } from '../lib/cascade'
  import { openRef } from '../app/router.svelte'
  import { player } from '../player/player.svelte'
  import { wave } from '../player/my-wave.svelte'
  import { home } from './home-data.svelte'

  function greeting(hour: number) {
    if (hour < 5) return 'Доброй ночи'
    if (hour < 12) return 'Доброе утро'
    if (hour < 18) return 'Добрый день'
    if (hour < 23) return 'Добрый вечер'
    return 'Доброй ночи'
  }

  const hello = greeting(new Date().getHours())

  onMount(() => {
    void home.load()
    if (!wave.active) void wave.prefetch()
  })

  // Обложки волны: играет — текущий и следующие, иначе — подобранная порция.
  const waveTracks = $derived<Track[]>(
    wave.active && player.current ? [player.current, ...player.upNext.slice(0, 2)] : wave.preview.slice(0, 3),
  )
  const waveCover = $derived(waveTracks[0]?.cover_url ?? home.recent[0]?.cover_url ?? null)
  const playingWave = $derived(wave.active && player.playing)

  const recentTitle = $derived(
    home.recent
      .slice(0, 2)
      .map((t) => t.title)
      .join(', '),
  )

  function playRecent(i: number) {
    void player.playList(home.recent, i, 'recent', 'Недавнее')
  }
  function playSimilar(i: number) {
    void player.playList(home.similar, i, 'similar', 'Похожее')
  }
  function openAlbum(a: Album) {
    openRef(a.ref)
  }
</script>

<section class="wave" class:on={wave.active}>
  <div class="art">
    <Cover url={waveCover} size={158} radius="var(--radius-l)" />
  </div>
  <div class="wave-text">
    <h1>Моя<br />волна</h1>
    <span class="mode">
      <Icon name="bolt" size={15} />
      {#if wave.loading && !wave.active}Подбираю…{:else if wave.active}{player.contextTitle ?? 'Играет'}{:else}Своя, по твоим лайкам{/if}
    </span>
  </div>

  <div class="floats" aria-hidden="true">
    {#each waveTracks.slice(1, 3) as t, i (t.ref)}
      <span class="float f{i}"><Cover url={t.cover_url} size={i ? 58 : 66} radius="12px" /></span>
    {/each}
  </div>

  <button
    class="wave-play"
    class:busy={wave.loading && !wave.active}
    aria-label={playingWave ? 'Пауза' : 'Включить волну'}
    title={wave.error && !wave.active ? wave.error : playingWave ? 'Пауза' : 'Включить волну'}
    onclick={() => wave.toggle()}
  >
    <PlayPause playing={playingWave} size={30} />
  </button>
</section>

<section class="block">
  <h2>{hello}{#if home.account?.name},
      <span class="who">
        {#if home.account.avatar_url}<img src={home.account.avatar_url} alt="" />{/if}
        {home.account.name}
      </span>{/if}</h2>
  {#if home.recent.length}
    <div class="row" use:cascade>
      <Tile
        title={recentTitle}
        subtitle={tracksText(home.recent.length)}
        covers={home.recent.slice(0, 4).map((t) => t.cover_url).filter((c): c is string => !!c)}
        icon="history"
        onclick={() => playRecent(0)}
      />
      {#each home.recent as t, i (t.ref)}
        <Tile title={t.title} subtitle={t.artist} image={t.cover_url} source={t.ref} onclick={() => playRecent(i)} />
      {/each}
    </div>
  {:else if home.loading}
    {@render skeleton()}
  {:else}
    <p class="empty">Здесь будет то, что ты слушал недавно.</p>
  {/if}
</section>

<section class="block">
  <h2>Релизы</h2>
  {#if home.releases.length}
    <div class="row" use:cascade>
      {#each home.releases as a (a.ref)}
        <Tile title={a.title} subtitle={a.artist} meta={a.year ? String(a.year) : undefined} image={a.cover_url} icon="disc" source={a.ref} onclick={() => openAlbum(a)} />
      {/each}
    </div>
  {:else if home.releasesLoading}
    {@render skeleton()}
  {:else}
    <p class="empty">Подпишись на исполнителей или послушай их — здесь появятся их свежие альбомы.</p>
  {/if}
</section>

{#if home.similar.length || home.similarLoading}
  <section class="block">
    <h2>Похожее{#if home.similarTo}<small> на «{home.similarTo.title}»</small>{/if}</h2>
    {#if home.similar.length}
      <div class="row" use:cascade>
        {#each home.similar as t, i (t.ref)}
          <Tile title={t.title} subtitle={t.artist} image={t.cover_url} source={t.ref} onclick={() => playSimilar(i)} />
        {/each}
      </div>
    {:else}
      {@render skeleton()}
    {/if}
  </section>
{/if}

{#snippet skeleton()}
  <div class="row" aria-label="Загрузка…">
    {#each { length: 7 } as _, i (i)}
      <div class="sk-tile"><div class="sk-cover skel"></div><div class="sk-line skel"></div><div class="sk-line short skel"></div></div>
    {/each}
  </div>
{/snippet}

<style>
  .wave {
    position: relative;
    display: flex;
    align-items: center;
    gap: 28px;
    padding: 24px;
    min-height: 206px;
    border-radius: var(--radius-xl);
    background:
      radial-gradient(120% 140% at 0% 0%, var(--accent-soft), transparent 55%),
      radial-gradient(90% 120% at 100% 100%, rgba(255, 255, 255, 0.05), transparent 60%),
      var(--surface-1);
    border: 1px solid var(--border);
    overflow: hidden;
    transition: background var(--normal) var(--ease);
  }
  .art {
    flex-shrink: 0;
    border-radius: var(--radius-l);
    box-shadow: 0 14px 40px rgba(0, 0, 0, 0.45);
    transition: transform var(--normal) var(--ease);
  }
  .wave.on .art {
    transform: rotate(-2deg) scale(1.02);
  }
  .wave-text {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-width: 0;
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
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .floats {
    position: relative;
    flex: 1;
    align-self: stretch;
    min-width: 80px;
  }
  .float {
    position: absolute;
    display: block;
    border-radius: 12px;
    box-shadow: 0 10px 26px rgba(0, 0, 0, 0.45);
    animation:
      float-in 0.6s var(--ease) both,
      bob 6s ease-in-out 0.6s infinite alternate;
  }
  .float.f0 {
    right: 30%;
    top: 46%;
  }
  .float.f1 {
    right: 4%;
    top: 2%;
    animation-delay: 0.08s, 1.4s;
  }
  @keyframes float-in {
    from {
      opacity: 0;
      transform: translateY(14px) scale(0.9);
    }
  }
  @keyframes bob {
    to {
      transform: translateY(-8px) rotate(2deg);
    }
  }
  .wave-play {
    position: relative;
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: 72px;
    height: 72px;
    margin-left: auto;
    border-radius: 50%;
    background: var(--accent);
    color: var(--accent-ink);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.45);
    transition: transform var(--normal) var(--ease);
  }
  .wave-play :global(.play) {
    padding-left: 3px;
  }
  .wave-play:hover {
    transform: scale(1.06);
  }
  .wave-play:active {
    transform: scale(0.94);
  }
  .wave-play.busy {
    animation: breathe 1.1s ease-in-out infinite;
  }
  @keyframes breathe {
    50% {
      transform: scale(0.95);
      opacity: 0.75;
    }
  }
  .block {
    margin-top: 32px;
  }
  h2 {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 24px;
    font-weight: 800;
    margin-bottom: 14px;
  }
  h2 small {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-3);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .who {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    color: var(--accent);
  }
  .who img {
    width: 30px;
    height: 30px;
    border-radius: 50%;
    object-fit: cover;
  }
  .row {
    display: flex;
    gap: 18px;
    overflow-x: auto;
    overflow-y: hidden;
    padding-bottom: 4px;
    scrollbar-width: none;
  }
  .row::-webkit-scrollbar {
    display: none;
  }
  .empty {
    margin: 0;
    color: var(--text-3);
  }
  .sk-tile {
    display: flex;
    flex-direction: column;
    gap: 8px;
    width: 160px;
    flex-shrink: 0;
  }
  .sk-cover {
    aspect-ratio: 1;
    border-radius: var(--radius-l);
  }
  .sk-line {
    height: 12px;
    width: 80%;
    border-radius: 6px;
  }
  .sk-line.short {
    width: 50%;
  }
</style>
