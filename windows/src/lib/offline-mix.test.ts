import { describe, expect, test } from 'vitest'
import { MIX_LENGTH, mixScore, rankOfflineMix, spreadArtists, tagAffinity, type MixInput } from './offline-mix'

const NOW = 1_000 * 86_400_000
const tr = (ref: string, artist = ref) => ({ ref, artist })
const sig = (ref: string, over: Partial<{ plays: number; last_played: number; skips: number; tags: string[] }> = {}) => ({
  ref,
  plays: 0,
  last_played: 0,
  skips: 0,
  tags: [] as string[],
  ...over,
})
const input = (over: Partial<MixInput> = {}): MixInput => ({
  liked: new Set(),
  signals: [],
  recentTags: [],
  now: NOW,
  rand: () => 0,
  ...over,
})

describe('tagAffinity', () => {
  test('доля тегов трека среди недавних', () => {
    expect(tagAffinity(['lofi', 'rock'], new Set(['lofi']))).toBe(0.5)
    expect(tagAffinity([], new Set(['lofi']))).toBe(0)
    expect(tagAffinity(['lofi'], new Set())).toBe(0)
  })
})

describe('mixScore', () => {
  test('лайкнутый без истории выше незнакомого', () => {
    expect(mixScore(undefined, true, new Set(), NOW)).toBeGreaterThan(mixScore(undefined, false, new Set(), NOW))
  })

  test('пропуски опускают трек', () => {
    const clean = mixScore(sig('a', { plays: 5, last_played: NOW - 10 * 86_400_000 }), false, new Set(), NOW)
    const skipped = mixScore(sig('a', { plays: 5, skips: 5, last_played: NOW - 10 * 86_400_000 }), false, new Set(), NOW)
    expect(skipped).toBeLessThan(clean)
  })

  test('только что игравшее не лезет вперёд', () => {
    const minuteAgo = mixScore(sig('a', { plays: 3, last_played: NOW - 60_000 }), false, new Set(), NOW)
    const dayAgo = mixScore(sig('a', { plays: 3, last_played: NOW - 86_400_000 }), false, new Set(), NOW)
    expect(minuteAgo).toBeLessThan(dayAgo)
  })
})

describe('rankOfflineMix', () => {
  test('без случайности: лайк и прослушивания впереди, совпадение тегов поднимает', () => {
    const pool = [tr('x'), tr('liked'), tr('played'), tr('tagged')]
    const got = rankOfflineMix(
      pool,
      input({
        liked: new Set(['liked']),
        signals: [sig('played', { plays: 20, last_played: NOW - 3 * 86_400_000 }), sig('tagged', { tags: ['lofi'] })],
        recentTags: ['lofi', 'lofi'],
      }),
    )
    expect(got.map((t) => t.ref)).toEqual(['played', 'liked', 'tagged', 'x'])
  })

  test('только треки из пула, не длиннее MIX_LENGTH', () => {
    const pool = Array.from({ length: MIX_LENGTH + 10 }, (_, i) => tr(`r${i}`))
    const got = rankOfflineMix(pool, input({ signals: [sig('чужой', { plays: 100 })], rand: Math.random }))
    expect(got).toHaveLength(MIX_LENGTH)
    expect(got.every((t) => t.ref.startsWith('r'))).toBe(true)
  })

  test('случайность меняет порядок равных', () => {
    const pool = [tr('a'), tr('b'), tr('c')]
    const seq = [0.1, 0.9, 0.5]
    let i = 0
    const got = rankOfflineMix(pool, input({ rand: () => seq[i++] }))
    expect(got.map((t) => t.ref)).toEqual(['b', 'c', 'a'])
  })
})

describe('spreadArtists', () => {
  test('один исполнитель не идёт подряд, пока есть другие', () => {
    const got = spreadArtists([tr('1', 'A'), tr('2', 'A'), tr('3', 'B'), tr('4', 'A')])
    expect(got.map((t) => t.artist)).toEqual(['A', 'B', 'A', 'A'])
  })
})
