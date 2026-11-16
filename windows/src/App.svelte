<script lang="ts">
  import Rail from './app/Rail.svelte'
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
  import ArtistPage from './pages/ArtistPage.svelte'
  import AlbumPage from './pages/AlbumPage.svelte'
  import TrackMenu from './app/TrackMenu.svelte'
  import Toast from './app/Toast.svelte'
  import UpdatePopup from './app/UpdatePopup.svelte'
  import CrashNotice from './app/CrashNotice.svelte'
  import { updater } from './lib/updater.svelte'
  import { library } from './lib/library.svelte'
  import { onMount } from 'svelte'
  import { player } from './player/player.svelte'
  import FullPlayer from './player/FullPlayer.svelte'
  import { lyrics } from './lyrics/lyrics.svelte'
  import { wave } from './player/my-wave.svelte'
  import { autoplay } from './player/autoplay.svelte'
  import { theme } from './theme/theme.svelte'
  import { settings } from './lib/settings.svelte'
  import { slide } from 'svelte/transition'
  import { notch } from './lib/notch'

  const pages = {
    home: Home,
    library: Library,
    search: Search,
    player: Player,
    playlist: PlaylistPage,
    artist: ArtistPage,
    album: AlbumPage,
  }
  /** Строка поиска — только на странице поиска (на главной её нет, решение владельца). */
  const withSearch: Page[] = ['search']
  /** Страницы со своей шапкой в верхней строке (вкладки медиатеки как у Dotify): кнопки окна
   *  висят поверх справа, а страница начинается от самого верха. */
  const ownHeader: Page[] = ['library']
  /** Страницы, где шапка стоит на месте, а прокручивается только список треков (как у Dotify). */
  const fixedPages: Page[] = ['playlist']
  /** Строки поиска нет — кнопки окна висят поверх в углу, страница начинается от самого верха. */
  const floatHeader = $derived(ownHeader.includes(router.page) || !withSearch.includes(router.page))

  const Current = $derived(pages[router.page])
  let scroller: HTMLElement | undefined = $state()
  let island: HTMLElement | undefined = $state()

  onMount(() => {
    void settings.load()
    player.init()
    wave.init()
    autoplay.init()
    theme.init()
    lyrics.init()
    void library.load()
    updater.init()
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

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape' && settingsPanel.open && !lyrics.fullscreen) settingsPanel.close()
  }

  $effect(() => {
    router.key
    scroller?.scrollTo({ top: 0 })
  })
</script>

<SettingsPanel />

<div class="stage">
<div class="shell" class:away={settingsPanel.open} class:solo={settings.get('mini.style') === 'off' || !player.current || router.page === 'player'} inert={settingsPanel.open}>
  <Rail />

  <main class="card" class:own-head={floatHeader} class:fixed-page={fixedPages.includes(router.page)} use:notch={island}>
    {#if floatHeader}<div class="drag-strip" data-tauri-drag-region></div>{/if}
    <header class="top" data-tauri-drag-region>
      {#if withSearch.includes(router.page)}
        <SearchBar />
      {/if}
      <div class="spacer" data-tauri-drag-region></div>
    </header>

    <div class="scroll" bind:this={scroller}>
      {#key router.key}
        <div class="page">
          <Current />
        </div>
      {/key}
    </div>
  </main>
  <!-- «чёлка» как у Dotify: кнопки окна в своём островке, карточка под ним вырезана (lib/notch) -->
  <div class="island" bind:this={island} data-tauri-drag-region>
    <WindowControls />
  </div>

  <!-- пока ничего не играло — плеера снизу нет, главная на весь экран; появился трек — плеер выезжает -->
  {#if settings.get('mini.style') !== 'off' && player.current && router.page !== 'player'}
    <div class="player-slot" transition:slide={{ duration: 280 }}>
      <MiniPlayer />
    </div>
  {/if}
</div>
{#if settingsPanel.open}
  <!-- клик по отъехавшему окну закрывает настройки -->
  <button class="back-to-app" aria-label="Закрыть настройки" onclick={() => settingsPanel.close()}></button>
{/if}
</div>

{#if lyrics.fullscreen}
  <FullPlayer />
{/if}
<svelte:window onmousedown={mouseNav} onmouseup={mouseNav} onkeydown={onKey} onfocus={() => (focused = true)} onblur={() => (focused = false)} />
<svelte:document onvisibilitychange={() => (hidden = document.hidden)} />

<TrackMenu />
<UpdatePopup />
<CrashNotice />
<Toast />

<style>
  /* Открытие настроек (PLATFORMS.md, pc/Screenshot_30..32): окно уезжает вправо на ширину панели
     и поворачивается вглубь на ~15° (левый край дальше), затемняется; панель слева — плоская. */
  :global(:root) {
    --settings-w: 440px;
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
    filter: brightness(0.42);
    border-radius: 18px;
    box-shadow: -30px 0 80px rgba(0, 0, 0, 0.6);
  }
  .back-to-app {
    position: absolute;
    inset: 0 0 0 var(--settings-w);
    z-index: 32;
    cursor: pointer;
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
    border: 1px solid var(--border);
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
  /* без плеера снизу — карточка занимает всю высоту */
  .shell.solo {
    grid-template-rows: minmax(0, 1fr) 0;
    row-gap: 0;
  }
</style>
