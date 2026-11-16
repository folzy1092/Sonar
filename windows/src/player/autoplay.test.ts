import { describe, expect, it, vi } from 'vitest'

vi.mock('./player.svelte', () => ({ player: {} }))
vi.mock('./my-wave.svelte', () => ({ wave: {}, WAVE_CONTEXT: 'wave' }))
vi.mock('../lib/api', () => ({ api: {} }))
vi.mock('../lib/settings.svelte', () => ({ settings: { get: () => true, set: () => {} } }))

const { autoplaySeeds, freshSimilar } = await import('./autoplay.svelte')

const tr = (ref: string, available = true) =>
  ({ ref, title: ref, artist: 'a', artists: [], album: null, duration_ms: 1, cover_url: null, url: null, explicit: false, available, plays: null, tags: null }) as never
const refs = (l: { ref: string }[]) => l.map((t) => t.ref)

describe('freshSimilar', () => {
  it('чередует сиды, без очереди, 👎, недоступных и повторов, не больше n', () => {
    const a = [tr('s1'), tr('q1'), tr('s3'), tr('s4', false)]
    const b = [tr('s1'), tr('d1'), tr('s5'), tr('s6')]
    const out = freshSimilar([a, b], new Set(['q1']), (r) => r === 'd1', 3)
    expect(refs(out)).toEqual(['s1', 's3', 's5'])
  })
})

describe('autoplaySeeds', () => {
  it('последний трек и случайный из своей части очереди', () => {
    const q = [tr('a'), tr('b'), tr('x'), tr('y')]
    const out = autoplaySeeds(q, new Set(['x', 'y']), () => 0.99)
    expect(refs(out)).toEqual(['y', 'b'])
  })
  it('очередь из одного трека — он один', () => {
    expect(refs(autoplaySeeds([tr('a')], new Set()))).toEqual(['a'])
    expect(autoplaySeeds([], new Set())).toEqual([])
  })
})
