<script lang="ts">
  import SidePane from './app/SidePane.svelte'
  import { sidePane } from './app/side-pane.svelte'
  import Rail from './app/Rail.svelte'
  import { t } from './lib/i18n.svelte'
  import WindowControls from './app/WindowControls.svelte'
  import SearchBar from './app/SearchBar.svelte'
  import MiniPlayer from './app/MiniPlayer.svelte'
  import { router, type Page } from './app/router.svelte'
  import Home from './pages/Home.svelte'
  import Library from './pages/Library.svelte'
  import Search from './pages/Search.svelte'
  import Player from './pages/Player.svelte'
  import SettingsPanel from './pages/SettingsPanel.svelte'
  import { settingsPanel } from './pages/settings-section.svelte'
  import PlaylistPage from './pages/PlaylistPage.svelte'
  import SmartPlaylistPage from './pages/SmartPlaylistPage.svelte'
  import SmartEditor from './app/smart/SmartEditor.svelte'
  import { isSmartId } from './lib/smart'
  import ArtistPage from './pages/ArtistPage.svelte'
  import AlbumPage from './pages/AlbumPage.svelte'
  import ProfilePage from './pages/ProfilePage.svelte'
  import ImportPage from './pages/ImportPage.svelte'
  import DupesPage from './pages/DupesPage.svelte'
  import MixPage from './pages/MixPage.svelte'
  import TrackMenu from './app/TrackMenu.svelte'
  import PlaylistMenu from './app/PlaylistMenu.svelte'
  import ConfirmDialog from './app/ConfirmDialog.svelte'
  import QuickOpen from './app/QuickOpen.svelte'
  import RecapViewer from './app/RecapViewer.svelte'
  import Toast from './app/Toast.svelte'
  import Tooltip from './app/Tooltip.svelte'
  import UpdatePopup from './app/UpdatePopup.svelte'
  import CrashNotice from './app/CrashNotice.svelte'
  import { updater } from './lib/updater.svelte'
  import { listen } from '@tauri-apps/api/event'
  import { isTauri } from './lib/tauri'
  import { mini } from './lib/mini.svelte'
  import { startThumbbar } from './lib/thumbbar.svelte'
  import { library } from './lib/library.svelte'
  import { onMount } from 'svelte'
  import { initScRelogin } from './lib/sc-relogin'
  import { player } from './player/player.svelte'
  import FullPlayer from './player/FullPlayer.svelte'
  import BlendDebug from './player/BlendDebug.svelte'
  import { lyrics } from './lyrics/lyrics.svelte'
  import { blendAnalysis } from './player/blend/analyze.svelte'
  import { party } from './player/blend/party.svelte'
  import { blendRatings } from './player/blend/ratings.svelte'
  import { wave } from './player/my-wave.svelte'
  import { autoplay } from './player/autoplay.svelte'
  import { initTrackFx } from './lib/track-fx.svelte'
  import { theme } from './theme/theme.svelte'
  import { settings } from './lib/settings.svelte'
  import { isShutter, openMode } from './lib/settings-open'
  import { hotkeys } from './lib/hotkeys.svelte'
  import { remote } from './lib/remote.svelte'
  import { slide } from './lib/motion'
  import { notch } from './lib/notch'
  import { floating } from './lib/floating'
  import { offline } from './lib/offline.svelte'
  import { downloads } from './lib/downloads.svelte'

  const pages = {
    home: Home,
    library: Library,
    search: Search,
    player: Player,
    playlist: PlaylistPage,
    artist: ArtistPage,
    album: AlbumPage,
    profile: ProfilePage,
    import: ImportPage,
    dupes: DupesPage,
    mix: MixPage,
  }
  /** Строка поиска — только на странице поиска (на главной её нет, решение владельца). */
  const withSearch: Page[] = ['search']
  /** Страницы со своей шапкой в верхней строке (вкладки медиатеки как у Dotify): кнопки окна
   *  висят поверх справа, а страница начинается от самого верха. */
  const ownHeader: Page[] = ['library']
  /** Страницы, где шапка стоит на месте, а прокручивается только список треков (как у Dotify). */
  const fixedPages: Page[] = ['playlist', 'mix']
  /** Строки поиска нет — кнопки окна висят поверх в углу, страница начинается от самого верха. */
  const floatHeader = $derived(ownHeader.includes(router.page) || !withSearch.includes(router.page))

  /** Умный плейлист (`sm_…`) — та же страница «playlist», но своя: треки считают правила. */
  const Current = $derived(router.page === 'playlist' && isSmartId(router.param) ? SmartPlaylistPage : pages[router.page])
  let scroller: HTMLElement | undefined = $state()
  let island: HTMLElement | undefined = $state()

  onMount(() => {
    void settings.load()
    offline.init()
    downloads.init()
    player.init()
    wave.init()
    autoplay.init()
    initTrackFx()
    theme.init()
    lyrics.init()
    blendAnalysis.init()
    party.init()
    blendRatings.init(() => player.blend.done)
    void library.load()
    updater.init()
    hotkeys.init()
    remote.init()
    mini.start()
    // SoundCloud: ключи не починились — плашка «Войди в SoundCloud заново»
    initScRelogin()
    // «Тише во время звонков» (calls.rs): микрофон занят другим приложением — музыка стихает
    if (isTauri) void listen<boolean>('call:active', (e) => player.setCall(e.payload))
    // кнопки в превью на панели задач — когда окно уже показано
    setTimeout(() => void startThumbbar(), 1500)
  })

  /** Боковые кнопки мыши: «назад» (button 3) и «вперёд» (button 4). В полноэкранном
   *  плеере «назад» сворачивает его. mousedown гасим, чтобы WebView не трогал свою историю. */
  function mouseNav(e: MouseEvent) {
    if (e.button !== 3 && e.button !== 4) return
    e.preventDefault()
    if (e.type !== 'mouseup') return
    if (e.button === 3) {
      if (lyrics.fullscreen) lyrics.close()
      else if (settingsPanel.open) settingsPanel.close()
      else router.back()
    } else if (!lyrics.fullscreen && !settingsPanel.open) router.forward()
  }

  // Экономия ресурсов (`system.power_saving`): окно свёрнуто (или в фоне) — фоновые анимации и
  // визуализатор на паузе (класс .idle на <html>).
  let hidden = $state(document.hidden)
  let focused = $state(document.hasFocus())
  $effect(() => {
    const mode = settings.get('system.power_saving')
    const idle = mode === 'minimized' ? hidden : mode === 'background' ? hidden || !focused : false
    document.documentElement.classList.toggle('idle', idle)
  })

  // Панель справа — настройки зеркально: выезжают справа, окно уходит влево с наклоном в другую сторону
  $effect(() => {
    document.documentElement.classList.toggle('side-right', settings.get('tabs.position') === 'right' && !floatTabs)
  })

  // Вкладки: подстройка цвета под страницу и автоскрытие панелей, когда мышь замерла на 3 с
  $effect(() => {
    const root = document.documentElement
    root.classList.toggle('tabs-adapt', settings.get('tabs.adapt'))
    const hide = settings.get('tabs.autohide')
    root.classList.toggle('tabs-autohide', hide)
    if (!hide) return root.classList.remove('ui-still')
    let timer: ReturnType<typeof setTimeout> | undefined
    const wake = () => {
      root.classList.remove('ui-still')
      clearTimeout(timer)
      timer = setTimeout(() => root.classList.add('ui-still'), 3000)
    }
    wake()
    window.addEventListener('mousemove', wake, { passive: true })
    window.addEventListener('keydown', wake)
    return () => {
      clearTimeout(timer)
      window.removeEventListener('mousemove', wake)
      window.removeEventListener('keydown', wake)
      root.classList.remove('ui-still')
    }
  })

  // Строка нижнего плеера живёт, пока он на экране, — и пока доигрывает анимация ухода. Раньше она
  // схлопывалась сразу, и плеер обрывался вместо плавного ухода (жалоба владельца 2026-11-17).
  let slotUp = $state(false)
  // плавающая панель вкладок парит над окном где угодно — сетка окна как без панели
  const floatTabs = $derived(settings.get('tabs.style') === 'floating')
  /** Вкладки сверху или снизу — настройки шторкой, окно стоит на месте (SettingsPanel, lib/settings-open). */
  const shutter = $derived(isShutter(openMode(settings.get('tabs.position'), settings.get('tabs.style'))))
  const away = $derived(settingsPanel.open && !shutter)
  const veiled = $derived(settingsPanel.open && shutter)
  function slotAlive(node: HTMLElement) {
    slotUp = true
    // высота мини-плеера — для «Скрытия элементов»: карточка растягивается ровно на его место
    const root = document.documentElement
    const ro = new ResizeObserver(() => root.style.setProperty('--mini-h', `${node.offsetHeight}px`))
    ro.observe(node)
    return {
      destroy: () => {
        slotUp = false
        ro.disconnect()
      },
    }
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape' && settingsPanel.open && !lyrics.fullscreen) return settingsPanel.close()
    // сочетания из Приложение → Клавиши внутри окна (по всей системе их ставит Rust)
    hotkeys.handleKey(e)
  }

  $effect(() => {
    router.key
    scroller?.scrollTo({ top: 0 })
  })
  /** Правая панель «Очередь / Текст» — только когда есть трек и не открыт большой плеер. */
  const paneOn = $derived(sidePane.open && !!player.current && router.page !== 'player')
</script>

<SettingsPanel />

<div class="stage">
<div class="shell tabs-{floatTabs ? 'left' : settings.get('tabs.position')} tstyle-{settings.get('tabs.style')} mini-{settings.get('mini.position')}" class:away class:solo={!slotUp} inert={away}>
  {#if settings.get('tabs.position') === 'top' && !floatTabs}
    <!-- островок вкладок сверху узкий — окно таскается и за пустое место вокруг него -->
    <div class="top-drag" data-tauri-drag-region></div>
  {/if}
  <Rail />

  <!-- панель сверху — кнопки окна на её правом конце, карточке вырез не нужен -->
  <main class="card" inert={veiled} class:own-head={floatHeader} class:fixed-page={fixedPages.includes(router.page)} use:notch={settings.get('tabs.position') === 'top' && !floatTabs ? undefined : island}>
    {#if floatHeader}<div class="drag-strip" data-tauri-drag-region></div>{/if}
    <header class="top" data-tauri-drag-region>
      {#if withSearch.includes(router.page)}
        <SearchBar />
      {/if}
      <div class="spacer" data-tauri-drag-region></div>
    </header>

    <div class="scroll" class:with-pane={paneOn} bind:this={scroller}>
      {#key router.key}
        <div class="page">
          <Current />
        </div>
      {/key}
    </div>
    {#if paneOn}
      <div class="pane-slot"><SidePane /></div>
    {/if}
  </main>
  <!-- «чёлка» как у Dotify: кнопки окна в своём островке, карточка под ним вырезана (lib/notch) -->
  <div class="island" bind:this={island} data-tauri-drag-region>
    <WindowControls />
  </div>

  <!-- пока ничего не играло — плеера снизу нет, главная на весь экран; появился трек — плеер выезжает -->
  {#if settings.get('mini.style') !== 'off' && player.current && router.page !== 'player'}
    <div class="player-slot" inert={veiled} transition:slide={{ duration: 280 }} use:slotAlive use:floating={settings.get('mini.position') === 'floating'}>
      <MiniPlayer />
    </div>
  {/if}
</div>
{#if away}
  <!-- клик по отъехавшему окну закрывает настройки (у шторки — своя вуаль в SettingsPanel) -->
  <button class="back-to-app" aria-label={t('Закрыть настройки')} onclick={() => settingsPanel.close()}></button>
{/if}
</div>

{#if lyrics.fullscreen}
  <FullPlayer />
{/if}
<svelte:window onmousedown={mouseNav} onmouseup={mouseNav} onkeydown={onKey} onfocus={() => (focused = true)} onblur={() => (focused = false)} />
<svelte:document onvisibilitychange={() => (hidden = document.hidden)} />

<TrackMenu />
<PlaylistMenu />
<ConfirmDialog />
<SmartEditor />
<QuickOpen />
<RecapViewer />
<UpdatePopup />
<CrashNotice />
<Toast />
<BlendDebug />
<Tooltip />

<style>
  /* Открытие настроек (PLATFORMS.md, pc/Screenshot_30..32): окно уезжает вправо на ширину панели
     и поворачивается вглубь на ~15° (левый край дальше), затемняется; панель слева — плоская.
     Панель — почти во всё окно (NEXT_PROMPT «Этап 0» п. 6): от окна остаётся полоска, за неё
     окно и возвращается. Вкладки сверху/снизу — шторка, см. SettingsPanel. */
  :global(:root) {
    --settings-w: clamp(420px, calc(100vw - 180px), 1180px);
    /* окно и панель едут одним движением (пружина Dotify: damping 28, stiffness 240) */
    --settings-t: 0.52s;
    --settings-ease: cubic-bezier(0.2, 0.9, 0.25, 1);
  }
  .stage {
    position: relative;
    /* выше панели настроек (z 30): закрыто — окно её прячет, открыто — уезжает и показывает */
    z-index: 31;
    height: 100vh;
    perspective: 1800px;
    perspective-origin: 30% 50%;
    overflow: hidden;
    /* сама сцена прозрачна для мыши — иначе перекроет панель, клики ловят окно и «назад» */
    pointer-events: none;
  }
  .shell,
  .back-to-app {
    pointer-events: auto;
  }
  .shell {
    position: relative;
    z-index: 31;
    background: var(--bg);
    transform-origin: left center;
    transition:
      transform var(--settings-t) var(--settings-ease),
      filter var(--settings-t) var(--settings-ease),
      border-radius var(--settings-t) var(--settings-ease),
      box-shadow var(--settings-t) var(--settings-ease);
  }
  .shell.away {
    transform: translateX(calc(var(--settings-w) + 24px)) rotateY(-15deg) scale(0.9);
    /* за панелью настроек окно чуть матовеет — как стекло в душе: темнее и самую малость размыто */
    filter: brightness(0.42) blur(1.6px) saturate(0.85);
    border-radius: 18px;
    box-shadow: -30px 0 80px rgba(0, 0, 0, 0.6);
  }
  .back-to-app {
    position: absolute;
    inset: 0 0 0 var(--settings-w);
    z-index: 32;
    cursor: pointer;
  }
  /* панель вкладок справа — всё зеркально: окно уезжает влево, правый край уходит вглубь */
  :global(:root.side-right) .stage {
    perspective-origin: 70% 50%;
  }
  :global(:root.side-right) .shell {
    transform-origin: right center;
  }
  :global(:root.side-right) .shell.away {
    transform: translateX(calc(-1 * (var(--settings-w) + 24px))) rotateY(15deg) scale(0.9);
    box-shadow: 30px 0 80px rgba(0, 0, 0, 0.6);
  }
  :global(:root.side-right) .back-to-app {
    inset: 0 var(--settings-w) 0 0;
  }
  @media (prefers-reduced-motion: reduce) {
    .shell {
      transition: filter 0.2s linear;
    }
  }
  .shell {
    display: grid;
    grid-template-columns: var(--rail-w) minmax(0, 1fr);
    grid-template-rows: minmax(0, 1fr) auto;
    height: 100vh;
    padding: 0 var(--gap) var(--gap) 0;
    gap: var(--gap);
  }
  :global(.rail) {
    grid-row: 1 / span 2;
  }
  .card {
    display: flex;
    flex-direction: column;
    min-height: 0;
    margin-top: var(--gap);
    border-radius: var(--radius-xl);
    /* тема под обложку: сверху — оттенок обложки, ниже — обычная поверхность */
    background: linear-gradient(180deg, color-mix(in srgb, var(--tint) 70%, var(--surface-0)) 0, var(--surface-0) 420px);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    overflow: hidden;
  }
  .top {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 50px;
    padding: 8px 6px 2px 28px;
  }
  .spacer {
    flex: 1;
    align-self: stretch;
  }
  .card {
    position: relative;
  }
  /* островок — в вырезе карточки: 4 px вокруг кнопок, фон окна (Dotify: top/right +4 к карточке) */
  .island {
    position: absolute;
    top: var(--gap);
    right: var(--gap);
    z-index: 4;
    padding: 4px;
  }
  /* полоса прокрутки не уходит под чёлку */
  .scroll::-webkit-scrollbar-track {
    margin-top: var(--notch-h, 0px);
  }
  .own-head .top {
    position: absolute;
    top: 0;
    right: 0;
    z-index: 3;
    min-height: 0;
    padding: 6px 6px 0 0;
  }
  /* тонкая полоса сверху — за неё окно по-прежнему можно тащить */
  .drag-strip {
    position: absolute;
    inset: 0 0 auto 0;
    height: 12px;
    z-index: 2;
  }
  .own-head .top .spacer {
    display: none;
  }
  .own-head .page {
    padding-top: 14px;
  }
  .fixed-page .scroll {
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .fixed-page .page {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    padding-bottom: 0;
  }
  .scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overflow-x: hidden;
    transition: margin-right var(--normal) var(--ease);
  }
  /* правая панель «Очередь / Текст»: страница ужимается, панель лежит справа внутри карточки */
  .scroll.with-pane {
    margin-right: calc(var(--pane-w) + 8px);
  }
  .card {
    --pane-w: min(400px, 44%);
  }
  .pane-slot {
    position: absolute;
    top: calc(var(--notch-h, 44px) + 8px);
    right: 8px;
    bottom: 8px;
    z-index: 3;
    display: flex;
    flex-direction: column;
    width: var(--pane-w);
  }
  .pane-slot > :global(.pane) {
    flex: 1;
  }
  .page {
    position: relative;
    z-index: 0;
    padding: 12px 28px 32px;
    animation: page-in var(--normal) var(--ease);
  }
  @keyframes page-in {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
  }
  /* нижний плеер — над карточкой страницы: его всплывашки (эквалайзер, скорость) выше всего */
  .player-slot {
    position: relative;
    z-index: 6;
  }
  /* без плеера снизу — карточка занимает всю высоту */
  .shell.solo {
    grid-template-rows: minmax(0, 1fr) 0;
    row-gap: 0;
  }
  /* отступ над плеером тает вместе с ним, а не прыгает */
  .shell {
    transition-property: transform, filter, border-radius, box-shadow, row-gap;
    transition-duration: var(--settings-t), var(--settings-t), var(--settings-t), var(--settings-t), 0.28s;
  }
  @media (prefers-reduced-motion: reduce) {
    .shell {
      transition-property: filter;
      transition-duration: 0.2s;
    }
  }

  /* ---- позиция мини-плеера (Плеер → Мини плеер, mini.position) ---- */
  /* сверху: плеер над карточкой, кнопки окна остаются справа — плеер им уступает место */
  .shell.mini-top {
    grid-template-rows: auto minmax(0, 1fr);
  }
  .shell.mini-top.solo {
    grid-template-rows: 0 minmax(0, 1fr);
  }
  .mini-top .player-slot {
    grid-row: 1;
    margin-top: var(--gap);
    margin-right: 150px;
  }
  .mini-top .card {
    grid-row: 2;
    margin-top: 0;
  }
  .shell.tabs-top.mini-top {
    grid-template-rows: var(--rail-w) auto minmax(0, 1fr);
  }
  .tabs-top.mini-top .player-slot {
    grid-row: 2;
    margin-right: 0;
  }
  .tabs-top.mini-top .card {
    grid-row: 3;
  }
  .shell.tabs-bottom.mini-top {
    grid-template-rows: auto minmax(0, 1fr) var(--rail-w);
  }
  .tabs-bottom.mini-top .card {
    grid-row: 2;
  }
  /* плавающий: карточка на всю высоту, плеер парит над её низом */
  .shell.mini-floating {
    grid-template-rows: minmax(0, 1fr) 0;
    row-gap: 0;
  }
  .shell.tabs-top.mini-floating {
    grid-template-rows: var(--rail-w) minmax(0, 1fr) 0;
  }
  .shell.tabs-bottom.mini-floating {
    grid-template-rows: minmax(0, 1fr) 0 var(--rail-w);
  }
  /* под парящим плеером страница не прячет низ */
  .mini-floating .page {
    padding-bottom: calc(var(--player-h) + 48px);
  }
  /* снизу во всю ширину: боковая панель кончается над плеером, плеер — от края до края окна */
  .shell.mini-bottom_full:not(.tabs-top, .tabs-bottom) :global(.rail) {
    grid-row: 1;
  }
  .shell.mini-bottom_full:not(.tabs-top, .tabs-bottom) .player-slot {
    grid-column: 1 / -1;
    margin-left: var(--gap);
  }
  .shell.tabs-right.mini-bottom_full .player-slot {
    margin: 0 var(--gap) 0 0;
  }
  .mini-floating .player-slot {
    position: fixed;
    z-index: 20;
    width: min(760px, calc(100vw - 120px));
    cursor: grab;
    filter: drop-shadow(0 18px 36px oklch(0 0 0 / 0.5));
  }
  .mini-floating .player-slot:global(.dragging) {
    cursor: grabbing;
  }

  /* плавающая панель вкладок (tabs.style = floating) — вне сетки, колонка под неё нулевая */
  .shell.tstyle-floating {
    grid-template-columns: 0 minmax(0, 1fr);
  }
  .tstyle-floating .card,
  .tstyle-floating .player-slot {
    grid-column: 2;
  }

  /* ---- позиция вкладок (Интерфейс → Вкладки, tabs.position) ---- */
  /* справа: зеркально — карточка и плеер слева, панель справа на всю высоту */
  .shell.tabs-right {
    grid-template-columns: minmax(0, 1fr) var(--rail-w);
    padding: 0 0 var(--gap) var(--gap);
  }
  .tabs-right :global(.rail) {
    grid-column: 2;
    grid-row: 1 / span 2;
  }
  .tabs-right .card,
  .tabs-right .player-slot {
    grid-column: 1;
    grid-row: auto;
  }
  .tabs-right .card {
    grid-row: 1;
  }
  .tabs-right .player-slot {
    grid-row: 2;
  }
  .tabs-right .island {
    right: calc(var(--rail-w) + var(--gap));
  }
  /* сверху / снизу: панель — горизонтальная полоса во всю ширину */
  .shell.tabs-top,
  .shell.tabs-bottom {
    grid-template-columns: minmax(0, 1fr);
    padding: 0 var(--gap) var(--gap);
  }
  .shell.tabs-top {
    grid-template-rows: var(--rail-w) minmax(0, 1fr) auto;
  }
  .shell.tabs-top.solo {
    grid-template-rows: var(--rail-w) minmax(0, 1fr) 0;
  }
  .tabs-top :global(.rail) {
    grid-row: 1;
    grid-column: 1;
  }
  .top-drag {
    grid-row: 1;
    grid-column: 1;
    margin-top: var(--gap);
  }
  .tabs-top .card {
    grid-row: 2;
    grid-column: 1;
  }
  .tabs-top .player-slot {
    grid-row: 3;
  }
  .tabs-top .island {
    top: calc(var(--gap) + (var(--rail-w) - var(--gap) - 40px) / 2);
    right: calc(var(--gap) + 8px);
  }
  .shell.tabs-bottom {
    grid-template-rows: minmax(0, 1fr) auto var(--rail-w);
  }
  .shell.tabs-bottom.solo {
    grid-template-rows: minmax(0, 1fr) 0 var(--rail-w);
  }
  .tabs-bottom :global(.rail) {
    grid-row: 3;
    grid-column: 1;
  }
  .tabs-bottom .card {
    grid-row: 1;
    grid-column: 1;
  }
  .tabs-bottom .player-slot {
    grid-row: 2;
  }
  /* Скрытие элементов (tabs.autohide): мышь замерла — панель и мини-плеер гаснут, а карточка страницы
     плавно занимает их место, чтобы не оставалось пустых полей (владелец 2026-11-22). Отрицательные
     поля, а не сетка: длины анимируются, а «auto» у строки мини-плеера — нет. Плавающие панель и
     мини-плеер места в сетке не занимают — для них ничего не надо. */
  .card {
    transition:
      margin 0.45s var(--ease),
      border-radius 0.45s var(--ease);
  }
  /* панель (не плавающая): слева / справа — по ширине панели (она прижата к краю окна, зазор остаётся) */
  :global(:root.tabs-autohide.ui-still) .shell.tabs-left:not(.tstyle-floating) .card {
    margin-left: calc(-1 * var(--rail-w));
  }
  :global(:root.tabs-autohide.ui-still) .shell.tabs-right:not(.tstyle-floating) .card {
    margin-right: calc(-1 * var(--rail-w));
  }
  /* сверху: полоса вкладок (и мини-плеер под ней, если он сверху); обычный отступ сверху — var(--gap) */
  :global(:root.tabs-autohide.ui-still) .shell.tabs-top:not(.tstyle-floating) .card {
    margin-top: calc(var(--gap) - var(--rail-w));
  }
  /* с мини-плеером в сетке между полосой и карточкой ещё зазор строк */
  :global(:root.tabs-autohide.ui-still) .shell.tabs-top:not(.tstyle-floating, .solo) .card {
    margin-top: calc(-1 * var(--rail-w));
  }
  :global(:root.tabs-autohide.ui-still) .shell:not(.tabs-top, .solo).mini-top .card,
  :global(:root.tabs-autohide.ui-still) .shell.tabs-top.tstyle-floating:not(.solo).mini-top .card {
    margin-top: calc(-1 * var(--mini-h, 0px));
  }
  :global(:root.tabs-autohide.ui-still) .shell.tabs-top:not(.tstyle-floating, .solo).mini-top .card {
    margin-top: calc(-1 * (var(--rail-w) + var(--mini-h, 0px) + var(--gap)));
  }
  /* снизу: мини-плеер, полоса вкладок или оба — каждый со своим зазором */
  :global(:root.tabs-autohide.ui-still) .shell:not(.solo):is(.mini-bottom, .mini-bottom_full) .card {
    margin-bottom: calc(-1 * (var(--mini-h, 0px) + var(--gap)));
  }
  :global(:root.tabs-autohide.ui-still) .shell.tabs-bottom:not(.tstyle-floating) .card {
    margin-bottom: calc(-1 * (var(--rail-w) + var(--gap)));
  }
  :global(:root.tabs-autohide.ui-still) .shell.tabs-bottom.solo:not(.tstyle-floating) .card {
    margin-bottom: calc(-1 * var(--rail-w));
  }
  :global(:root.tabs-autohide.ui-still) .shell.tabs-bottom:not(.tstyle-floating, .solo):is(.mini-bottom, .mini-bottom_full) .card {
    margin-bottom: calc(-1 * (var(--rail-w) + var(--mini-h, 0px) + 2 * var(--gap)));
  }
  /* карточка поверх погасших панели и мини-плеера */
  :global(:root.tabs-autohide.ui-still) .card {
    z-index: 1;
  }
  @media (prefers-reduced-motion: reduce) {
    .card {
      transition: none;
    }
  }
</style>
