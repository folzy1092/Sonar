import { describe, expect, it } from 'vitest'
import type { MapNode } from './api'
import { layout } from './layout'
import { frameNodes, positionsOf, progress } from './scene'
import { edgeTier } from './render'

const node = (key: string, weight = 1): MapNode => ({
  key,
  name: key,
  refs: [],
  avatar_url: null,
  tracks: 1,
  plays: 0,
  weight,
  discovered: true,
})

describe('кадр между раскладками', () => {
  const nodes = [node('a', 3), node('b', 1)]
  const byKey = new Map(nodes.map((n) => [n.key, n]))
  const l = layout(nodes, [])

  it('новые круги стоят на месте и проявляются', () => {
    const f = frameNodes(l, byKey, new Map(), 0, 0.25)
    expect(f.map((n) => n.shown)).toEqual([0.25, 0.25])
    expect(f[0].x).toBe(l.nodes[0].x)
  })

  it('старые переезжают с прежнего места', () => {
    const prev = new Map([['a', { x: l.nodes[0].x - 100, y: l.nodes[0].y, r: 10 }]])
    const half = frameNodes(l, byKey, prev, 0.5, 1)
    const a = half.find((n) => n.key === 'a')!
    expect(a.x).toBeCloseTo(l.nodes[0].x - 50, 9)
    expect(a.shown).toBe(1)
    const done = frameNodes(l, byKey, prev, 1, 1)
    expect(positionsOf(done).get('a')).toEqual({ x: l.nodes[0].x, y: l.nodes[0].y, r: l.nodes[0].r })
  })

  it('доля времени — от 0 до 1, без длительности — сразу 1', () => {
    expect(progress(100, 50, 200)).toBe(0)
    expect(progress(100, 200, 200)).toBe(0.5)
    expect(progress(100, 900, 200)).toBe(1)
    expect(progress(100, 100, 0)).toBe(1)
  })

  it('рёбра делятся на три пачки по силе', () => {
    expect(edgeTier(4)).toBe(0)
    expect(edgeTier(1.5)).toBe(1)
    expect(edgeTier(0.2)).toBe(2)
  })
})
