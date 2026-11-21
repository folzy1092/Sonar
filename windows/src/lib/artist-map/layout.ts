// Раскладка карты исполнителей — чистые функции, без случайности: один и тот же граф всегда
// ложится одинаково. Кучки — распространение меток в постоянном порядке; внутри кучки круги
// встают сотами (каждый касается уже стоящего, ближе к своим связям, без наложений); потом так же
// раскладываются сами кучки. Размер круга — вес исполнителя.
import type { MapEdge, MapNode } from './api'

/** Радиусы кругов в единицах мира (при масштабе 1 — CSS-пиксели). */
export const R_MIN = 14
export const R_MAX = 46
/** Зазор между кругами и между кучками. */
const GAP = 6
const CLUSTER_GAP = 110
/** Поле вокруг кучки, куда не встают одиночки без связей. */
const LOOSE_MARGIN = 40
const LABEL_ROUNDS = 25
/** Касательные места вокруг соседа: 12 направлений — соты при равных кругах. */
const ANGLES = 12
/** Сколько ближайших к цели кругов перебираем как опору. */
const NEAREST = 24
/** Тяга к центру: держит кучку круглой, а не вытянутой. */
const CENTER_PULL = 0.3
const EPS = 1e-9

export interface Point {
  x: number
  y: number
}
export interface Disc extends Point {
  r: number
}
export interface Placed extends Disc {
  key: string
  cluster: number
}
export interface ClusterBox extends Disc {
  id: number
  /** Ключи кучки, тяжёлые первыми. */
  keys: string[]
}
export interface Bounds {
  minX: number
  minY: number
  maxX: number
  maxY: number
}
export interface Layout {
  nodes: Placed[]
  byKey: Map<string, Placed>
  clusters: ClusterBox[]
  bounds: Bounds
}

export type Adjacency = Map<string, Map<string, number>>

const byWeight = (a: MapNode, b: MapNode) => b.weight - a.weight || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0)

/** Радиус по весу: площадь круга растёт с весом, а не радиус — так крупные не давят остальных. */
export function radius(weight: number, maxWeight: number): number {
  if (!(maxWeight > 0)) return R_MIN
  const k = Math.min(1, Math.sqrt(Math.max(0, weight) / maxWeight))
  return R_MIN + (R_MAX - R_MIN) * k
}

const cmp = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0)

/** Соседи каждого узла с весом связи (только между известными узлами). Рёбра сначала
 *  сортируются: порядок обхода и сложения не зависит от порядка входа — раскладка повторяется. */
export function adjacency(edges: readonly MapEdge[], known?: ReadonlySet<string>): Adjacency {
  const adj: Adjacency = new Map()
  const add = (a: string, b: string, w: number) => {
    const m = adj.get(a) ?? new Map<string, number>()
    m.set(b, (m.get(b) ?? 0) + w)
    adj.set(a, m)
  }
  const sorted = [...edges].sort((x, y) => cmp(x.a, y.a) || cmp(x.b, y.b) || x.weight - y.weight)
  for (const e of sorted) {
    if (e.a === e.b || (known && (!known.has(e.a) || !known.has(e.b)))) continue
    add(e.a, e.b, e.weight)
    add(e.b, e.a, e.weight)
  }
  return adj
}

/** Кучки связанных исполнителей. Порядок — по суммарному весу; одиночки без связей — одной
 *  общей кучкой в конце. */
export function clusters(nodes: readonly MapNode[], adj: Adjacency): string[][] {
  const order = [...nodes].sort(byWeight)
  const weight = new Map(order.map((n) => [n.key, n.weight]))
  const label = new Map(order.map((n, i) => [n.key, i]))
  for (let round = 0; round < LABEL_ROUNDS; round++) {
    let moved = false
    for (const n of order) {
      const best = strongestLabel(n.key, adj, label)
      if (best !== undefined && best !== label.get(n.key)) {
        label.set(n.key, best)
        moved = true
      }
    }
    if (!moved) break
  }
  const groups = new Map<number, string[]>()
  const loose: string[] = []
  for (const n of order) {
    if (!adj.get(n.key)?.size) {
      loose.push(n.key)
      continue
    }
    const l = label.get(n.key)!
    groups.set(l, [...(groups.get(l) ?? []), n.key])
  }
  const total = (g: string[]) => g.reduce((s, k) => s + (weight.get(k) ?? 0), 0)
  const out = [...groups.values()].sort((a, b) => total(b) - total(a) || (a[0] < b[0] ? -1 : 1))
  return loose.length ? [...out, loose] : out
}

/** Метка, за которую сильнее всего тянут соседи; при равенстве — меньшая (тяжелее исполнитель). */
function strongestLabel(key: string, adj: Adjacency, label: Map<string, number>): number | undefined {
  const nb = adj.get(key)
  if (!nb?.size) return undefined
  const score = new Map<number, number>()
  for (const [k, w] of nb) {
    const l = label.get(k)
    if (l !== undefined) score.set(l, (score.get(l) ?? 0) + w)
  }
  let best = label.get(key)!
  let bestScore = score.get(best) ?? 0
  for (const [l, s] of score) {
    if (s > bestScore + EPS || (Math.abs(s - bestScore) <= EPS && l < best)) {
      best = l
      bestScore = s
    }
  }
  return best
}

/** Сетка для быстрой проверки наложений: клетка не меньше диаметра самого большого круга. */
class Grid {
  private cells = new Map<string, Disc[]>()
  constructor(private cell: number) {}
  private id(cx: number, cy: number) {
    return `${cx},${cy}`
  }
  add(d: Disc) {
    const id = this.id(Math.floor(d.x / this.cell), Math.floor(d.y / this.cell))
    this.cells.set(id, [...(this.cells.get(id) ?? []), d])
  }
  hits(d: Disc, gap: number): boolean {
    const cx = Math.floor(d.x / this.cell)
    const cy = Math.floor(d.y / this.cell)
    for (let dx = -1; dx <= 1; dx++) {
      for (let dy = -1; dy <= 1; dy++) {
        for (const o of this.cells.get(this.id(cx + dx, cy + dy)) ?? []) {
          const min = o.r + d.r + gap - EPS
          if ((o.x - d.x) ** 2 + (o.y - d.y) ** 2 < min * min) return true
        }
      }
    }
    return false
  }
}

const dist2 = (a: Point, b: Point) => (a.x - b.x) ** 2 + (a.y - b.y) ** 2

/** Жадная упаковка кругов: первый — в начале координат, каждый следующий касается одного из
 *  стоящих, ближе всего к своей цели (`goal`), без наложений. Порядок входа — порядок установки.
 *  Опору ищем среди «открытых» кругов: у кого вокруг ещё есть место хотя бы для самого маленького.
 *  Если у ближайших к цели всё занято — идём дальше от цели, пока не найдём место; так плотная
 *  середина не выталкивает новые круги в линию за краем. */
export function pack(
  radii: readonly number[],
  goal: (i: number, placed: readonly (Disc | undefined)[]) => Point,
  gap: number,
  /** Уже стоящие круги: новые обходят их и цепляются к ним. */
  fixed: readonly Disc[] = [],
): Disc[] {
  const maxR = [...radii, ...fixed.map((d) => d.r)].reduce((m, r) => Math.max(m, r), 0)
  const minR = radii.reduce((m, r) => Math.min(m, r), Infinity)
  const grid = new Grid(2 * maxR + gap)
  for (const d of fixed) grid.add(d)
  const placed: (Disc | undefined)[] = new Array(radii.length).fill(undefined)
  let open: Disc[] = [...fixed]
  for (let i = 0; i < radii.length; i++) {
    const r = radii[i]
    let d: Disc
    if (open.length === 0) d = { x: 0, y: 0, r }
    else {
      const spot = bestSpot(r, goal(i, placed), open, grid, gap, minR)
      d = spot.disc
      if (spot.full.size) open = open.filter((o) => !spot.full.has(o))
    }
    placed[i] = d
    open.push(d)
    grid.add(d)
  }
  return placed as Disc[]
}

function bestSpot(
  r: number,
  target: Point,
  open: readonly Disc[],
  grid: Grid,
  gap: number,
  minR: number,
): { disc: Disc; full: Set<Disc> } {
  const near = [...open].sort((a, b) => dist2(a, target) - dist2(b, target))
  const full = new Set<Disc>()
  let best: Disc | undefined
  let bestCost = Infinity
  let tried = 0
  for (const p of near) {
    // ближайшие к цели опоры с местом перебраны — дальше только хуже
    if (best && tried >= NEAREST) break
    const dist = p.r + r + gap
    let free = false
    for (let a = 0; a < ANGLES; a++) {
      const ang = (a * 2 * Math.PI) / ANGLES
      const c = { x: p.x + dist * Math.cos(ang), y: p.y + dist * Math.sin(ang), r }
      if (grid.hits(c, gap)) continue
      free = true
      const cost = dist2(c, target) + CENTER_PULL * (c.x * c.x + c.y * c.y)
      if (cost < bestCost - EPS) {
        best = c
        bestCost = cost
      }
    }
    if (free) tried++
    // не влез даже самый маленький — у этого круга места больше не будет
    else if (r <= minR + EPS) full.add(p)
  }
  return { disc: best ?? outside(r, open, gap), full }
}

/** Места ни у кого не нашлось (не бывает: у крайнего круга снаружи всегда свободно) — за краем. */
function outside(r: number, list: readonly Disc[], gap: number): Disc {
  const edge = list.reduce((m, d) => Math.max(m, d.x + d.r), 0)
  return { x: edge + gap + r, y: 0, r }
}

/** Центр тяжести уже поставленных соседей (по силе связи); никого — начало координат. */
function pull(neighbors: Map<number, number> | undefined, placed: readonly (Disc | undefined)[]): Point {
  let sx = 0
  let sy = 0
  let sw = 0
  for (const [j, w] of neighbors ?? []) {
    const d = placed[j]
    if (!d) continue
    sx += d.x * w
    sy += d.y * w
    sw += w
  }
  return sw > 0 ? { x: sx / sw, y: sy / sw } : { x: 0, y: 0 }
}

/** Порядок установки в кучке: самый тяжёлый, дальше — сильнее всего связанный с уже стоящими. */
function placementOrder(keys: readonly string[], adj: Adjacency, weight: Map<string, number>): string[] {
  const left = new Set(keys)
  const link = new Map<string, number>(keys.map((k) => [k, 0]))
  const out: string[] = []
  while (left.size) {
    let pick = ''
    let score = -Infinity
    for (const k of keys) {
      if (!left.has(k)) continue
      const s = link.get(k)! * 100 + (weight.get(k) ?? 0)
      if (s > score + EPS) {
        pick = k
        score = s
      }
    }
    left.delete(pick)
    out.push(pick)
    for (const [k, w] of adj.get(pick) ?? []) if (left.has(k)) link.set(k, link.get(k)! + w)
  }
  return out
}

function packCluster(keys: readonly string[], adj: Adjacency, weight: Map<string, number>, maxWeight: number): Map<string, Disc> {
  const order = placementOrder(keys, adj, weight)
  const index = new Map(order.map((k, i) => [k, i]))
  const links = order.map((k) => {
    const m = new Map<number, number>()
    for (const [o, w] of adj.get(k) ?? []) {
      const j = index.get(o)
      if (j !== undefined) m.set(j, w)
    }
    return m
  })
  const discs = pack(
    order.map((k) => radius(weight.get(k) ?? 0, maxWeight)),
    (i, placed) => pull(links[i], placed),
    GAP,
  )
  return new Map(order.map((k, i) => [k, discs[i]]))
}

/** Вся раскладка: кучки сотами, потом кучки рядом друг с другом (связанные — ближе). Одиночки
 *  без связей не лепятся отдельным пятном сбоку, а обступают кучки кольцом — карта получается
 *  круглой. */
export function layout(nodes: readonly MapNode[], edges: readonly MapEdge[]): Layout {
  if (!nodes.length) return { nodes: [], byKey: new Map(), clusters: [], bounds: { minX: 0, minY: 0, maxX: 0, maxY: 0 } }
  const known = new Set(nodes.map((n) => n.key))
  const adj = adjacency(edges, known)
  const weight = new Map(nodes.map((n) => [n.key, n.weight]))
  const maxWeight = nodes.reduce((m, n) => Math.max(m, n.weight), 0)
  const all = clusters(nodes, adj)
  const last = all[all.length - 1]
  const hasLoose = !adj.get(last[0])?.size
  const groups = hasLoose ? all.slice(0, -1) : all
  const loose = hasLoose ? last : []

  const inner = groups.map((keys) => packCluster(keys, adj, weight, maxWeight))
  const extent = inner.map((m) => [...m.values()].reduce((e, d) => Math.max(e, Math.hypot(d.x, d.y) + d.r), 0))

  const groupOf = new Map<string, number>()
  groups.forEach((g, i) => g.forEach((k) => groupOf.set(k, i)))
  const between = groups.map(() => new Map<number, number>())
  for (const [a, m] of adj) {
    for (const [b, w] of m) {
      const ga = groupOf.get(a)
      const gb = groupOf.get(b)
      if (ga !== undefined && gb !== undefined && ga !== gb) between[ga].set(gb, (between[ga].get(gb) ?? 0) + w)
    }
  }
  const centers = pack(extent, (i, placed) => pull(between[i], placed), CLUSTER_GAP)

  const placed: Placed[] = []
  const boxes: ClusterBox[] = groups.map((keys, ci) => {
    const c = centers[ci]
    for (const k of keys) {
      const d = inner[ci].get(k)!
      placed.push({ key: k, x: c.x + d.x, y: c.y + d.y, r: d.r, cluster: ci })
    }
    return { id: ci, x: c.x, y: c.y, r: extent[ci], keys }
  })

  if (loose.length) {
    // центр масс кучек — чтобы кольцо одиночек легло вокруг карты, а не вокруг первой кучки
    const mass = placed.reduce((m, p) => m + p.r * p.r, 0)
    const mid = mass > 0 ? { x: placed.reduce((s, p) => s + p.x * p.r * p.r, 0) / mass, y: placed.reduce((s, p) => s + p.y * p.r * p.r, 0) / mass } : { x: 0, y: 0 }
    const discs = pack(
      loose.map((k) => radius(weight.get(k) ?? 0, maxWeight)),
      () => mid,
      GAP,
      // кучки — целиком, с полем: одиночки обступают их, но не влезают в щели и не размывают границы
      boxes.map((b) => ({ x: b.x, y: b.y, r: b.r + LOOSE_MARGIN })),
    )
    const id = boxes.length
    loose.forEach((k, i) => placed.push({ key: k, ...discs[i], cluster: id }))
    const r = discs.reduce((e, d) => Math.max(e, Math.hypot(d.x - mid.x, d.y - mid.y) + d.r), 0)
    boxes.push({ id, x: mid.x, y: mid.y, r, keys: loose })
  }
  return { nodes: placed, byKey: new Map(placed.map((p) => [p.key, p])), clusters: boxes, bounds: boundsOf(placed) }
}

export function boundsOf(discs: readonly Disc[]): Bounds {
  if (!discs.length) return { minX: 0, minY: 0, maxX: 0, maxY: 0 }
  return discs.reduce(
    (b, d) => ({
      minX: Math.min(b.minX, d.x - d.r),
      minY: Math.min(b.minY, d.y - d.r),
      maxX: Math.max(b.maxX, d.x + d.r),
      maxY: Math.max(b.maxY, d.y + d.r),
    }),
    { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity },
  )
}

/** Круг под точкой мира; из наложенных (их нет, но на всякий) — верхний, т. е. последний. */
export function hitTest(nodes: readonly Placed[], p: Point): Placed | undefined {
  for (let i = nodes.length - 1; i >= 0; i--) {
    const n = nodes[i]
    if (dist2(n, p) <= n.r * n.r) return n
  }
  return undefined
}

/** Поиск по карте: точное имя, потом начало имени, потом вхождение; без учёта регистра. */
export function findNode(nodes: readonly MapNode[], query: string): MapNode | undefined {
  const q = query.trim().toLowerCase()
  if (!q) return undefined
  const sorted = [...nodes].sort(byWeight)
  return (
    sorted.find((n) => n.name.toLowerCase() === q) ??
    sorted.find((n) => n.name.toLowerCase().startsWith(q)) ??
    sorted.find((n) => n.name.toLowerCase().includes(q))
  )
}
