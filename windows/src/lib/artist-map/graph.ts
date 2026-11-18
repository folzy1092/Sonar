// Выборки по графу карты для экрана: соседи под курсором, связи в карточке, исполнители кучки.
// Чистые функции — без DOM.
import type { MapEdge, MapGraph, MapNode } from './api'
import type { Layout } from './layout'
import { refKind } from '../services'

/** Кучка для подписи издалека: центр, размер и самый весомый исполнитель. */
export interface ClusterHead {
  x: number
  y: number
  r: number
  top: MapNode
}

export interface Connection {
  node: MapNode
  edge: MapEdge
}

/** Сам узел и все, с кем он связан, — их подсвечиваем при наведении. */
export function focusSet(edges: readonly MapEdge[], key: string): Set<string> {
  const out = new Set([key])
  for (const e of edges) {
    if (e.a === key) out.add(e.b)
    else if (e.b === key) out.add(e.a)
  }
  return out
}

/** Связи исполнителя для карточки и подсказки: сильные первыми, при равенстве — по весу соседа. */
export function connections(graph: MapGraph, key: string, limit = Infinity): Connection[] {
  const byKey = new Map(graph.nodes.map((n) => [n.key, n]))
  const out: Connection[] = []
  for (const e of graph.edges) {
    const other = e.a === key ? e.b : e.b === key ? e.a : null
    const node = other ? byKey.get(other) : undefined
    if (node) out.push({ node, edge: e })
  }
  out.sort((x, y) => y.edge.weight - x.edge.weight || y.node.weight - x.node.weight || (x.node.key < y.node.key ? -1 : 1))
  return out.slice(0, limit)
}

/** Исполнители кучки, где стоит `key`, — тяжёлые первыми; только из медиатеки, если `onlyLibrary`. */
export function clusterMembers(layout: Layout, nodes: ReadonlyMap<string, MapNode>, key: string, onlyLibrary = true): MapNode[] {
  const placed = layout.byKey.get(key)
  if (!placed) return []
  const box = layout.clusters[placed.cluster]
  if (!box) return []
  return box.keys
    .map((k) => nodes.get(k))
    .filter((n): n is MapNode => !!n && (!onlyLibrary || n.discovered))
}

/** Сколько исполнителей из медиатеки на карте (соседи снаружи не считаются). */
export function discoveredCount(graph: MapGraph | null): number {
  return graph ? graph.nodes.reduce((s, n) => s + (n.discovered ? 1 : 0), 0) : 0
}

/** Ссылка на страницу исполнителя в Sonar: первая, у которой в реестре есть страница исполнителя. */
export function artistRef(node: MapNode): string | undefined {
  return node.refs.find((r) => refKind(r) === 'artist')
}

/** Кучки, которые стоит подписать: не меньше `min` исполнителей и связанные между собой —
 *  одиночки без связей лежат общей россыпью в конце, у неё нет «главного». */
export function clusterHeads(layout: Layout, nodes: ReadonlyMap<string, MapNode>, edges: readonly MapEdge[], min: number): ClusterHead[] {
  const linked = new Set(edges.flatMap((e) => [e.a, e.b]))
  return layout.clusters.flatMap((c) => {
    const top = nodes.get(c.keys[0])
    if (!top || c.keys.length < min || !linked.has(top.key)) return []
    return [{ x: c.x, y: c.y, r: c.r, top }]
  })
}
