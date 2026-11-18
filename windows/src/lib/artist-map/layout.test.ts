import { describe, expect, it } from 'vitest'
import type { MapEdge, MapNode } from './api'
import { adjacency, clusters, findNode, hitTest, layout, pack, radius, R_MAX, R_MIN, type Placed } from './layout'

const node = (key: string, weight = 1, discovered = true): MapNode => ({
  key,
  name: key.toUpperCase(),
  refs: [],
  avatar_url: null,
  tracks: 1,
  plays: 0,
  weight,
  discovered,
})

const edge = (a: string, b: string, weight = 2): MapEdge => ({
  a: a < b ? a : b,
  b: a < b ? b : a,
  weight,
  reasons: { feats: 1, prods: 0, follow: null, common: [], common_count: 0, similar: 0 },
})

function overlaps(nodes: readonly Placed[]): string[] {
  const bad: string[] = []
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const a = nodes[i]
      const b = nodes[j]
      if (Math.hypot(a.x - b.x, a.y - b.y) < a.r + b.r - 1e-6) bad.push(`${a.key}/${b.key}`)
    }
  }
  return bad
}

/** Две клики по четыре и одиночки — как маленькая медиатека. */
function sample() {
  const nodes = [node('a', 5), node('b', 3), node('c', 2), node('d', 1), node('w', 4), node('x', 2), node('y', 1), node('z', 1), node('solo', 2), node('lone', 0.5)]
  const edges: MapEdge[] = []
  for (const g of [['a', 'b', 'c', 'd'], ['w', 'x', 'y', 'z']]) {
    for (let i = 0; i < g.length; i++) for (let j = i + 1; j < g.length; j++) edges.push(edge(g[i], g[j], 3))
  }
  edges.push(edge('d', 'z', 0.4))
  return { nodes, edges }
}

describe('радиус', () => {
  it('растёт с весом и не выходит за пределы', () => {
    expect(radius(0, 10)).toBe(R_MIN)
    expect(radius(10, 10)).toBe(R_MAX)
    expect(radius(20, 10)).toBe(R_MAX)
    expect(radius(2, 10)).toBeLessThan(radius(5, 10))
    expect(radius(5, 0)).toBe(R_MIN)
  })
})

describe('кучки', () => {
  it('клики — отдельные кучки, одиночки — общей кучкой в конце', () => {
    const { nodes, edges } = sample()
    const groups = clusters(nodes, adjacency(edges))
    expect(groups.map((g) => [...g].sort())).toEqual([
      ['a', 'b', 'c', 'd'],
      ['w', 'x', 'y', 'z'],
      ['lone', 'solo'],
    ])
    expect(groups[2]).toEqual(['solo', 'lone'])
  })

  it('рёбра к неизвестным узлам не учитываются', () => {
    const adj = adjacency([edge('a', 'ghost')], new Set(['a']))
    expect(adj.size).toBe(0)
  })
})

describe('упаковка', () => {
  it('круги не налезают друг на друга', () => {
    const radii = Array.from({ length: 120 }, (_, i) => R_MIN + ((i * 7) % 30))
    const discs = pack(radii, () => ({ x: 0, y: 0 }), 4)
    const placed = discs.map((d, i) => ({ ...d, key: String(i), cluster: 0 }))
    expect(overlaps(placed)).toEqual([])
  })

  it('первый круг — в начале координат', () => {
    expect(pack([10, 10], () => ({ x: 0, y: 0 }), 2)[0]).toEqual({ x: 0, y: 0, r: 10 })
  })
})

describe('раскладка', () => {
  it('пустой граф — пустая карта', () => {
    const l = layout([], [])
    expect(l.nodes).toEqual([])
    expect(l.clusters).toEqual([])
  })

  it('одинаковый граф ложится одинаково', () => {
    const { nodes, edges } = sample()
    const one = layout(nodes, edges)
    const two = layout([...nodes].reverse(), [...edges].reverse())
    const pos = (l: ReturnType<typeof layout>) => [...l.nodes].sort((a, b) => a.key.localeCompare(b.key)).map((n) => [n.key, n.x.toFixed(3), n.y.toFixed(3)])
    expect(pos(two)).toEqual(pos(one))
  })

  it('без наложений, и внутри кучки соседи ближе, чем чужие', () => {
    const { nodes, edges } = sample()
    const l = layout(nodes, edges)
    expect(l.nodes).toHaveLength(nodes.length)
    expect(overlaps(l.nodes)).toEqual([])
    const p = (k: string) => l.byKey.get(k)!
    const d = (a: string, b: string) => Math.hypot(p(a).x - p(b).x, p(a).y - p(b).y)
    expect(d('a', 'b')).toBeLessThan(d('a', 'x'))
    expect(d('w', 'x')).toBeLessThan(d('w', 'b'))
    expect(p('a').r).toBeGreaterThan(p('d').r)
  })

  it('рамка охватывает все круги', () => {
    const { nodes, edges } = sample()
    const l = layout(nodes, edges)
    for (const n of l.nodes) {
      expect(n.x - n.r).toBeGreaterThanOrEqual(l.bounds.minX - 1e-9)
      expect(n.y + n.r).toBeLessThanOrEqual(l.bounds.maxY + 1e-9)
    }
  })

  it('300 исполнителей раскладываются быстро и без наложений', () => {
    const nodes = Array.from({ length: 320 }, (_, i) => node(`n${i}`, 1 + (i % 17)))
    const edges = Array.from({ length: 600 }, (_, i) => edge(`n${(i * 13) % 320}`, `n${(i * 29 + 7) % 320}`, 1 + (i % 3)))
    const started = performance.now()
    const l = layout(nodes, edges.filter((e) => e.a !== e.b))
    expect(performance.now() - started).toBeLessThan(2000)
    expect(overlaps(l.nodes)).toEqual([])
  })
})

describe('поиск и попадание', () => {
  it('находит по точному имени, потом по началу, потом по вхождению', () => {
    const nodes = [node('cowboyclicker', 1), node('cowboy', 0.5), node('yungcowboy', 2)]
    expect(findNode(nodes, 'COWBOY')?.key).toBe('cowboy')
    expect(findNode(nodes, 'cowb')?.key).toBe('cowboyclicker')
    expect(findNode(nodes, 'yung')?.key).toBe('yungcowboy')
    expect(findNode(nodes, '  ')).toBeUndefined()
  })

  it('попадание в круг', () => {
    const placed: Placed[] = [{ key: 'a', x: 0, y: 0, r: 10, cluster: 0 }]
    expect(hitTest(placed, { x: 6, y: 6 })?.key).toBe('a')
    expect(hitTest(placed, { x: 9, y: 9 })).toBeUndefined()
  })
})
