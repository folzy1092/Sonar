<script lang="ts">
  // Фон полноэкранного плеера (как у Dotify): обложка «течёт» в WebGL (player/art-field.ts) только
  // пока трек играет; окно свёрнуто или в фоне при экономии ресурсов — стоит. Нет WebGL — просто
  // размытая обложка без движения.
  import { onMount } from 'svelte'
  import { fade } from 'svelte/transition'
  import { player } from './player.svelte'
  import { lyrics } from '../lyrics/lyrics.svelte'
  import { proxied } from '../theme/theme.svelte'
  import { ArtField } from './art-field'
  import { offline } from '../lib/offline.svelte'

  let canvas: HTMLCanvasElement | undefined = $state()
  let field: ArtField | null = $state(null)
  let failed = $state(false)
  let idle = $state(false)

  const cover = $derived(player.current?.cover_url ?? null)

  onMount(() => {
    if (!canvas) return
    try {
      field = new ArtField(canvas)
    } catch {
      failed = true
      return
    }
    const f = field
    const ro = new ResizeObserver(() => f.resize())
    ro.observe(canvas)
    const lost = (e: Event) => {
      e.preventDefault()
      failed = true
    }
    canvas.addEventListener('webglcontextlost', lost)
    // .idle на <html> ставит экономия ресурсов (App.svelte)
    const mo = new MutationObserver(() => (idle = document.documentElement.classList.contains('idle')))
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] })
    idle = document.documentElement.classList.contains('idle')
    return () => {
      ro.disconnect()
      mo.disconnect()
      canvas?.removeEventListener('webglcontextlost', lost)
      f.dispose()
      field = null
    }
  })

  $effect(() => {
    const f = field
    const url = cover
    if (!f || !url) return
    void proxied(url).then((src) => f.show(src))
  })

  $effect(() => {
    field?.setRunning(player.playing && !idle)
  })

  $effect(() => {
    field?.setFocus(lyrics.shown ? lyrics.line : -1)
  })
</script>

<div class="bg" aria-hidden="true">
  {#if failed}
    {#key cover}
      {#if cover}<img src={offline.src(cover)} alt="" transition:fade={{ duration: 600 }} />{/if}
    {/key}
  {:else}
    <canvas bind:this={canvas}></canvas>
  {/if}
</div>

<style>
  .bg {
    position: absolute;
    inset: 0;
    pointer-events: none;
    overflow: hidden;
    background: #0a0a0a;
  }
  canvas {
    width: 100%;
    height: 100%;
    display: block;
  }
  img {
    position: absolute;
    inset: -10%;
    width: 120%;
    height: 120%;
    object-fit: cover;
    filter: blur(80px) brightness(0.55);
  }
</style>
