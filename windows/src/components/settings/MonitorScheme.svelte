<script lang="ts">
  // Схема мониторов для «Оверлей → Положение на экране»: все мониторы, как они стоят в Windows, в рамке
  // не больше 420×260. На каждом — номер, модель, разрешение и частота; клик выбирает монитор, на нём —
  // точки 3×3 и плашка в масштабе. Плашку можно утащить на другой монитор — отпустили, прилипла к
  // ближайшей клетке. Вся математика — lib/monitor-layout.ts, здесь только рисунок и указатель.
  import type { Snippet } from 'svelte'
  import type { OverlayAnchor } from '../../lib/settings.svelte'
  import { OVERLAY_ANCHORS } from '../../lib/overlay'
  import {
    SCHEME_MAX,
    anchorBox,
    anchorDots,
    dropTarget,
    fitScheme,
    hzLabel,
    marginPx,
    plaqueBox,
    stepAnchor,
    tileAt,
    type MonitorInfo,
    type Point,
    type SchemeTile,
  } from '../../lib/monitor-layout'
  import { cascade } from '../../lib/cascade'
  import { pop } from '../../lib/motion'
  import { t } from '../../lib/i18n.svelte'

  let {
    monitors,
    selectedId,
    anchor,
    layout,
    fullscreen = false,
    opacity = 1,
    plaque,
    big,
    cellName,
    onplace,
  }: {
    monitors: MonitorInfo[]
    /** id монитора, на котором сейчас оверлей (уже с подстановкой основного). */
    selectedId: string
    anchor: OverlayAnchor
    /** Окно оверлея, логические пиксели с масштабом (`overlayLayout`). */
    layout: { width: number; height: number }
    fullscreen?: boolean
    /** Непрозрачность плашки 0…1. */
    opacity?: number
    plaque: Snippet
    /** Карточка полноэкранного режима. */
    big: Snippet
    cellName: (a: OverlayAnchor) => string
    onplace: (m: MonitorInfo, anchor: OverlayAnchor) => void
  } = $props()

  /** Зазор между мониторами на схеме, px с каждой стороны. */
  const GAP = 1.5
  /** Меньше этого — на мониторе только номер, подписи не влезают. */
  const COMPACT = { w: 118, h: 74 }
  /** Точки сетки — на столько px от края рабочей области. */
  const DOT_INSET = 10
  /** Рамка монитора (`.tile` border) — рабочая область внутри неё сдвигается на столько. */
  const BORDER = 1.5

  let boxW = $state(0)
  let el = $state<HTMLDivElement>()

  const scheme = $derived(fitScheme(monitors, { w: Math.min(SCHEME_MAX.w, boxW), h: SCHEME_MAX.h }))
  const selected = $derived(scheme.tiles.find((tile) => tile.m.id === selectedId) ?? scheme.tiles[0] ?? null)
  const sizeFor = (tile: SchemeTile) => plaqueBox(layout, tile.m, scheme.k, tile.work)
  // при смене набора мониторов плитки появляются каскадом заново
  const listKey = $derived(monitors.map((m) => m.id).join('|'))

  // перетаскивание: указатель на схеме и за какую долю плашки схватили
  let drag = $state<{ p: Point; fx: number; fy: number } | null>(null)
  const hover = $derived(drag ? tileAt(scheme, drag.p) : null)
  const hoverSize = $derived(hover ? sizeFor(hover) : null)
  const target = $derived(drag && hoverSize ? dropTarget(scheme, center(drag, hoverSize), () => hoverSize) : null)
  /** На каком мониторе точки: пока тянут — под указателем, иначе — выбранный. */
  const dotsTile = $derived(hover ?? selected)

  const box = $derived.by(() => {
    if (!selected) return null
    if (drag && hover && hoverSize) {
      const c = center(drag, hoverSize)
      return { x: c.x - hoverSize.w / 2, y: c.y - hoverSize.h / 2, ...hoverSize }
    }
    const size = sizeFor(selected)
    return { ...anchorBox(selected.work, size, anchor, marginPx(selected.m, scheme.k)), ...size }
  })

  function center(d: { p: Point; fx: number; fy: number }, size: { w: number; h: number }): Point {
    return { x: d.p.x + (0.5 - d.fx) * size.w, y: d.p.y + (0.5 - d.fy) * size.h }
  }

  function local(e: PointerEvent): Point {
    const r = el!.getBoundingClientRect()
    const clamp = (v: number, max: number) => Math.min(max, Math.max(0, v))
    return { x: clamp(e.clientX - r.left, scheme.width), y: clamp(e.clientY - r.top, scheme.height) }
  }

  function grab(e: PointerEvent) {
    if (!box || e.button !== 0) return
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    const p = local(e)
    drag = { p, fx: (p.x - box.x) / box.w, fy: (p.y - box.y) / box.h }
  }
  function move(e: PointerEvent) {
    if (drag) drag = { ...drag, p: local(e) }
  }
  function drop() {
    const hit = target
    drag = null
    if (hit) onplace(hit.tile.m, hit.anchor)
  }
  function cancel() {
    drag = null
  }

  const ARROWS: Record<string, [-1 | 0 | 1, -1 | 0 | 1]> = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }
  function key(e: KeyboardEvent) {
    const step = ARROWS[e.key]
    if (!step || !selected) return
    e.preventDefault()
    onplace(selected.m, stepAnchor(anchor, step[0], step[1]))
  }

  const title = (m: MonitorInfo) => m.name || t('Монитор {n}', { n: m.number })
  const specs = (m: MonitorInfo) => {
    const hz = hzLabel(m.refresh_hz)
    return hz ? `${m.width}×${m.height} · ${hz} ${t('Гц')}` : `${m.width}×${m.height}`
  }
  const compact = (tile: SchemeTile) => tile.rect.w < COMPACT.w || tile.rect.h < COMPACT.h
</script>

<div class="wrap" bind:clientWidth={boxW}>
  <div
    class="scheme"
    class:dragging={!!drag}
    bind:this={el}
    style:width="{scheme.width}px"
    style:height="{scheme.height}px"
    style:--o={opacity}
  >
    <div class="tiles" use:cascade={listKey}>
      {#each scheme.tiles as tile (tile.m.id)}
        {@const r = tile.rect}
        <button
          class="tile"
          class:on={tile === selected}
          class:target={!!drag && tile === hover}
          class:compact={compact(tile)}
          style:left="{r.x + GAP}px"
          style:top="{r.y + GAP}px"
          style:width="{r.w - 2 * GAP}px"
          style:height="{r.h - 2 * GAP}px"
          aria-pressed={tile === selected}
          aria-label="{title(tile.m)}, {specs(tile.m)}{tile.m.primary ? `, ${t('монитор::Основной')}` : ''}"
          onclick={() => tile !== selected && onplace(tile.m, anchor)}
        >
          <span
            class="work"
            style:left="{tile.work.x - r.x - GAP - BORDER}px"
            style:top="{tile.work.y - r.y - GAP - BORDER}px"
            style:width="{tile.work.w}px"
            style:height="{tile.work.h}px"
          ></span>
          <span class="label">
            <b class="num">{tile.m.number}</b>
            {#if !compact(tile)}
              <span class="name">{title(tile.m)}</span>
              <small class="spec">{specs(tile.m)}</small>
            {/if}
          </span>
          {#if tile.m.primary && !compact(tile)}
            <span class="tag">{t('монитор::Основной')}</span>
          {/if}
        </button>
      {/each}
    </div>

    {#if fullscreen && selected}
      {@const r = selected.rect}
      <span class="full" style:left="{r.x + GAP}px" style:top="{r.y + GAP}px" style:width="{r.w - 2 * GAP}px" style:height="{r.h - 2 * GAP}px">
        {@render big()}
      </span>
    {:else if dotsTile && box}
      {#key dotsTile.m.id}
        <span class="dots">
          {#each Object.entries(anchorDots(dotsTile.work, DOT_INSET)) as [a, p], i (a)}
            {@const cell = a as OverlayAnchor}
            <button
              class="dot"
              class:snap={target?.tile === dotsTile && target.anchor === cell}
              class:here={!drag && dotsTile === selected && cell === anchor}
              style:left="{p.x}px"
              style:top="{p.y}px"
              aria-label={cellName(cell)}
              onclick={() => onplace(dotsTile.m, cell)}
              in:pop={{ duration: 220, y: 0, scale: 0.4, delay: i * 18 }}
            ></button>
          {/each}
        </span>
      {/key}
      <span
        class="plaque"
        class:dragging={!!drag}
        role="slider"
        tabindex="0"
        aria-label={t('Положение на экране')}
        aria-valuetext={cellName(anchor)}
        aria-valuemin={0}
        aria-valuemax={OVERLAY_ANCHORS.length - 1}
        aria-valuenow={OVERLAY_ANCHORS.indexOf(anchor)}
        style:left="{box.x}px"
        style:top="{box.y}px"
        style:width="{box.w}px"
        style:height="{box.h}px"
        onpointerdown={grab}
        onpointermove={move}
        onpointerup={drop}
        onpointercancel={cancel}
        onkeydown={key}
      >
        {@render plaque()}
      </span>
    {/if}
  </div>
</div>

<style>
  .wrap {
    width: 100%;
    min-width: 0;
    padding: 6px 0 14px;
  }
  .scheme {
    position: relative;
    max-width: 100%;
    margin: 0 auto;
    touch-action: none;
    transition:
      width 0.3s var(--ease),
      height 0.3s var(--ease);
  }
  .tiles {
    position: absolute;
    inset: 0;
  }

  /* ——— монитор: рамка = весь экран, светлее внутри = рабочая область, тёмная полоса = панель задач ——— */
  .tile {
    position: absolute;
    display: grid;
    place-items: center;
    padding: 0;
    border-radius: 7px;
    border: 1.5px solid var(--border-strong); /* = BORDER */
    background: color-mix(in srgb, var(--surface-1) 70%, #000);
    color: var(--text-2);
    overflow: hidden;
    cursor: pointer;
    transition:
      left 0.35s var(--ease),
      top 0.35s var(--ease),
      width 0.35s var(--ease),
      height 0.35s var(--ease),
      border-color 0.25s var(--ease),
      color 0.25s var(--ease),
      scale 0.15s var(--ease);
  }
  .tile:hover:not(.on) {
    border-color: color-mix(in srgb, var(--accent) 45%, var(--border-strong));
  }
  .tile:active:not(.on) {
    scale: 0.98;
  }
  .tile.on {
    border-color: var(--accent);
    color: var(--text);
    cursor: default;
  }
  .tile.target:not(.on) {
    border-color: color-mix(in srgb, var(--accent) 70%, transparent);
    border-style: dashed;
  }
  .work {
    position: absolute;
    background:
      radial-gradient(circle at 28% 18%, color-mix(in srgb, var(--accent) 16%, transparent), transparent 62%),
      linear-gradient(135deg, var(--surface-3), var(--surface-2));
    transition:
      left 0.35s var(--ease),
      top 0.35s var(--ease),
      width 0.35s var(--ease),
      height 0.35s var(--ease),
      opacity 0.25s var(--ease);
  }
  .tile:not(.on) .work {
    opacity: 0.75;
  }
  .label {
    position: relative;
    display: grid;
    justify-items: center;
    gap: 1px;
    max-width: 100%;
    padding: 0 8px;
    text-align: center;
    pointer-events: none;
  }
  .num {
    font-size: calc(26px * var(--fs, 1));
    font-weight: 700;
    line-height: 1.1;
    font-variant-numeric: tabular-nums;
    transition: color 0.25s var(--ease);
  }
  .tile.on .num {
    color: var(--accent);
  }
  .compact .num {
    font-size: calc(17px * var(--fs, 1));
  }
  .name {
    max-width: 100%;
    overflow: hidden;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .spec {
    font-size: calc(10.5px * var(--fs, 1));
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }
  .tag {
    position: absolute;
    top: 6px;
    right: 6px;
    padding: 2px 7px;
    border-radius: 999px;
    background: color-mix(in srgb, var(--accent) 22%, transparent);
    color: var(--accent);
    font-size: calc(10px * var(--fs, 1));
    font-weight: 600;
    pointer-events: none;
  }

  /* ——— точки 3×3 и плашка ——— */
  .dots {
    position: absolute;
    inset: 0;
    pointer-events: none;
  }
  .dot {
    position: absolute;
    width: 9px;
    height: 9px;
    margin: -4.5px 0 0 -4.5px;
    padding: 0;
    border-radius: 50%;
    background: var(--text-3);
    opacity: 0.5;
    pointer-events: auto;
    transition:
      opacity 0.2s var(--ease),
      scale 0.25s var(--ease),
      background 0.2s var(--ease);
  }
  .dot:hover,
  .dot:focus-visible {
    opacity: 1;
    scale: 1.45;
  }
  .dot.here {
    opacity: 0;
  }
  .dot.snap {
    opacity: 1;
    scale: 1.6;
    background: var(--accent);
  }
  .scheme.dragging .dot {
    pointer-events: none;
  }
  .plaque {
    position: absolute;
    display: block;
    z-index: 1;
    cursor: grab;
    outline: none;
    transition:
      left 0.4s var(--ease),
      top 0.4s var(--ease),
      width 0.3s var(--ease),
      height 0.3s var(--ease),
      scale 0.2s var(--ease),
      filter 0.2s var(--ease);
  }
  .plaque:focus-visible {
    filter: drop-shadow(0 0 0 var(--accent)) drop-shadow(0 0 3px var(--accent));
  }
  .plaque.dragging {
    cursor: grabbing;
    scale: 1.05;
    filter: drop-shadow(0 6px 14px rgb(0 0 0 / 0.45));
    transition:
      width 0.25s var(--ease),
      height 0.25s var(--ease),
      scale 0.2s var(--ease),
      filter 0.2s var(--ease);
  }
  .full {
    position: absolute;
    display: grid;
    place-items: center;
    border-radius: 7px;
    background: rgb(0 0 0 / calc(var(--o) * 0.45));
    pointer-events: none;
    animation: full-in 0.35s var(--ease);
    transition:
      left 0.35s var(--ease),
      top 0.35s var(--ease),
      width 0.35s var(--ease),
      height 0.35s var(--ease);
  }
  @keyframes full-in {
    from {
      opacity: 0;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .scheme,
    .tile,
    .work,
    .dot,
    .plaque,
    .plaque.dragging,
    .full {
      transition: opacity 0.2s;
    }
    .plaque.dragging,
    .tile:active:not(.on) {
      scale: none;
    }
  }
</style>
