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
  import { hscroll } from '../lib/hscroll'
  import { wave } from '../player/my-wave.svelte'
  import { home } from './home-data.svelte'
  import { flyOrb } from '../lib/fly'
  import { colorOf } from '../theme/theme.svelte'
  import { css, inkFor, type RGB } from '../theme/palette'

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

  let playBtn: HTMLButtonElement | undefined = $state()
  /** Цвет кнопки: после прилёта сгустка — цвет обложки (как в Dotify), иначе — белая. */
  let btnColor = $state<RGB | null>(null)
  const ink = $derived(btnColor ? css(inkFor(btnColor)) : null)

  /** Клик по обложке волны: сгусток её цвета летит в кнопку, кнопка перекрашивается, трек играет. */
  async function playCover(e: MouseEvent, t: Track | undefined) {
    const el = e.currentTarget as Element
    const url = t?.cover_url ?? waveCover
    const color = (url ? await colorOf(url) : null) ?? ([255, 255, 255] as RGB)
    if (playBtn) void flyOrb(el, playBtn, color).then(() => (btnColor = color))
    if (!t || (wave.active && player.current?.ref === t.ref)) return wave.toggle()
    if (wave.active) {
      const i = player.upNext.findIndex((x) => x.ref === t.ref)
      if (i >= 0) return void player.jumpTo(i)
    }
    void wave.start(undefined, true, t.ref)
  }

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

<!-- Герой как у Dotify: без карточки; слева обложка и «Моя волна» (Roboto Flex), справа — сцена
     с двумя обложками следующих треков и большой кнопкой. -->
<section class="wave" class:on={wave.active}>
  <div class="lead">
    <button class="art" aria-label="Играть волну" onclick={(e) => playCover(e, waveTracks[0])}>
      <Cover url={waveCover} size={158} radius="26px" />
    </button>
    <div class="wave-text">
      <h1 class="font-wave"><span>Моя</span><span>волна</span></h1>
      <span class="mode">
        <Icon name="bolt" size={15} />
        {#if wave.loading && !wave.active}Подбираю…{:else if wave.active}{player.contextTitle ?? 'Играет'}{:else}Своя, по твоим лайкам{/if}
      </span>
    </div>
  </div>

  <div class="scene" class:still={!player.playing}>
    {#each waveTracks.slice(1, 3) as t, i (t.ref)}
      <button class="float f{i} idle-pause" aria-label="Играть «{t.title}»" title="{t.artist} — {t.title}" onclick={(e) => playCover(e, t)}>
        <Cover url={t.cover_url} size={64} radius="16px" />
      </button>
    {/each}
    <button
      bind:this={playBtn}
      class="wave-play"
      class:busy={wave.loading && !wave.active}
      style:background-color={btnColor ? css(btnColor) : null}
      style:color={ink}
      aria-label={playingWave ? 'Пауза' : 'Включить волну'}
      title={wave.error && !wave.active ? wave.error : playingWave ? 'Пауза' : 'Включить волну'}
      onclick={() => wave.toggle()}
    >
      <PlayPause playing={playingWave} size={30} />
    </button>
  </div>
</section>

<section class="block">
  <h2>{hello}{#if home.account?.name},
      <span class="who">
        {#if home.account.avatar_url}<img src={home.account.avatar_url} alt="" />{/if}
        {home.account.name}
      </span>{/if}</h2>
  {#if home.recent.length}
    <div class="row" use:cascade use:hscroll>
      <!-- «Недавнее» целиком — веер из трёх обложек, как у Dotify -->
      <button class="stack" title={recentTitle} onclick={() => playRecent(0)}>
        <span class="fan">
          {#each home.recent.slice(0, 3).reverse() as t, i (t.ref)}
            <span class="leaf l{home.recent.slice(0, 3).length - 1 - i}"><Cover url={t.cover_url} size={160} radius="var(--radius-l)" /></span>
          {/each}
        </span>
        <span class="st-title">{recentTitle}</span>
        <span class="st-sub">{tracksText(home.recent.length)}</span>
      </button>
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
    <div class="row" use:cascade use:hscroll>
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
      <div class="row" use:cascade use:hscroll>
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
  /* обложки плывут только пока играет музыка — на паузе стоят */
  .scene.still .float {
    /* появление доигрывает всегда, на паузе стоит только покачивание */
    animation-play-state: running, paused;
  }
  .wave {
    position: relative;
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    gap: 24px;
    padding: 8px 0 0;
  }
  .lead {
    display: flex;
    align-items: flex-end;
    gap: 28px;
    min-width: 0;
  }
  .art {
    flex-shrink: 0;
    border-radius: 26px;
    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.45);
    transition: transform var(--normal) var(--ease);
  }
  .art:hover {
    transform: scale(1.03);
  }
  .art:active {
    transform: scale(0.96);
  }
  .wave-text {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 12px;
    padding-bottom: 4px;
    min-width: 0;
  }
  h1 {
    display: flex;
    flex-direction: column;
    font-size: 54px;
    line-height: 0.92;
    letter-spacing: -0.02em;
  }
  .mode {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    color: var(--text-2);
    font-size: 13px;
    white-space: nowrap;
  }
  /* сцена справа: 288×224, обложки 64 px, кнопка 80 px (размеры Dotify) */
  .scene {
    position: relative;
    flex-shrink: 0;
    width: 288px;
    height: 224px;
  }
  .float {
    position: absolute;
    border-radius: 16px;
    box-shadow: 0 10px 26px rgba(0, 0, 0, 0.45);
    filter: saturate(0.55) brightness(0.9);
    cursor: pointer;
    transition: filter var(--normal) var(--ease);
    animation:
      float-in 0.6s var(--ease) both,
      bob 6s ease-in-out 0.6s infinite alternate;
  }
  .float:hover {
    filter: none;
  }
  .float.f0 {
    right: 8px;
    top: 8px;
    animation-delay: 0.08s, 1.4s;
  }
  .float.f1 {
    right: 128px;
    top: 96px;
  }
  @keyframes float-in {
    from {
      opacity: 0;
      transform: translateY(14px) scale(0.9);
    }
  }
  @keyframes bob {
    to {
      transform: translateY(-7px);
    }
  }
  .wave-play {
    position: absolute;
    right: 8px;
    bottom: 0;
    display: grid;
    place-items: center;
    width: 80px;
    height: 80px;
    border-radius: 50%;
    background-color: var(--text);
    color: var(--on-text);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.45);
    transition:
      background-color 0.4s cubic-bezier(0.16, 1, 0.3, 1),
      color 0.4s cubic-bezier(0.16, 1, 0.3, 1),
      transform 0.22s cubic-bezier(0.16, 1, 0.3, 1),
      opacity 0.22s ease,
      filter 0.22s ease;
  }
  .wave-play:hover {
    transform: scale(1.05);
  }
  .wave-play:active {
    transform: scale(0.93);
  }
  /* загрузка — как у Dotify: прозрачнее, меньше, чуть размыта */
  .wave-play.busy {
    opacity: 0.35;
    transform: scale(0.82);
    filter: blur(1.5px);
    pointer-events: none;
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
  .stack {
    display: flex;
    flex-direction: column;
    gap: 2px;
    width: 280px;
    flex-shrink: 0;
    text-align: left;
  }
  .fan {
    position: relative;
    height: 160px;
    margin-bottom: 8px;
  }
  .leaf {
    position: absolute;
    top: 0;
    left: 0;
    border-radius: var(--radius-l);
    box-shadow: 8px 0 24px rgba(0, 0, 0, 0.45);
    transition: transform var(--normal) var(--ease);
  }
  .leaf.l0 {
    z-index: 3;
  }
  .leaf.l1 {
    z-index: 2;
    transform: translateX(62px) scale(0.86);
    transform-origin: left center;
  }
  .leaf.l2 {
    z-index: 1;
    transform: translateX(112px) scale(0.74);
    transform-origin: left center;
  }
  .stack:hover .leaf.l1 {
    transform: translateX(74px) scale(0.86);
  }
  .stack:hover .leaf.l2 {
    transform: translateX(136px) scale(0.74);
  }
  .st-title {
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .st-sub {
    font-size: 12px;
    color: var(--text-2);
  }
</style>
