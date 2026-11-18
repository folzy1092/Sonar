import { describe, expect, it } from 'vitest'
import type { MapEdge, MapGraph, MapNode } from './api'
import { artistRef, clusterHeads, clusterMembers, connections, discoveredCount, focusSet } from './graph'
import { layout } from './layout'
import { BANNER_MIN_ARTISTS, shouldOfferMap } from './banner'

const node = (key: string, weight = 1, discovered = true, refs: string[] = []): MapNode => ({
  key,
  name: key,
  refs,
  avatar_url: null,
  tracks: 1,
  plays: 0,
  weight,
  discovered,
})

const edge = (a: string, b: string, weight: number): MapEdge => ({
  a,
  b,
  weight,
  reasons: { feats: 1, prods: 0, follow: null, common: [], common_count: 0, similar: 0 },
})

const graph: MapGraph = {
  nodes: [node('a', 4), node('b', 2), node('c', 1), node('far', 1, false), node('solo', 1)],
  edges: [edge('a', 'b', 3), edge('a', 'c', 1), edge('b', 'c', 1), edge('a', 'far', 0.5)],
}

describe('выборки по графу', () => {
  it('подсветка — сам узел и его соседи', () => {
    expect([...focusSet(graph.edges, 'b')].sort()).toEqual(['a', 'b', 'c'])
    expect([...focusSet(graph.edges, 'solo')]).toEqual(['solo'])
  })

  it('связи — сильные первыми, с ограничением', () => {
    expect(connections(graph, 'a').map((c) => c.node.key)).toEqual(['b', 'c', 'far'])
    expect(connections(graph, 'a', 1).map((c) => c.node.key)).toEqual(['b'])
    expect(connections(graph, 'nobody')).toEqual([])
  })

  it('кучка — только исполнители из медиатеки, тяжёлые первыми', () => {
    const l = layout(graph.nodes, graph.edges)
    const byKey = new Map(graph.nodes.map((n) => [n.key, n]))
    expect(clusterMembers(l, byKey, 'b').map((n) => n.key)).toEqual(['a', 'b', 'c'])
    expect(clusterMembers(l, byKey, 'b', false).map((n) => n.key)).toContain('far')
    expect(clusterMembers(l, byKey, 'ghost')).toEqual([])
  })

  it('подписи кучек — только у связанных и достаточно больших', () => {
    const l = layout(graph.nodes, graph.edges)
    const byKey = new Map(graph.nodes.map((n) => [n.key, n]))
    const heads = clusterHeads(l, byKey, graph.edges, 3)
    expect(heads.map((h) => h.top.key)).toEqual(['a'])
    expect(clusterHeads(l, byKey, graph.edges, 10)).toEqual([])
  })

  it('счёт исполнителей медиатеки', () => {
    expect(discoveredCount(graph)).toBe(4)
    expect(discoveredCount(null)).toBe(0)
  })

  it('страница исполнителя — по ссылке исполнителя, а не трека', () => {
    expect(artistRef(node('x', 1, true, ['sc:1', 'yma:7', 'sca:5']))).toBe('yma:7')
    expect(artistRef(node('x', 1, true, ['sc:1']))).toBeUndefined()
  })
})

describe('баннер карты', () => {
  it('один раз: после переноса или при 20 исполнителях', () => {
    expect(shouldOfferMap({ done: false, artists: BANNER_MIN_ARTISTS, imported: false })).toBe(true)
    expect(shouldOfferMap({ done: false, artists: 5, imported: false })).toBe(false)
    expect(shouldOfferMap({ done: false, artists: 5, imported: true })).toBe(true)
    expect(shouldOfferMap({ done: false, artists: 1, imported: true })).toBe(false)
    expect(shouldOfferMap({ done: true, artists: 500, imported: true })).toBe(false)
  })
})
