<script lang="ts">
  // Главная по reference/pc/Screenshot_20, 23: Sonar Mix (обложка, заголовок, источник, плавающие
  // обложки следующих треков, большая кнопка); ниже по порядку — «Для тебя» (карточки подборок →
  // MixPage), «Релизы недели» тех, на кого стоят лайки, «Похоже на» трёх последних исполнителей;
  // потом тренды, плейлисты пользователей и чарты Sonar (с сервера, до него — заготовка).
  import { untrack } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import Tile from '../components/Tile.svelte'
  import Shelf from '../components/Shelf.svelte'
  import MixCard from '../components/MixCard.svelte'
  import RecapInvite from '../components/RecapInvite.svelte'
  import PlayPause from '../components/PlayPause.svelte'
  import type { Album } from '../lib/api'
  import { openRef, router } from '../app/router.svelte'
  import type { IconName } from '../components/icons'
  import type { MixId } from '../lib/home-mixes'
  import { mixes } from './mixes.svelte'
  import { player } from '../player/player.svelte'
  import { settings } from '../lib/settings.svelte'
  import { WAVE_MODES } from '../player/my-wave.svelte'
  import { reducedMotion } from '../lib/motion'
  import { cubicOut } from 'svelte/easing'
  import { wave } from '../player/my-wave.svelte'
  import { DAYPART_TEXT, daypart, home, releaseLabel, weekReleases } from './home-data.svelte'
  import { indicator } from '../lib/indicator'
  import { cascade } from '../lib/cascade'
  import { t } from '../lib/i18n.svelte'
  import SonarField from '../components/SonarField.svelte'
  import { heroPhrase } from '../lib/hero-phrases'
  import { offline } from '../lib/offline.svelte'
  import OfflineHome from './OfflineHome.svelte'

  const partId = daypart(new Date().getHours())
  const part = DAYPART_TEXT[partId]
  const phrase = heroPhrase(partId)
  let moodsOpen = $state(false)

  /** Клик мимо всплывашки настроений — закрыть (открывается и закрывается только кликом). */
  function outside(node: HTMLElement, close: () => void) {
    const onDown = (e: MouseEvent) => {
      const target = e.target as Node
      if (!node.contains(target) && !(target instanceof Element && target.closest('.moods-btn'))) close()
    }
    window.addEventListener('mousedown', onDown, true)
    return { destroy: () => window.removeEventListener('mousedown', onDown, true) }
  }

  function pop(_n: Element) {
    if (reducedMotion()) return { duration: 140, css: (t: number) => `opacity:${t}` }
    return { duration: 200, easing: cubicOut, css: (t: number, u: number) => `opacity:${t};transform:translateY(${-6 * u}px) scale(${0.97 + 0.03 * t})` }
  }
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

  /** Значок пустой мозаики подборки. */
  const MIX_ICON: Record<MixId, IconName> = { daypart: 'clock', recent: 'history', new: 'disc', fresh: 'trending', like: 'music' }
  // какие подборки показывать: пустые сетевые — пока грузятся, «Похоже на трек» — всегда, когда есть история
  const forYou = $derived(
    (['daypart', 'recent', 'new', 'fresh', 'like'] as const).filter((id) =>
      id === 'like' ? !!(mixes.seed || home.recent.length) : mixes.tracks(id).length > 0 || mixes.isLoading(id),
    ),
  )

  // в офлайне сеть не трогаем; режим выключили, пока Главная открыта, — догружаем
  // зависим только от офлайна: load() и ensureCovers() читают своё состояние (loading, covers), и без
  // untrack неудачная загрузка (нет сервисов, нет сети) перезапускала эффект по кругу — главный поток вставал
  $effect(() => {
    if (offline.on) return
    untrack(() => {
      void home.load().then(() => mixes.load())
      wave.ensureCovers()
    })
  })

  const playingWave = $derived(wave.active && player.playing)

  function playSimilar(i: number) {
    void player.playList(home.similar, i, 'similar', t('Похоже на'))
  }
  function openAlbum(a: Album) {
    openRef(a.ref)
  }

  const mode = $derived(WAVE_MODES.find((m) => m.id === wave.mode) ?? WAVE_MODES[0])

</script>

{#if offline.on}
  <OfflineHome />
{:else}
<!-- Герой (решение владельца 2026-11-18): приветствие с аватаром, крупная фраза под время суток с
     акцентным словом, «Слушать» и настроение волны; справа — живое поле точек (слизь ⇄ знак Sonar). -->
<section class="hero" class:on={wave.active}>
  <div class="hero-text">
    <div class="hi">
      {#if me.avatar}<img src={offline.src(me.avatar)} alt="" />{/if}
      <span>{me.name ? t('{hello}, {name}', { hello: t(hello), name: me.name }) : t(hello)}</span>
    </div>
    <h1 class="font-wave" data-fx-title>{t(phrase[0])} <em>{t(phrase[1])}</em></h1>
    <span class="kind">
      {t('Sonar Mix')} · {t(mode.title)}{#if wave.loading} · {t('подбираю…')}{:else if wave.active && wave.seed} · {t('в стиле «{title}»', { title: wave.seed.title })}{/if}
    </span>
    <div class="actions">
      <button
        class="listen press"
        class:busy={wave.loading && !wave.active}
        title={wave.error && !wave.active ? wave.error : undefined}
        onclick={() => wave.toggle()}
      >
        <PlayPause playing={playingWave} size={18} />
        {playingWave ? t('Пауза') : t('Слушать')}
      </button>
      <button
        class="moods-btn press"
        class:on={moodsOpen}
        aria-label={t('Настроение Sonar Mix')}
        title={t('Настроение Sonar Mix')}
        aria-expanded={moodsOpen}
        onclick={() => (moodsOpen = !moodsOpen)}
      >
        <Icon name="adjustments" size={18} />
      </button>
      {#if moodsOpen}
        <div class="moods" role="dialog" aria-label={t('Настроение Sonar Mix')} use:outside={() => (moodsOpen = false)} transition:pop>
          <b>{t('Какое настроение?')}</b>
          <div class="chips">
            {#each WAVE_MODES as m (m.id)}
              <button class="chip press" class:on={wave.mode === m.id} title={t(m.sub)} onclick={() => void wave.setMode(m.id, wave.active)}>
                <Icon name={m.icon} size={15} />{t(m.title)}
              </button>
            {/each}
          </div>
        </div>
      {/if}
    </div>
  </div>
  <div class="hero-field"><SonarField playing={playingWave} /></div>
</section>

<RecapInvite />

<!-- «Для тебя»: подборки-карточки; клик открывает страницу подборки (MixPage), а не очередь -->
<section class="block">
  <h2>{t('Для тебя')}</h2>
  {#if forYou.length}
    <Shelf wheel key={forYou.length}>
      {#each forYou as id (id)}
        <MixCard
          title={mixes.title(id)}
          tracks={mixes.tracks(id)}
          loading={mixes.isLoading(id)}
          hint={id === 'like' ? t('Выбери трек — соберу похожее') : t('Пока пусто — слушай и лайкай')}
          icon={MIX_ICON[id]}
          onclick={() => router.go('mix', id)}
        />
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

<!-- «Похоже на» трёх последних исполнителей: аватар и имя открывают исполнителя -->
{#if home.similar.length || home.similarLoading}
  <section class="block">
    <div class="like-head">
      <h2>{t('Похоже на')}</h2>
      {#if home.similarArtists.length}
        <div class="seeds" use:cascade={home.similarArtists.map((a) => a.name).join('|')}>
          {#each home.similarArtists as a (a.name)}
            <button class="seed press" disabled={!a.ref} title={a.ref ? t('Открыть исполнителя') : a.name} onclick={() => openRef(a.ref)}>
              {#if a.avatar_url}<img src={offline.src(a.avatar_url)} alt="" />{:else}<span class="seed-ph">{a.name.slice(0, 1).toUpperCase()}</span>{/if}
              <span class="seed-name">{a.name}</span>
            </button>
          {/each}
        </div>
      {/if}
    </div>
    {#if home.similar.length}
      <Shelf key={home.similar.length}>
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
{/if}

{#snippet soon(icon: 'trending' | 'playlist' | 'chart', text: string)}
  <div class="soon">
    <span class="soon-ic"><Icon name={icon} size={18} /></span>
    <p>{text}</p>
  </div>
{/snippet}

{#snippet skeleton()}
  <div class="row" aria-label={t('Загрузка…')}>
    {#each { length: 7 } as _, i (i)}
      <div class="sk-tile"><div class="sk-cover skel"></div><div class="sk-line skel"></div><div class="sk-line short skel"></div></div>
    {/each}
  </div>
{/snippet}

<style>
  .hero {
    position: relative;
    display: grid;
    grid-template-columns: minmax(0, 1.2fr) minmax(0, 1fr);
    align-items: center;
    gap: 16px;
    min-height: 300px;
    padding: 8px 0 0;
  }
  .hero-text {
    position: relative;
    z-index: 1;
    /* герой не вылезает из своей колонки: размер заголовка ограничен её шириной (--hero-fit),
       самое длинное слово фраз (~10 букв широким шрифтом, ~9em) влезает при 11cqi */
    container-type: inline-size;
    --hero-fit: 11cqi;
    min-width: 0;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 10px;
  }
  .hi {
    display: flex;
    align-items: center;
    gap: 8px;
    color: var(--text-2);
    font-weight: 600;
    animation: rise-in var(--normal) var(--ease) both;
  }
  .hi img {
    width: 26px;
    height: 26px;
    border-radius: 50%;
    object-fit: cover;
  }
  .hero h1 {
    margin: 0;
    max-width: min(12ch, 100%);
    font-size: min(clamp(40px, 5.6vw, 76px), var(--hero-fit));
    overflow-wrap: break-word;
    line-height: 0.98;
    letter-spacing: -0.02em;
    animation: rise-in calc(var(--normal) * 1.6) var(--ease) both;
  }
  .hero h1 em {
    font-style: normal;
    color: color-mix(in srgb, var(--accent) 75%, var(--text));
    transition: color 0.6s var(--ease);
  }
  .kind {
    color: var(--text-3);
    font-size: calc(13px * var(--fs, 1));
  }
  @keyframes rise-in {
    from {
      opacity: 0;
      transform: translateY(8px);
    }
  }
  .actions {
    position: relative;
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 12px;
  }
  .listen {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 46px;
    padding: 0 22px 0 18px;
    border-radius: 999px;
    background: var(--text);
    color: var(--surface-0);
    font-weight: 700;
    transition:
      transform var(--fast) var(--ease),
      filter var(--fast) var(--ease),
      opacity var(--normal) var(--ease);
  }
  .listen:hover {
    filter: brightness(0.92);
  }
  .listen:active {
    transform: scale(0.96);
  }
  .listen.busy {
    opacity: 0.5;
    pointer-events: none;
  }
  .moods-btn {
    display: grid;
    place-items: center;
    width: 46px;
    height: 46px;
    border-radius: 50%;
    background: var(--plate);
    border: 1px solid var(--card-line);
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .moods-btn:hover,
  .moods-btn.on {
    background: var(--hover);
    color: var(--text);
  }
  .moods {
    position: absolute;
    top: calc(100% + 10px);
    left: 0;
    z-index: 5;
    display: flex;
    flex-direction: column;
    gap: 10px;
    width: min(380px, 80vw);
    padding: 14px;
    border-radius: 18px;
    background: var(--surface-1, var(--surface-0));
    border: 1px solid var(--card-line);
    box-shadow: 0 18px 50px rgba(0, 0, 0, 0.45);
  }
  .moods b {
    font-size: calc(13px * var(--fs, 1));
  }
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 32px;
    padding: 0 12px;
    border-radius: 999px;
    background: var(--plate);
    color: var(--text-2);
    font-size: calc(13px * var(--fs, 1));
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .chip:hover {
    background: var(--hover);
    color: var(--text);
  }
  .chip.on {
    background: var(--text);
    color: var(--surface-0);
    font-weight: 600;
  }
  .hero-field {
    position: relative;
    height: 300px;
    opacity: 0.9;
  }
  @media (max-width: 760px) {
    .hero {
      grid-template-columns: 1fr;
    }
    .hero-field {
      position: absolute;
      inset: 0 0 auto 40%;
      opacity: 0.35;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .hi,
    .hero h1 {
      animation: none;
    }
  }
  .block {
    margin-top: var(--section-gap);
  }
  h2 {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: calc(var(--fs-h2) * var(--fs, 1));
    font-weight: 800;
    margin-bottom: var(--head-gap);
  }
  h2 small {
    font-size: calc(15px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .row {
    display: flex;
    gap: var(--sp-4);
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
    gap: var(--sp-2);
    width: var(--card-w);
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
  /* «Похоже на»: чипы исполнителей — своей строкой под заголовком, а не впритык к нему */
  .like-head {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--sp-3);
    margin-bottom: var(--head-gap);
  }
  .like-head h2 {
    margin-bottom: 0;
  }
  .seeds {
    display: flex;
    flex-wrap: wrap;
    gap: var(--sp-2);
  }
  .seed {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    max-width: 220px;
    height: 34px;
    padding: 0 12px 0 4px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    color: var(--text-2);
    font-weight: 600;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .seed:not(:disabled):hover {
    background: var(--hover);
    color: var(--text);
  }
  .seed:not(:disabled):active {
    transform: scale(0.96);
  }
  .seed:disabled {
    cursor: default;
  }
  .seed img,
  .seed-ph {
    flex: none;
    width: 26px;
    height: 26px;
    border-radius: 50%;
    object-fit: cover;
  }
  .seed-ph {
    display: grid;
    place-items: center;
    background: var(--hover);
    color: var(--text-2);
    font-size: calc(12px * var(--fs, 1));
  }
  .seed-name {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--sp-4);
    margin-bottom: var(--head-gap);
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
</style>
