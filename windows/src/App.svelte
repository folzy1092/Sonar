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
  import Settings from './pages/Settings.svelte'
  import { onMount } from 'svelte'
  import { player } from './player/player.svelte'

  const pages = { home: Home, library: Library, search: Search, player: Player, settings: Settings }
  const withSearch: Page[] = ['home', 'search']

  const Current = $derived(pages[router.page])
  let scroller: HTMLElement | undefined = $state()

  onMount(() => player.init())

  $effect(() => {
    router.page
    scroller?.scrollTo({ top: 0 })
  })
</script>

<div class="shell">
  <Rail />

  <main class="card">
    <header class="top" data-tauri-drag-region>
      {#if withSearch.includes(router.page)}
        <SearchBar />
      {/if}
      <div class="spacer" data-tauri-drag-region></div>
      <WindowControls />
    </header>

    <div class="scroll" bind:this={scroller}>
      {#key router.page}
        <div class="page">
          <Current />
        </div>
      {/key}
    </div>
  </main>

  <div class="player-slot">
    <MiniPlayer />
  </div>
</div>

<style>
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
    background: var(--surface-0);
    border: 1px solid var(--border);
    overflow: hidden;
  }
  .top {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 56px;
    padding: 10px 10px 4px 28px;
  }
  .spacer {
    flex: 1;
    align-self: stretch;
  }
  .scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overflow-x: hidden;
  }
  .page {
    padding: 12px 28px 32px;
    animation: page-in var(--normal) var(--ease);
  }
  @keyframes page-in {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
  }
</style>
