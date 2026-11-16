<script lang="ts">
  // Главная по reference/pc/Screenshot_20, 23: «Моя волна» (обложка, заголовок, источник, плавающие
  // обложки следующих треков, большая кнопка); под ней приветствие с ником и подборкой под время
  // суток, «Релизы недели» тех, на кого стоят лайки, «Похожее»; ниже — тренды, плейлисты
  // пользователей и чарты Sonar (с сервера, до него — заготовка).
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import Tile from '../components/Tile.svelte'
  import Shelf from '../components/Shelf.svelte'
  import Cover from '../components/Cover.svelte'
  import LoadFx from '../components/LoadFx.svelte'
  import PlayPause from '../components/PlayPause.svelte'
  import { api, type Album, type Track } from '../lib/api'
  import { tracksText } from '../lib/format'
  import { openRef } from '../app/router.svelte'
  import { player } from '../player/player.svelte'
  import { settings } from '../lib/settings.svelte'
  import { WAVE_MODES } from '../player/my-wave.svelte'
  import { reducedMotion } from '../lib/motion'
  import { cubicOut, cubicIn } from 'svelte/easing'
  import { wave } from '../player/my-wave.svelte'
  import { DAYPART_TEXT, daypart, home, releaseLabel, weekReleases } from './home-data.svelte'
  import { indicator } from '../lib/indicator'
  import { flyOrb } from '../lib/fly'
  import { colorOf } from '../theme/theme.svelte'
  import { css, inkFor, type RGB } from '../theme/palette'
  import { t } from '../lib/i18n.svelte'

  const part = DAYPART_TEXT[daypart(new Date().getHours())]
  const hello = part.hello
  // приветствие — из профиля Sonar (Аккаунт → Профиль), пусто — из подключённого сервиса
  const me = $derived({
    name: settings.get('profile.name') || home.account?.name || '',
    avatar: settings.get('profile.avatar') || home.account?.avatar_url || '',
  })

  // «Релизы недели»; за неделю у любимых ничего — показываем самые свежие под другим заголовком
  const week = $derived(weekReleases(home.releases))
  const releases = $derived(week.length ? week : home.releases)

  // Чарты Sonar (SPEC §4.7): период переключается капсулой; данные — с сервера
  const CHART_PERIODS = [
    { id: 'week', label: 'Неделя' },
    { id: 'month', label: 'Месяц' },
    { id: 'all', label: 'Всё время' },
  ] as const
  let chartPeriod = $state<(typeof CHART_PERIODS)[number]['id']>('week')

  onMount(() => {
    void home.load()
    wave.ensureCovers()
  })

  // Обложки волны — «лицо» её стиля (wave.covers): от перемотки треков не меняются.
  const waveTracks = $derived<Track[]>(wave.covers)
  // Большая обложка — играющий трек: подсветка (--cover-glow) идёт от его цвета, и обложка с ней совпадает
  // (решение владельца 2026-11-17); ничего не играет — «лицо» волны.
  const waveCover = $derived(player.current?.cover_url ?? waveTracks[0]?.cover_url ?? home.recent[0]?.cover_url ?? null)
  const playingWave = $derived(wave.active && player.playing)

  const titles = (list: Track[]) =>
    list
      .slice(0, 2)
      .map((t) => t.title)
      .join(', ')
  const recentTitle = $derived(titles(home.recent))

  let playBtn: HTMLButtonElement | undefined = $state()
  /** Цвет кнопки: после прилёта сгустка — цвет обложки (как в Dotify), иначе — белая. */
  let btnColor = $state<RGB | null>(null)
  const ink = $derived(btnColor ? css(inkFor(btnColor)) : null)

  /** Обложка выбирает стиль волны: сгусток её цвета летит в кнопку, кнопка перекрашивается.
   *  Большая — обычная волна режима (играет — пауза), маленькая — волна в стиле этого трека:
   *  он звучит первым, дальше — похожие на него, и стиль держится, сколько ни листай треки. */
  async function playCover(e: MouseEvent, t: Track | undefined, style: boolean) {
    const el = e.currentTarget as Element
    const url = t?.cover_url ?? waveCover
    const color = (url ? await colorOf(url) : null) ?? ([255, 255, 255] as RGB)
    if (playBtn) void flyOrb(el, playBtn, color).then(() => (btnColor = color))
    if (!style || !t) {
      if (wave.active && !wave.seed) return wave.toggle()
      return void wave.start(undefined, true, t?.ref)
    }
    if (wave.active && wave.seed?.ref === t.ref) return wave.toggle()
    void wave.start(t)
  }

  function playMix(i: number) {
    void player.playList(home.mix, i, 'daypart', t(part.mix))
  }
  function playRecent(i: number) {
    void player.playList(home.recent, i, 'recent', t('Недавнее'))
  }
  function playSimilar(i: number) {
    void player.playList(home.similar, i, 'similar', t('Похожее'))
  }
  function openAlbum(a: Album) {
    openRef(a.ref)
  }

  const mode = $derived(WAVE_MODES.find((m) => m.id === wave.mode) ?? WAVE_MODES[0])

  /** Полу-3D переворот подписи режима: новая выезжает снизу, поворачиваясь к нам, старая уходит вверх. */
  function flipIn(_n: Element) {
    if (reducedMotion()) return { duration: 160, css: (t: number) => `opacity:${t}` }
    return {
      duration: 420,
      easing: cubicOut,
      css: (t: number, u: number) => `opacity:${t};transform:rotateX(${-80 * u}deg) translateY(${6 * u}px)`,
    }
  }
  function flipOut(_n: Element) {
    if (reducedMotion()) return { duration: 120, css: (t: number) => `opacity:${t}` }
    return {
      duration: 300,
      easing: cubicIn,
      css: (t: number, u: number) => `opacity:${t};transform:rotateX(${80 * u}deg) translateY(${-6 * u}px)`,
    }
  }
</script>

<!-- Герой как у Dotify: без карточки; слева обложка и «Моя волна» (Roboto Flex), справа — сцена
     с двумя обложками следующих треков и большой кнопкой. -->
<section class="wave" class:on={wave.active}>
  <div class="lead">
    <button class="art" data-fx-cover aria-label={t('Играть волну')} onclick={(e) => playCover(e, waveTracks[0], false)}>
      <Cover url={waveCover} size={158} radius="26px" />
      <!-- загрузка трека волны — на обложке героя, если волна играет -->
      <LoadFx on={wave.active} url={player.current?.cover_url} />
    </button>
    <div class="wave-text">
      <h1 class="font-wave" data-fx-title>{#each t('Моя волна').split(' ') as w, i (i)}<span>{w}</span>{/each}</h1>
      <!-- режим волны: клик — следующий (Своя → Жёсткая → Спокойная → …), карточка переворачивается -->
      <button class="mode" title={t('Режим волны — нажми, чтобы сменить')} onclick={() => wave.nextMode()}>
        {#key mode.id}
          <span class="flip" in:flipIn out:flipOut>
            <Icon name={mode.icon} size={15} />
            <b>{t(mode.title)}</b>{#if wave.loading}<span class="sub">· {t('подбираю…')}</span>{:else if wave.active && wave.seed}<span class="sub">· {t('в стиле «{title}»', { title: wave.seed.title })}</span>{:else}<span class="sub">· {t(mode.sub)}</span>{/if}
          </span>
        {/key}
      </button>
    </div>
  </div>

  <div class="scene" class:still={!player.playing}>
    {#each waveTracks.slice(1, 3) as tr, i (tr.ref)}
      <button
        class="float f{i} idle-pause"
        class:picked={wave.active && wave.seed?.ref === tr.ref}
        aria-label={t('Волна в стиле «{title}»', { title: tr.title })}
        title={t('Волна в стиле: {artist} — {title}', { artist: tr.artist, title: tr.title })}
        onclick={(e) => playCover(e, tr, true)}
      >
        <Cover url={tr.cover_url} size={64} radius="16px" />
      </button>
    {/each}
    <button
      bind:this={playBtn}
      class="wave-play"
      class:busy={wave.loading && !wave.active}
      style:background-color={btnColor ? css(btnColor) : null}
      style:color={ink}
      aria-label={playingWave ? t('Пауза') : t('Включить волну')}
      title={wave.error && !wave.active ? wave.error : playingWave ? t('Пауза') : t('Включить волну')}
      onclick={() => wave.toggle()}
    >
      <PlayPause playing={playingWave} size={38} />
    </button>
  </div>
</section>

<section class="block">
  <h2>{t(hello)}{#if me.name},
      <span class="who">
        {#if me.avatar}<img src={me.avatar} alt="" />{/if}
        {me.name}
      </span>{/if}</h2>
  {#if home.mix.length || home.recent.length}
    <Shelf wheel>
      <!-- первым — подборка под время суток (что слушаешь в эти часы + лайки), за ней «Недавнее»;
           обе — веером из трёх обложек, как у Dotify -->
      {#if home.mix.length}
        {@render fan(home.mix, t(part.mix), t('подборка · {tracks}', { tracks: tracksText(home.mix.length) }), () => playMix(0), titles(home.mix))}
      {/if}
      {#if home.recent.length}
        {@render fan(home.recent, t('Недавнее'), tracksText(home.recent.length), () => playRecent(0), recentTitle)}
      {/if}
      {#each home.mix.length ? home.mix : home.recent as t, i (t.ref)}
        <Tile title={t.title} subtitle={t.artist} image={t.cover_url} source={t.ref} onclick={() => (home.mix.length ? playMix(i) : playRecent(i))} />
      {/each}
    </Shelf>
  {:else if home.loading}
    {@render skeleton()}
  {:else}
    <p class="empty">{t('Послушай что-нибудь — здесь соберётся подборка под утро, день, вечер и ночь.')}</p>
  {/if}
</section>

<section class="block">
  <h2>{week.length || !home.releases.length ? t('Релизы недели') : t('Свежие релизы')}</h2>
  {#if releases.length}
    <Shelf wheel>
      {#each releases as a (a.ref)}
        <Tile title={a.title} subtitle={a.artist} meta={releaseLabel(a.released) ?? (a.year ? String(a.year) : undefined)} image={a.cover_url} icon="disc" source={a.ref} onclick={() => openAlbum(a)} />
      {/each}
    </Shelf>
  {:else if home.releasesLoading}
    {@render skeleton()}
  {:else}
    <p class="empty">{t('Лайкай треки и исполнителей — здесь появятся их новые релизы за неделю.')}</p>
  {/if}
</section>

{#if home.similar.length || home.similarLoading}
  <section class="block">
    <h2>{t('Похожее')}{#if home.similarTo}<small> {t('на «{title}»', { title: home.similarTo.title })}</small>{/if}</h2>
    {#if home.similar.length}
      <Shelf>
        {#each home.similar as t, i (t.ref)}
          <Tile title={t.title} subtitle={t.artist} image={t.cover_url} source={t.ref} onclick={() => playSimilar(i)} />
        {/each}
      </Shelf>
    {:else}
      {@render skeleton()}
    {/if}
  </section>
{/if}

<!-- Что слушают в Sonar: с сервера (API.md §5а). Пока его нет — ряды с заготовкой, без выдумок. -->
<section class="block">
  <h2>{t('Тренды Sonar')}<small>{t('что слушают в приложении')}</small></h2>
  {@render soon('trending', t('Появятся вместе с сервером Sonar: треки, которые чаще всего слушают все.'))}
</section>

<section class="block">
  <h2>{t('Плейлисты пользователей')}<small>{t('по популярности')}</small></h2>
  {@render soon('playlist', t('Плейлисты других пользователей — самые слушаемые и сохраняемые. Ждут сервер.'))}
</section>

<section class="block">
  <div class="head">
    <h2>{t('Чарты Sonar')}</h2>
    <div class="periods" use:indicator={{ key: chartPeriod, kind: 'pill' }}>
      {#each CHART_PERIODS as p (p.id)}
        <button class="period press" class:on={chartPeriod === p.id} onclick={() => (chartPeriod = p.id)}>{t(p.label)}</button>
      {/each}
    </div>
  </div>
  {@render soon('chart', t('Треки, исполнители, альбомы и плейлисты, которые чаще всего слушают в Sonar.'))}
</section>

{#snippet soon(icon: 'trending' | 'playlist' | 'chart', text: string)}
  <div class="soon">
    <span class="soon-ic"><Icon name={icon} size={18} /></span>
    <p>{text}</p>
  </div>
{/snippet}

{#snippet fan(list: Track[], title: string, sub: string, onclick: () => void, hint: string)}
  <button class="stack" title={hint} {onclick}>
    <span class="fan">
      {#each list.slice(0, 3).reverse() as t, i (t.ref)}
        <span class="leaf l{list.slice(0, 3).length - 1 - i}"><Cover url={t.cover_url} size={160} radius="var(--radius-l)" /></span>
      {/each}
    </span>
    <span class="st-title">{title}</span>
    <span class="st-sub">{sub}</span>
  </button>
{/snippet}

{#snippet skeleton()}
  <div class="row" aria-label={t('Загрузка…')}>
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
    position: relative;
    flex-shrink: 0;
    overflow: hidden;
    border-radius: 26px;
    /* обычная тень; «Монолит» — свечение цвета обложки (palette.ts SURFACE_DECOR) */
    box-shadow: var(--cover-glow);
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
    font-size: calc(54px * var(--fs, 1));
    line-height: 0.92;
    letter-spacing: -0.02em;
  }
  .mode {
    display: inline-grid;
    justify-items: start;
    margin-left: -8px;
    padding: 5px 10px;
    border-radius: 10px;
    color: var(--text-2);
    font-size: calc(13px * var(--fs, 1));
    white-space: nowrap;
    perspective: 420px;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .mode:hover {
    background: var(--hover);
    color: var(--text);
  }
  .mode:active .flip {
    scale: 0.96;
  }
  /* старая и новая подпись стоят в одной клетке и переворачиваются вокруг горизонтальной оси */
  .flip {
    grid-area: 1 / 1;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    transform-origin: 50% 50% -10px;
    backface-visibility: hidden;
    transition: scale var(--fast) var(--ease);
  }
  .flip b {
    font-weight: 700;
    color: var(--text);
  }
  .flip .sub {
    color: var(--text-3);
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
  .float:hover,
  .float.picked {
    filter: none;
  }
  /* выбранный стиль — тонкое кольцо цвета темы вокруг обложки */
  .float::after {
    content: '';
    position: absolute;
    inset: -5px;
    border-radius: 21px;
    border: 2px solid var(--accent, var(--text));
    opacity: 0;
    scale: 0.9;
    transition:
      opacity var(--normal) var(--ease),
      scale var(--normal) var(--ease);
    pointer-events: none;
  }
  .float.picked::after {
    opacity: 0.9;
    scale: 1;
  }
  /* верхняя обложка — ниже чёлки с кнопками окна (--notch-h ставит lib/notch на карточку) */
  .float.f0 {
    right: 12px;
    top: calc(var(--notch-h, 0px) + 6px);
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
    font-size: calc(24px * var(--fs, 1));
    font-weight: 800;
    margin-bottom: 14px;
  }
  h2 small {
    font-size: calc(15px * var(--fs, 1));
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
  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    margin-bottom: 14px;
  }
  .head h2 {
    margin-bottom: 0;
  }
  .periods {
    position: relative;
    display: flex;
    gap: 2px;
    padding: 3px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .period {
    position: relative;
    z-index: 1;
    height: 28px;
    padding: 0 14px;
    border-radius: 999px;
    color: var(--text-2);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition: color var(--fast) var(--ease);
  }
  .period:hover,
  .period.on {
    color: var(--text);
  }
  .periods :global(.tab-ind.pill) {
    background: var(--hover);
  }
  .soon {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 16px 18px;
    border-radius: var(--radius-l);
    background: var(--plate);
    border: 1px dashed var(--border);
    color: var(--text-3);
    animation: soon-in var(--normal) var(--ease) both;
  }
  .soon p {
    margin: 0;
  }
  .soon-ic {
    display: grid;
    place-items: center;
    flex: none;
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: var(--hover);
    color: var(--text-2);
  }
  @keyframes soon-in {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
  }
  .st-sub {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-2);
  }
</style>
