import { describe, expect, it } from 'vitest'
import type { BlendAnalysis } from './analysis'
import {
  PARTY_POOL,
  PARTY_START_FROM,
  PartyOrder,
  WARMUP_MS,
  arcTarget,
  isPartyContext,
  partyBase,
  partyContext,
  trackEnergy,
} from './party-core'

/** Анализ с нужной «энергией»: громкость и темп. */
function an(ref: string, loudness: number, bpm = 124): BlendAnalysis {
  return {
    version: 1,
    ref,
    durationMs: 200_000,
    startMs: 0,
    endMs: 200_000,
    bpm,
    bpmConf: 1,
    beatMs: 60_000 / bpm,
    firstBeatMs: 0,
    downbeat: 0,
    gridStable: true,
    key: null,
    keyConf: 0,
    loudness,
    bars: { energy: [], low: [], mid: [], onsets: [] },
    phrases: [],
  }
}

/** Детерминированный «случай». */
function seeded(seed = 1): () => number {
  let s = seed
  return () => {
    s = (s * 16807) % 2147483647
    return (s - 1) / 2147483646
  }
}

const refs = (n: number) => Array.from({ length: n }, (_, i) => `t${i}`)
const flat = () => 0.5

describe('контекст вечеринки', () => {
  it('party: поверх обычного контекста и обратно', () => {
    const ctx = partyContext('playlist:42')
    expect(isPartyContext(ctx)).toBe(true)
    expect(partyBase(ctx)).toBe('playlist:42')
    expect(isPartyContext('playlist:42')).toBe(false)
    expect(isPartyContext(null)).toBe(false)
  })
})

describe('энергия трека', () => {
  it('громче и быстрее — выше, в пределах 0…1', () => {
    expect(trackEnergy(an('a', -8, 128))).toBeGreaterThan(trackEnergy(an('b', -14, 128)))
    expect(trackEnergy(an('a', -10, 140))).toBeGreaterThan(trackEnergy(an('b', -10, 100)))
    for (const l of [-70, -30, 0, 5]) {
      const e = trackEnergy(an('x', l, 90))
      expect(e).toBeGreaterThanOrEqual(0)
      expect(e).toBeLessThanOrEqual(1)
    }
  })

  it('половинный темп считается как двойной: 64 и 128 уд/мин — одна энергия', () => {
    expect(trackEnergy(an('a', -10, 64))).toBeCloseTo(trackEnergy(an('b', -10, 128)), 5)
  })
})

describe('дуга энергии', () => {
  it('первые 20 минут цель выше текущей', () => {
    const { target, dip } = arcTarget({ elapsedMs: 5 * 60_000, sinceDip: 0, dips: 0, peak: 0.5 }, 0.5)
    expect(dip).toBe(false)
    expect(target).toBeGreaterThan(0.5)
  })

  it('после разгона держит пик, на 5-м треке — шаг вниз, следующий спад — на 6-м', () => {
    const hold = { elapsedMs: WARMUP_MS + 1, dips: 0, peak: 0.8 }
    expect(arcTarget({ ...hold, sinceDip: 0 }, 0.7).target).toBeCloseTo(0.8)
    expect(arcTarget({ ...hold, sinceDip: 3 }, 0.8).dip).toBe(false)
    const down = arcTarget({ ...hold, sinceDip: 4 }, 0.8)
    expect(down.dip).toBe(true)
    expect(down.target).toBeLessThan(0.8)
    expect(arcTarget({ ...hold, dips: 1, sinceDip: 4 }, 0.8).dip).toBe(false)
    expect(arcTarget({ ...hold, dips: 1, sinceDip: 5 }, 0.8).dip).toBe(true)
  })
})

describe('порядок вечеринки', () => {
  it('первый трек — из первых 10, пул — 8 других', () => {
    for (let seed = 1; seed < 30; seed++) {
      const o = new PartyOrder(refs(50), seeded(seed))
      expect(refs(PARTY_START_FROM)).toContain(o.first)
      expect(o.pool).toHaveLength(PARTY_POOL)
      expect(o.pool).not.toContain(o.first)
    }
  })

  it('короткий плейлист: пул — всё, что осталось', () => {
    const o = new PartyOrder(refs(3), seeded())
    expect(o.pool).toHaveLength(2)
  })

  it('без повторов: весь плейлист ровно по разу', () => {
    const all = refs(40)
    const o = new PartyOrder(all, seeded(7))
    const look = (r: string) => ({ analysis: an(r, -12 + (Number(r.slice(1)) % 7)), failed: false })
    const played = [o.first]
    o.commit(o.first, 0.5, 0)
    for (;;) {
      o.refill(() => false)
      const next = o.suggest(0, look, flat)
      if (!next) break
      played.push(next)
      o.commit(next, 0.5, 0)
    }
    expect(played).toHaveLength(all.length)
    expect(new Set(played).size).toBe(all.length)
    expect(o.done).toBe(true)
  })

  it('пул пополняется до 8 живых, сбойные не считаются', () => {
    const o = new PartyOrder(refs(30), seeded(3))
    const bad = new Set(o.pool.slice(0, 3))
    const added = o.refill((r) => bad.has(r))
    expect(added).toHaveLength(3)
    expect(o.pool.filter((r) => !bad.has(r))).toHaveLength(PARTY_POOL)
  })

  it('не проанализированные и сбойные — в конец', () => {
    const o = new PartyOrder(refs(12), seeded(5))
    const [failed, pending, ready] = o.pool
    const look = (r: string) =>
      r === ready ? { analysis: an(r, -10), failed: false } : { analysis: null, failed: r === failed }
    // есть готовый — берём его, хоть он и третий
    expect(o.suggest(0, look, flat)).toBe(ready)
    // готовых нет — первый ещё считающийся, сбойный пропускаем
    const noReady = (r: string) => (r === ready ? { analysis: null, failed: true } : look(r))
    expect(o.suggest(0, noReady, flat)).toBe(pending)
    // одни сбойные — всё равно играем, по порядку пула
    expect(o.suggest(0, () => ({ analysis: null, failed: true }), flat)).toBe(o.pool[0])
  })

  it('лучший план перехода перевешивает при равной энергии', () => {
    const o = new PartyOrder(refs(12), seeded(2))
    const [a, b] = o.pool
    const look = (r: string) => ({ analysis: r === a || r === b ? an(r, -10) : null, failed: false })
    const score = (n: BlendAnalysis) => (n.ref === b ? 0.9 : 0.2)
    expect(o.suggest(0, look, score)).toBe(b)
  })

  it('энергия идёт по дуге: растёт в разгон, потом спады раз в 5–6 треков', () => {
    // 80 треков, энергия вразнобой от тихих до громких; любой переход одинаково хорош
    const all = refs(80)
    const loud = new Map(all.map((r, i) => [r, -20 + ((i * 37) % 80) / 5]))
    const look = (r: string) => ({ analysis: an(r, loud.get(r)!), failed: false })
    const energyOf = (r: string) => trackEnergy(look(r).analysis)
    const o = new PartyOrder(all, seeded(11))
    const TRACK_MS = 4 * 60_000
    const energies = [energyOf(o.first)]
    o.commit(o.first, energies[0], 0)
    for (let i = 1; i <= 24; i++) {
      o.refill(() => false)
      const next = o.suggest(i * TRACK_MS, look, flat)!
      energies.push(energyOf(next))
      o.commit(next, energyOf(next), i * TRACK_MS)
    }
    // разгон — первые 20 минут (треки 1…5): в среднем растёт и не проваливается
    const warm = energies.slice(0, 6)
    expect(warm[5]).toBeGreaterThan(warm[0])
    for (let i = 1; i < warm.length; i++) expect(warm[i]).toBeGreaterThan(warm[i - 1] - 0.05)
    // дальше — держим, но с провалами: между спадами 5–6 треков
    const hold = energies.slice(6)
    const dropsAt = hold.flatMap((e, i) => (i > 0 && e < hold[i - 1] - 0.08 ? [i] : []))
    expect(dropsAt.length).toBeGreaterThanOrEqual(2)
    for (let i = 1; i < dropsAt.length; i++) expect(dropsAt[i] - dropsAt[i - 1]).toBeGreaterThanOrEqual(4)
  })
})
