<script lang="ts">
  // Карта исполнителей (Медиатека → Исполнители → Карта). Холст 2D в devicePixelRatio: соты кучек,
  // связи, перетаскивание, колесо к курсору, поиск с перелётом, карточка по клику. Рисуем только
  // когда что-то поменялось и карта видна; «меньше движения» — камера переставляется сразу.
  import { onMount, untrack } from 'svelte'
  import Icon from '../../components/Icon.svelte'
  import EmptyState from '../../components/EmptyState.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { easeOutQuint, pop, reducedMotion, rise, xfade } from '../../lib/motion'
  import { rawError } from '../../lib/api'
  import { mapApi, onMapEvents, type FollowProgress, type MapGraph } from '../../lib/artist-map/api'
  import { findNode, hitTest, layout } from '../../lib/artist-map/layout'
  import { FOCUS_ZOOM, between, fit, panBy, toWorld, wheelFactor, zoomAt, type Camera, type Viewport } from '../../lib/artist-map/camera'
  import { artistsCount, clusterTitle, whyText } from '../../lib/artist-map/why'
  import { clusterHeads, connections, discoveredCount, focusSet } from '../../lib/artist-map/graph'
  import { AvatarCache } from '../../lib/artist-map/avatars'
  import { CLUSTER_LABEL_MIN, drawMap, readPalette, type DrawNode, type Palette } from '../../lib/artist-map/render'
  import { FADE_MS, MORPH_MS, frameNodes, positionsOf, progress, type Positions } from '../../lib/artist-map/scene'
  import MapCard from './MapCard.svelte'

  /** Длительность перелёта камеры. */
  const FLY_MS = 650
  /** Сдвиг меньше — это клик, а не перетаскивание. */
  const CLICK_SLOP = 4
  /** Шаг кнопок «Приблизить» / «Отдалить». */
  const ZOOM_STEP = 1.45
  /** Цвета темы перечитываем не чаще. */
  const PALETTE_MS = 1000
  /** Карточка справа закрывает часть карты — выбранного ставим левее центра. */
  const CARD_SHIFT = 160
  const WIDE = 640
  /** Связей в подсказке при наведении. */
  const TIP_LINKS = 3

  let graph = $state.raw<MapGraph | null>(null)
  let status = $state<'loading' | 'ready' | 'error'>('loading')
  let errorMsg = $state('')
  let follow = $state<FollowProgress | null>(null)
  let selected = $state<string | null>(null)
  let tip = $state<{ key: string; x: number; y: number } | null>(null)
  let query = $state('')
  let notFound = $state(false)
  let dragging = $state(false)

  let wrap: HTMLDivElement | undefined = $state()
  let canvas: HTMLCanvasElement | undefined = $state()

  const lay = $derived(layout(graph?.nodes ?? [], graph?.edges ?? []))
  const nodesByKey = $derived(new Map((graph?.nodes ?? []).map((n) => [n.key, n])))
  const labels = $derived(
    graph
      ? clusterHeads(lay, nodesByKey, graph.edges, CLUSTER_LABEL_MIN).map((h) => ({ x: h.x, y: h.y, r: h.r, title: clusterTitle(h.top.name) }))
      : [],
  )
  const libraryCount = $derived(discoveredCount(graph))
  const selectedNode = $derived(selected ? nodesByKey.get(selected) : undefined)
  // ключ отдельно: подсказка двигается за мышью, а связи пересчитываются только при смене круга
  const tipKey = $derived(tip?.key ?? null)
  const tipNode = $derived(tipKey ? nodesByKey.get(tipKey) : undefined)
  const tipLinks = $derived(graph && tipKey ? connections(graph, tipKey, TIP_LINKS) : [])
  const followText = $derived.by(() => {
    if (follow?.state === 'running' && follow.total > 0) {
      return t('Подтягиваю подписки SoundCloud: {done} из {total}', { done: follow.done, total: follow.total })
    }
    if (follow?.state === 'paused') return t('SoundCloud попросил паузу — продолжу позже')
    return ''
  })

  // ── Рисование: всё ниже — обычные переменные, не реактивные (60 кадров без лишней работы) ──
  let ctx: CanvasRenderingContext2D | null = null
  let vp: Viewport = { w: 0, h: 0 }
  let dpr = 1
  let cam: Camera = { x: 0, y: 0, zoom: 1 }
  let fitted = false
  let visible = false
  let raf = 0
  let prev: Positions = new Map()
  let morphStarted = 0
  let flight: { from: Camera; to: Camera; started: number } | null = null
  let drawn: DrawNode[] = []
  let palette: Palette | null = null
  let paletteAt = 0
  let focusCache: { key: string; set: Set<string> } | null = null
  const avatars = new AvatarCache(() => schedule())

  function schedule() {
    if (!raf && visible && ctx) raf = requestAnimationFrame(tick)
  }

  function focusOf(key: string | null): Set<string> | null {
    if (!key || !graph) return null
    if (focusCache?.key !== key) focusCache = { key, set: focusSet(graph.edges, key) }
    return focusCache.set
  }

  function tick(now: number) {
    raf = 0
    if (!ctx || !graph || !wrap || vp.w === 0) return
    let animating = false
    if (flight) {
      const k = progress(flight.started, now, FLY_MS)
      cam = between(flight.from, flight.to, easeOutQuint(k))
      if (k < 1) animating = true
      else flight = null
    }
    const move = progress(morphStarted, now, reducedMotion() ? 0 : MORPH_MS)
    const fade = progress(morphStarted, now, FADE_MS)
    if (move < 1 || fade < 1) animating = true
    drawn = frameNodes(lay, nodesByKey, prev, easeOutQuint(move), fade)
    if (!palette || now - paletteAt > PALETTE_MS) {
      palette = readPalette(wrap)
      paletteAt = now
    }
    const hovered = tip?.key ?? null
    const focusKey = hovered ?? selected
    drawMap({
      ctx,
      vp,
      dpr,
      cam,
      nodes: drawn,
      byKey: new Map(drawn.map((n) => [n.key, n])),
      edges: graph.edges,
      clusters: labels,
      focusKey,
      focus: focusOf(focusKey),
      hovered,
      selected,
      palette,
      avatars,
      fade,
    })
    if (animating) schedule()
  }

  function setGraph(next: MapGraph) {
    prev = graph ? positionsOf(drawn) : new Map()
    focusCache = null
    graph = next
    morphStarted = performance.now()
    if (selected && !next.nodes.some((n) => n.key === selected)) selected = null
    if (!fitted && vp.w > 0) fitAll()
    schedule()
  }

  function fitAll() {
    cam = fit(lay.bounds, vp)
    fitted = true
  }

  async function load() {
    try {
      const next = await mapApi.graph()
      setGraph(next)
      status = 'ready'
    } catch (e) {
      if (!graph) {
        errorMsg = rawError(e)
        status = 'error'
      }
    }
  }

  function retry() {
    status = 'loading'
    void load()
  }

  // ── Камера ──
  function flyTo(target: Camera) {
    if (reducedMotion()) {
      flight = null
      cam = target
    } else {
      flight = { from: cam, to: target, started: performance.now() }
    }
    schedule()
  }

  function focusOn(key: string) {
    const p = lay.byKey.get(key)
    if (!p) return
    const zoom = Math.max(cam.zoom, FOCUS_ZOOM)
    const shift = vp.w >= WIDE ? CARD_SHIFT / zoom : 0
    selected = key
    tip = null
    flyTo({ x: p.x + shift, y: p.y, zoom })
  }

  function zoomBy(factor: number) {
    flyTo(zoomAt(cam, vp, { x: vp.w / 2, y: vp.h / 2 }, factor))
  }

  function select(key: string | null) {
    selected = key
    schedule()
  }

  // ── Мышь ──
  let drag: { id: number; startX: number; startY: number; lastX: number; lastY: number; moved: boolean } | null = null

  function local(e: PointerEvent | WheelEvent) {
    const r = canvas!.getBoundingClientRect()
    return { x: e.clientX - r.left, y: e.clientY - r.top }
  }

  function onDown(e: PointerEvent) {
    if (e.button !== 0) return
    canvas?.setPointerCapture(e.pointerId)
    drag = { id: e.pointerId, startX: e.clientX, startY: e.clientY, lastX: e.clientX, lastY: e.clientY, moved: false }
    flight = null
  }

  function onMove(e: PointerEvent) {
    if (drag && drag.id === e.pointerId) {
      if (!drag.moved && Math.hypot(e.clientX - drag.startX, e.clientY - drag.startY) > CLICK_SLOP) {
        drag.moved = true
        dragging = true
        tip = null
      }
      if (drag.moved) {
        cam = panBy(cam, e.clientX - drag.lastX, e.clientY - drag.lastY)
        drag.lastX = e.clientX
        drag.lastY = e.clientY
        schedule()
        return
      }
    }
    hover(local(e))
  }

  function onUp(e: PointerEvent) {
    if (!drag || drag.id !== e.pointerId) return
    const click = !drag.moved
    drag = null
    dragging = false
    if (click) {
      const hit = hitTest(lay.nodes, toWorld(cam, vp, local(e)))
      select(hit && hit.key !== selected ? hit.key : null)
    }
  }

  function hover(p: { x: number; y: number }) {
    const hit = hitTest(lay.nodes, toWorld(cam, vp, p))
    const key = hit?.key ?? null
    if (key === (tip?.key ?? null)) {
      if (tip) tip = { ...tip, x: p.x, y: p.y }
      return
    }
    tip = key ? { key, x: p.x, y: p.y } : null
    schedule()
  }

  function onLeave() {
    if (drag) return
    tip = null
    schedule()
  }

  function onWheel(e: WheelEvent) {
    e.preventDefault()
    flight = null
    cam = zoomAt(cam, vp, local(e), wheelFactor(e.deltaY))
    schedule()
  }

  function search(e: SubmitEvent) {
    e.preventDefault()
    const n = graph ? findNode(graph.nodes, query) : undefined
    notFound = !n && query.trim() !== ''
    if (n) focusOn(n.key)
  }

  // ── Холст: размер, видимость, тема ──
  function resize() {
    if (!wrap || !canvas) return
    const r = canvas.getBoundingClientRect()
    vp = { w: r.width, h: r.height }
    dpr = window.devicePixelRatio || 1
    canvas.width = Math.round(r.width * dpr)
    canvas.height = Math.round(r.height * dpr)
    if (!fitted && graph && vp.w > 0) fitAll()
    schedule()
  }

  function updateVisible(onScreen: boolean) {
    visible = onScreen && !document.hidden
    schedule()
  }

  $effect(() => {
    if (!canvas) return
    ctx = canvas.getContext('2d')
    const el = canvas
    el.addEventListener('wheel', onWheel, { passive: false })
    const ro = new ResizeObserver(resize)
    ro.observe(el)
    let inView = false
    const io = new IntersectionObserver(([entry]) => {
      inView = entry.isIntersecting
      updateVisible(inView)
    })
    io.observe(el)
    const onVis = () => updateVisible(inView)
    document.addEventListener('visibilitychange', onVis)
    // тема поменялась — перечитать цвета и перерисовать, даже если карта стоит
    const mo = new MutationObserver(() => {
      palette = null
      schedule()
    })
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ['class', 'style', 'data-theme'] })
    untrack(resize)
    return () => {
      el.removeEventListener('wheel', onWheel)
      ro.disconnect()
      io.disconnect()
      mo.disconnect()
      document.removeEventListener('visibilitychange', onVis)
      if (raf) cancelAnimationFrame(raf)
      raf = 0
      ctx = null
    }
  })

  onMount(() => {
    void load()
    void mapApi.refresh().catch(() => {})
    let off: (() => void) | null = null
    let alive = true
    void onMapEvents({
      progress: (p) => (follow = p),
      updated: () => void load(),
    }).then((f) => (alive ? (off = f) : f()))
    return () => {
      alive = false
      off?.()
      avatars.clear()
    }
  })
</script>

<section class="map-view" in:rise={{ y: 8 }}>
  {#if status === 'error'}
    <div class="state" in:xfade>
      <p>{errorMsg}</p>
      <button class="retry" onclick={retry}>{t('Повторить')}</button>
    </div>
  {:else if status === 'ready' && libraryCount === 0}
    <div in:xfade>
      <EmptyState icon="user" title={t('Карта пока пустая')} text={t('Перенеси лайки или плейлисты из сервисов — здесь появится твоя карта')} />
    </div>
  {:else}
    <div class="bar">
      <form class="find" class:miss={notFound} onsubmit={search}>
        <Icon name="search" size={15} />
        <input
          type="search"
          placeholder={t('Найти на карте')}
          aria-label={t('Найти на карте')}
          bind:value={query}
          oninput={() => (notFound = false)}
        />
      </form>
      {#if notFound}<span class="note" transition:xfade>{t('Ничего не нашлось')}</span>{/if}
      <span class="spacer"></span>
      {#if followText}<span class="note" transition:xfade>{followText}</span>{/if}
      {#if status === 'ready'}<span class="count">{artistsCount(libraryCount)}</span>{/if}
    </div>

    <div class="stage" bind:this={wrap}>
      <canvas
        bind:this={canvas}
        class:over={!!tip}
        class:dragging
        aria-label={t('Карта исполнителей')}
        onpointerdown={onDown}
        onpointermove={onMove}
        onpointerup={onUp}
        onpointercancel={onUp}
        onpointerleave={onLeave}
      ></canvas>

      {#if status === 'loading'}
        <p class="loading" transition:xfade>{t('Собираю карту…')}</p>
      {/if}

      {#if tip && tipNode && tip.key !== selected}
        <div class="tip" style:left="{tip.x}px" style:top="{tip.y}px" in:pop={{ duration: 140, y: 4 }}>
          <strong>{tipNode.name}</strong>
          {#if tipLinks.length}
            {#each tipLinks as link (link.node.key)}
              <span>{whyText(link.edge.reasons, link.node.name)}</span>
            {/each}
          {:else}
            <span>{t('Пока без связей')}</span>
          {/if}
        </div>
      {/if}

      <div class="zoom">
        <button aria-label={t('Приблизить')} title={t('Приблизить')} onclick={() => zoomBy(ZOOM_STEP)}><Icon name="plus" size={16} /></button>
        <button aria-label={t('Отдалить')} title={t('Отдалить')} onclick={() => zoomBy(1 / ZOOM_STEP)}><Icon name="minus" size={16} /></button>
        <button aria-label={t('Показать всё')} title={t('Показать всё')} onclick={() => flyTo(fit(lay.bounds, vp))}><Icon name="maximize" size={15} /></button>
      </div>

      {#if selectedNode && graph}
        {#key selectedNode.key}
          <MapCard node={selectedNode} {graph} layout={lay} nodes={nodesByKey} onclose={() => select(null)} onfly={focusOn} />
        {/key}
      {/if}
    </div>

    <p class="caption">{t('Карта лучше всего строится по SoundCloud; для Яндекс Музыки и Spotify связей меньше — карта по ним слабее')}</p>
  {/if}
</section>

<style>
  .map-view {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 34px;
  }
  .spacer {
    flex: 1;
  }
  .find {
    display: flex;
    align-items: center;
    gap: 8px;
    width: min(280px, 50%);
    height: 34px;
    padding: 0 12px;
    border-radius: 999px;
    background: var(--surface-2);
    border: 1px solid transparent;
    color: var(--text-3);
    transition: border-color var(--fast) var(--ease), background var(--fast) var(--ease);
  }
  .find:focus-within {
    border-color: var(--border-strong);
    background: var(--surface-3);
  }
  .find.miss {
    border-color: var(--danger);
  }
  .find input {
    flex: 1;
    min-width: 0;
    border: 0;
    outline: 0;
    background: none;
    color: var(--text);
    font-size: 13px;
  }
  .note,
  .count {
    font-size: 12px;
    color: var(--text-3);
    white-space: nowrap;
  }
  .count {
    font-variant-numeric: tabular-nums;
  }
  .stage {
    position: relative;
    height: clamp(420px, calc(100vh - 240px), 1200px);
    border-radius: var(--radius-l);
    overflow: hidden;
    background: var(--surface-0);
    border: 1px solid var(--card-line);
  }
  canvas {
    display: block;
    width: 100%;
    height: 100%;
    cursor: grab;
    touch-action: none;
  }
  canvas.over {
    cursor: pointer;
  }
  canvas.dragging {
    cursor: grabbing;
  }
  .loading {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    margin: 0;
    font-size: 13px;
    color: var(--text-3);
    pointer-events: none;
  }
  .tip {
    position: absolute;
    transform: translate(14px, 14px);
    max-width: 280px;
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 8px 10px;
    border-radius: var(--radius-m);
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: 0 10px 26px rgb(0 0 0 / 0.25);
    backdrop-filter: blur(16px);
    pointer-events: none;
    z-index: 2;
  }
  .tip strong {
    font-size: 13px;
  }
  .tip span {
    font-size: 11.5px;
    line-height: 1.35;
    color: var(--text-3);
  }
  .zoom {
    position: absolute;
    left: 14px;
    bottom: 14px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 3px;
    border-radius: var(--radius-m);
    background: var(--plate);
    border: 1px solid var(--card-line);
    backdrop-filter: blur(16px);
  }
  .zoom button {
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    border-radius: var(--radius-s);
    color: var(--text-2);
    transition: background var(--fast) var(--ease), color var(--fast) var(--ease), transform var(--fast) var(--ease);
  }
  .zoom button:hover {
    background: var(--hover);
    color: var(--text);
  }
  .zoom button:active {
    transform: scale(0.92);
  }
  .caption {
    margin: 0;
    font-size: 12px;
    color: var(--text-3);
  }
  .state {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    padding: 56px 24px;
    color: var(--text-3);
    text-align: center;
  }
  .state p {
    margin: 0;
  }
  .retry {
    height: 32px;
    padding: 0 14px;
    border-radius: 999px;
    background: var(--surface-3);
    color: var(--text);
    font-weight: 600;
    transition: background var(--fast) var(--ease);
  }
  .retry:hover {
    background: var(--hover);
  }
</style>
