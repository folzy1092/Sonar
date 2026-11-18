// Рисование карты на canvas 2D. Всё в экранных координатах (масштаб камеры считаем сами), холст
// в devicePixelRatio. Рисуем только видимое: круги и рёбра за краем пропускаются, подписи — когда
// круг достаточно крупный. Цвета — из CSS-переменных темы (readPalette).
import type { AvatarCache } from './avatars'
import { onScreen, toScreen, type Camera, type Viewport } from './camera'
import type { Point } from './layout'

export interface Palette {
  accent: string
  text: string
  muted: string
  plate: string
  surface: string
  font: string
}

export interface DrawNode {
  key: string
  name: string
  x: number
  y: number
  r: number
  discovered: boolean
  avatar: string | null
  /** Появление 0..1 (новые круги проявляются). */
  shown: number
}

export interface DrawEdge {
  a: string
  b: string
  weight: number
}

export interface ClusterLabel extends Point {
  r: number
  title: string
}

export interface Frame {
  ctx: CanvasRenderingContext2D
  vp: Viewport
  dpr: number
  cam: Camera
  nodes: readonly DrawNode[]
  byKey: ReadonlyMap<string, DrawNode>
  edges: readonly DrawEdge[]
  clusters: readonly ClusterLabel[]
  /** Подсвеченный исполнитель (под курсором или выбранный) и его соседи. */
  focusKey: string | null
  focus: ReadonlySet<string> | null
  hovered: string | null
  selected: string | null
  palette: Palette
  avatars: AvatarCache
  /** Проявление рёбер 0..1 (после загрузки и перестройки). */
  fade: number
}

/** Круг на экране меньше — без подписи. */
const LABEL_MIN_R = 22
/** Масштаб, ниже которого вместо подписей кругов — названия кучек. */
const CLUSTER_LABEL_ZOOM = 0.55
/** Кучки меньше — без названия. */
export const CLUSTER_LABEL_MIN = 3
/** Бледность соседей снаружи медиатеки и всего, что вне подсветки. */
const OUTSIDE_ALPHA = 0.42
const DIMMED_ALPHA = 0.22
const LABEL_FONT = 12
const LABEL_PAD = 6
/** Рёбра делим на три пачки по силе — три stroke вместо сотен. */
const EDGE_TIERS = [
  { min: 3, width: 1.8, alpha: 0.34 },
  { min: 1.2, width: 1.2, alpha: 0.22 },
  { min: 0, width: 0.8, alpha: 0.13 },
] as const

/** Пачка ребра по силе связи (индекс в EDGE_TIERS). */
export function edgeTier(weight: number): number {
  return EDGE_TIERS.findIndex((t) => weight >= t.min)
}

export function readPalette(el: Element): Palette {
  const cs = getComputedStyle(el)
  const v = (name: string, fallback: string) => cs.getPropertyValue(name).trim() || fallback
  return {
    accent: v('--accent', '#8b9cff'),
    text: v('--text', '#f2f2f2'),
    muted: v('--text-3', '#8a8a8a'),
    plate: v('--surface-2', '#1d1d1f'),
    surface: v('--surface-3', '#2a2a2d'),
    font: cs.fontFamily || 'sans-serif',
  }
}

export function drawMap(f: Frame) {
  const { ctx, vp, dpr } = f
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  ctx.clearRect(0, 0, vp.w, vp.h)
  if (f.cam.zoom < CLUSTER_LABEL_ZOOM) drawClusterLabels(f)
  drawEdges(f)
  const visible = f.nodes.filter((n) => onScreen(f.cam, vp, n, n.r))
  for (const n of visible) drawNode(f, n)
  if (f.cam.zoom >= CLUSTER_LABEL_ZOOM) for (const n of visible) drawInnerLabel(f, n)
  for (const key of [f.selected, f.hovered]) {
    const n = key ? f.byKey.get(key) : undefined
    if (n) drawOuterLabel(f, n)
  }
  ctx.globalAlpha = 1
}

function nodeAlpha(f: Frame, n: DrawNode): number {
  const outside = n.discovered ? 1 : OUTSIDE_ALPHA
  const dimmed = f.focus && !f.focus.has(n.key) ? DIMMED_ALPHA : 1
  return outside * dimmed * n.shown
}

function drawEdges(f: Frame) {
  const { ctx, cam, vp } = f
  const tiers = EDGE_TIERS.map(() => new Path2D())
  const lit = new Path2D()
  let anyLit = false
  for (const e of f.edges) {
    const a = f.byKey.get(e.a)
    const b = f.byKey.get(e.b)
    if (!a || !b || !segmentVisible(cam, vp, a, b)) continue
    const sa = toScreen(cam, vp, a)
    const sb = toScreen(cam, vp, b)
    const touches = f.focusKey !== null && (e.a === f.focusKey || e.b === f.focusKey)
    const path = touches ? lit : tiers[edgeTier(e.weight)]
    if (touches) anyLit = true
    path.moveTo(sa.x, sa.y)
    path.lineTo(sb.x, sb.y)
  }
  ctx.lineCap = 'round'
  ctx.strokeStyle = f.palette.text
  EDGE_TIERS.forEach((t, i) => {
    ctx.globalAlpha = t.alpha * (f.focus ? 0.35 : 1) * f.fade
    ctx.lineWidth = t.width
    ctx.stroke(tiers[i])
  })
  if (anyLit) {
    ctx.globalAlpha = 0.85
    ctx.strokeStyle = f.palette.accent
    ctx.lineWidth = 2
    ctx.stroke(lit)
  }
}

/** Отрезок хотя бы рамкой задевает экран. */
function segmentVisible(cam: Camera, vp: Viewport, a: Point, b: Point): boolean {
  const sa = toScreen(cam, vp, a)
  const sb = toScreen(cam, vp, b)
  return Math.max(sa.x, sb.x) >= 0 && Math.min(sa.x, sb.x) <= vp.w && Math.max(sa.y, sb.y) >= 0 && Math.min(sa.y, sb.y) <= vp.h
}

function drawNode(f: Frame, n: DrawNode) {
  const { ctx } = f
  const s = toScreen(f.cam, f.vp, n)
  const r = n.r * f.cam.zoom
  if (r < 0.6) return
  ctx.globalAlpha = nodeAlpha(f, n)
  const img = r >= 5 ? f.avatars.get(n.avatar) : null
  if (img) {
    ctx.drawImage(img, s.x - r, s.y - r, r * 2, r * 2)
  } else {
    ctx.beginPath()
    ctx.arc(s.x, s.y, r, 0, Math.PI * 2)
    ctx.fillStyle = f.palette.surface
    ctx.fill()
    if (r >= 9) {
      ctx.fillStyle = f.palette.muted
      ctx.font = `700 ${Math.round(r * 0.8)}px ${f.palette.font}`
      ctx.textAlign = 'center'
      ctx.textBaseline = 'middle'
      ctx.fillText(initial(n.name), s.x, s.y + r * 0.04)
    }
  }
  ring(f, n, s, r)
}

function ring(f: Frame, n: DrawNode, s: Point, r: number) {
  const { ctx } = f
  const selected = n.key === f.selected
  const hovered = n.key === f.hovered
  if (!selected && !hovered && n.discovered) return
  ctx.beginPath()
  ctx.arc(s.x, s.y, r + (selected ? 3 : 1.5), 0, Math.PI * 2)
  if (selected) {
    ctx.globalAlpha = 1
    ctx.strokeStyle = f.palette.accent
    ctx.lineWidth = 2.5
  } else if (hovered) {
    ctx.globalAlpha = 0.9
    ctx.strokeStyle = f.palette.text
    ctx.lineWidth = 1.5
  } else {
    ctx.strokeStyle = f.palette.muted
    ctx.lineWidth = 1
    ctx.setLineDash([3, 3])
  }
  ctx.stroke()
  ctx.setLineDash([])
}

function initial(name: string): string {
  return (Array.from(name.trim())[0] ?? '?').toUpperCase()
}

/** Подпись внутри крупного круга — плашкой по нижнему краю. */
function drawInnerLabel(f: Frame, n: DrawNode) {
  const r = n.r * f.cam.zoom
  if (r < LABEL_MIN_R || n.key === f.hovered || n.key === f.selected) return
  const s = toScreen(f.cam, f.vp, n)
  pill(f, n.name, s.x, s.y + r * 0.62, r * 1.7, nodeAlpha(f, n))
}

/** Подпись под кругом для наведённого и выбранного — всегда целиком видна. */
function drawOuterLabel(f: Frame, n: DrawNode) {
  const s = toScreen(f.cam, f.vp, n)
  const r = n.r * f.cam.zoom
  pill(f, n.name, s.x, s.y + r + LABEL_FONT + 4, 260, 1)
}

function pill(f: Frame, text: string, cx: number, cy: number, maxW: number, alpha: number) {
  const { ctx } = f
  ctx.font = `600 ${LABEL_FONT}px ${f.palette.font}`
  const label = ellipsize(ctx, text, maxW - LABEL_PAD * 2)
  if (!label) return
  const w = ctx.measureText(label).width + LABEL_PAD * 2
  const h = LABEL_FONT + 8
  ctx.globalAlpha = alpha * 0.9
  ctx.fillStyle = f.palette.plate
  ctx.beginPath()
  ctx.roundRect(cx - w / 2, cy - h / 2, w, h, h / 2)
  ctx.fill()
  ctx.globalAlpha = alpha
  ctx.fillStyle = f.palette.text
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  ctx.fillText(label, cx, cy + 0.5)
}

/** Текст, обрезанный многоточием до ширины; слишком узко — пусто. */
function ellipsize(ctx: CanvasRenderingContext2D, text: string, maxW: number): string {
  if (maxW < LABEL_FONT * 1.5) return ''
  if (ctx.measureText(text).width <= maxW) return text
  const chars = Array.from(text)
  let lo = 0
  let hi = chars.length
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2)
    if (ctx.measureText(chars.slice(0, mid).join('') + '…').width <= maxW) lo = mid
    else hi = mid - 1
  }
  return lo ? chars.slice(0, lo).join('') + '…' : ''
}

/** Издалека — названия кучек над ними. */
function drawClusterLabels(f: Frame) {
  const { ctx } = f
  ctx.font = `700 13px ${f.palette.font}`
  ctx.textAlign = 'center'
  ctx.textBaseline = 'bottom'
  for (const c of f.clusters) {
    if (!onScreen(f.cam, f.vp, c, c.r)) continue
    const s = toScreen(f.cam, f.vp, { x: c.x, y: c.y - c.r })
    ctx.globalAlpha = f.focus ? 0.35 : 0.8
    ctx.fillStyle = f.palette.muted
    ctx.fillText(c.title, s.x, s.y - 6)
  }
}
