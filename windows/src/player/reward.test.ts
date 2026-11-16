import { describe, expect, it } from 'vitest'
import { artistKey, isEarlySkip, reward, type Outcome } from './reward'

const MIN = 60_000
const D = 4 * MIN
const o = (listenedMs: number, durationMs: number, manualSkip: boolean, extra: Partial<Outcome> = {}): Outcome => ({
  listenedMs,
  durationMs,
  manualSkip,
  liked: false,
  disliked: false,
  ...extra,
})

describe('reward — таблица docs/WAVE.md 1.3 (как wave.rs)', () => {
  it('👎 и лайк', () => {
    expect(reward(o(D, D, false, { disliked: true }))).toBe(-2)
    expect(reward(o(10_000, D, true, { liked: true }))).toBe(1.5)
  })
  it('пропуски по доле и секундам', () => {
    expect(reward(o(10_000, D, true))).toBe(-1)
    expect(reward(o(50_000, D, true))).toBe(-1) // f < 0.25
    expect(reward(o(35_000, 100_000, true))).toBe(-0.4)
    expect(reward(o(25_000, 100_000, true))).toBe(-1) // f ≥ 0.25, но < 30 с
    expect(reward(o(2 * MIN, D, true))).toBe(0)
    expect(reward(o((D * 8) / 10, D, true))).toBe(1)
  })
  it('закончился сам или сменился не пропуском', () => {
    expect(reward(o(D, D, false))).toBe(1)
    expect(reward(o(10_000, D, false))).toBe(0)
  })
  it('длительность неизвестна', () => {
    expect(reward(o(10_000, 0, true))).toBe(-1)
    expect(reward(o(60_000, 0, true))).toBe(0)
    expect(reward(o(150_000, 0, false))).toBe(1)
  })
  it('ранний пропуск', () => {
    expect(isEarlySkip(o(10_000, D, true))).toBe(true)
    expect(isEarlySkip(o(10_000, D, false))).toBe(false)
    expect(isEarlySkip(o(10_000, D, true, { liked: true }))).toBe(false)
  })
})

describe('artistKey', () => {
  const a = (name: string) => ({ ref: `yma:${name}`, name, avatar_url: null })
  it('совместный трек — первый из списка', () => {
    expect(artistKey({ artist: 'Oxxxymiron, Markul', artists: [a(' Oxxxymiron '), a('Markul')] })).toBe('oxxxymiron')
  })
  it('без списка — строка целиком', () => {
    expect(artistKey({ artist: 'Tyler, The Creator', artists: [] })).toBe('tyler, the creator')
  })
})
