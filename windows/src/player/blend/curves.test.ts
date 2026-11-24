// Кривые сведения (docs/BLEND.md §8, §14): в начале B молчит, в конце A молчит; после свапа ровно один бас;
// равная мощность без провалов > 1.5 дБ; B на полной за долю у «Эха» и «На дроп»; резкие места ≥ 5 мс.

import { describe, expect, it } from 'vitest'
import { curvesFor, keyBars, paramsAt, steps, tempoAt } from './curves'
import { ISO_MIN_DB } from './deck-chain'
import type { BlendKind, TransitionPlan } from './planner'

const NYQUIST = 24_000
const MIN_STEP_SEC = 0.005
const EPS = 1e-9

function planOf(kind: BlendKind, over: Partial<TransitionPlan> = {}): TransitionPlan {
  const bars = { bass: 8, filter: 8, echo: 3, smooth: 16, drop: 4 }[kind]
  const inAtBar = { bass: 0, filter: 0, echo: 1, smooth: 0, drop: bars }[kind]
  return {
    kind,
    sync: kind !== 'echo',
    bars,
    outMs: 60_000,
    endAMs: 60_000 + (kind === 'echo' ? 1 : bars) * 1875,
    inMs: 0,
    inAtBar,
    tempoA: 128,
    tempoB: 128,
    beatRatio: 1,
    shift: 0,
    gainDb: 0,
    cutOutMs: 0,
    cutInMs: 0,
    score: 1,
    parts: { tempo: 1, key: 1, energy: 1, phrases: 1, cut: 1, vocal: 1, fit: 1, rating: 0.5 },
    ...over,
  }
}

const KINDS: BlendKind[] = ['bass', 'filter', 'echo', 'smooth', 'drop']
const sample = (to: number, n = 400) => Array.from({ length: n + 1 }, (_, i) => (to * i) / n)

describe('curvesFor', () => {
  it.each(KINDS)('%s: в начале B молчит, в конце A молчит, B на полной', (kind) => {
    const c = curvesFor(planOf(kind), NYQUIST)
    expect(paramsAt(c, 0).b.gain).toBe(0)
    expect(paramsAt(c, 0).a.gain).toBe(1)
    const end = paramsAt(c, c.endBar)
    expect(end.a.gain).toBe(0)
    expect(end.b.gain).toBeCloseTo(1, 9)
    // после «промоута» A не звучит сухим ни на такте
    expect(paramsAt(c, c.promoteBar + 0.01).a.gain).toBeLessThan(EPS)
  })

  it.each(KINDS)('%s: B до своего входа молчит', (kind) => {
    const plan = planOf(kind)
    const c = curvesFor(plan, NYQUIST)
    for (const bar of sample(plan.inAtBar)) expect(paramsAt(c, bar).b.gain).toBe(0)
  })

  it('бас-свап: всегда ровно один бас на 0 дБ, свап на середине', () => {
    for (const bars of [4, 8, 16]) {
      const c = curvesFor(planOf('bass', { bars }), NYQUIST)
      const swap = bars / 2
      for (const bar of sample(c.endBar)) {
        if (Math.abs(bar - swap) < 0.01) continue // внутри 8-миллисекундного свапа
        const { a, b } = paramsAt(c, bar)
        expect([a.low, b.low].filter((db) => db === 0)).toHaveLength(1)
        expect([a.low, b.low].filter((db) => db === ISO_MIN_DB)).toHaveLength(1)
        expect(a.low === 0).toBe(bar < swap)
      }
    }
  })

  it.each(['bass', 'filter', 'smooth'] as const)('%s: громкость без провалов больше 1.5 дБ', (kind) => {
    const c = curvesFor(planOf(kind), NYQUIST)
    for (const bar of sample(c.endBar)) {
      const { a, b } = paramsAt(c, bar)
      expect(10 * Math.log10(a.gain ** 2 + b.gain ** 2)).toBeGreaterThanOrEqual(-1.5)
    }
  })

  it('bass: B до свапа — одна середина на 0.8, A после свапа держится на 0.8 и гаснет второй половиной', () => {
    const c = curvesFor(planOf('bass'), NYQUIST)
    // 8 тактов: свап на 4, «такт» = 1, A гаснет с 6
    expect(paramsAt(c, 1).b.high).toBe(ISO_MIN_DB)
    expect(paramsAt(c, 1).b.low).toBe(ISO_MIN_DB)
    expect(paramsAt(c, 3.9).b.gain).toBeCloseTo(0.8, 9)
    expect(paramsAt(c, 5).b.gain).toBe(1)
    expect(paramsAt(c, 5).b.high).toBe(0)
    expect(paramsAt(c, 5).a.high).toBe(-20)
    expect(paramsAt(c, 6).a.gain).toBeCloseTo(0.8, 9)
    expect(paramsAt(c, 6).a.high).toBe(ISO_MIN_DB)
    expect(paramsAt(c, 8).a.gain).toBe(0)
  })

  it('drop: B на полной громкости сразу на дропе', () => {
    const plan = planOf('drop')
    const c = curvesFor(plan, NYQUIST)
    expect(paramsAt(c, plan.inAtBar + 0.25).b.gain).toBeCloseTo(1, 9)
  })

  it('drop: разгон A уходит в эхо, хвост звенит после дропа и к концу глохнет', () => {
    const plan = planOf('drop')
    const c = curvesFor(plan, NYQUIST)
    expect(paramsAt(c, plan.bars - 1).a.echoSend).toBe(0)
    expect(paramsAt(c, plan.bars - 0.25).a.echoSend).toBe(1)
    expect(paramsAt(c, plan.bars + 1).a.feedback).toBeGreaterThan(0)
    expect(paramsAt(c, plan.bars + 1).a.gain).toBe(0)
    expect(c.endBar).toBe(plan.bars + 2)
    expect(paramsAt(c, c.endBar).a.echoSend).toBe(0)
  })

  it('echo: B выходит в полную громкость за такт, бас — за два, а не стеной на «раз»', () => {
    const plan = planOf('echo')
    const c = curvesFor(plan, NYQUIST)
    const one = plan.inAtBar
    expect(paramsAt(c, one + 0.25).b.gain).toBeGreaterThan(0)
    expect(paramsAt(c, one + 0.25).b.gain).toBeLessThan(1)
    expect(paramsAt(c, one + 1).b.gain).toBeCloseTo(1, 9)
    expect(paramsAt(c, one + 1).b.low).toBeLessThan(0)
    expect(paramsAt(c, one + 2).b.low).toBe(0)
  })

  it.each(KINDS)('%s: каждое изменение не короче 5 мс даже при разгоне темпа', (kind) => {
    const plan = planOf(kind, { tempoB: 135 })
    const c = curvesFor(plan, NYQUIST)
    const fastest = Math.max(plan.tempoA, plan.tempoB)
    for (const s of steps(c)) expect((s.bars * 240) / fastest).toBeGreaterThanOrEqual(MIN_STEP_SEC - EPS)
  })

  it('фильтр: highpass A растёт до 1.2 кГц, lowpass B открывается до Найквиста, бас B −12 пока HPF низко', () => {
    const c = curvesFor(planOf('filter'), NYQUIST)
    expect(paramsAt(c, 0).a.hpHz).toBe(20)
    expect(paramsAt(c, 8).a.hpHz).toBeCloseTo(1200, 6)
    expect(paramsAt(c, 8).b.lpHz).toBeCloseTo(NYQUIST, 6)
    for (const bar of sample(8)) {
      const { a, b } = paramsAt(c, bar)
      if (a.hpHz < 150) expect(b.low).toBe(-12)
    }
  })

  it('эхо: петля набирается с начала перехода до последней доли, сухой A гаснет полтакта после «раз»', () => {
    const plan = planOf('echo')
    const c = curvesFor(plan, NYQUIST)
    expect(paramsAt(c, 0).a.echoSend).toBe(0)
    const half = paramsAt(c, 0.375).a.echoSend
    expect(half).toBeGreaterThan(0)
    expect(half).toBeLessThan(1)
    expect(paramsAt(c, 0.75).a.echoSend).toBe(1)
    expect(paramsAt(c, 0.75).a.feedback).toBeCloseTo(0.55, 9)
    expect(paramsAt(c, 1).a.gain).toBe(1)
    // не обрыв: через четверть такта после «раз» сухой A ещё слышен
    expect(paramsAt(c, 1.25).a.gain).toBeGreaterThan(0.5)
    expect(paramsAt(c, 1.5).a.gain).toBe(0)
    expect(paramsAt(c, 3).a.feedback).toBeCloseTo(0.3, 9)
    expect(c.echoDelaySec).toBeCloseTo((0.75 * 60) / 128, 9)
    // A отпускают только когда он замолк
    expect(c.promoteBar).toBe(1.5)
    expect(c.endBar).toBe(3)
  })

  it('после последней точки — нейтраль или последнее значение, вне кривых — нейтраль', () => {
    const c = curvesFor(planOf('smooth'), NYQUIST)
    const after = paramsAt(c, 100)
    expect(after.b).toEqual({ ...c.rest, gain: after.b.gain })
    expect(after.a.hpHz).toBe(c.rest.hpHz)
    expect(after.a.lpHz).toBe(NYQUIST)
  })

  it('ключевые такты — в окне и по порядку', () => {
    const c = curvesFor(planOf('bass'), NYQUIST)
    const bars = keyBars(c, 1, 5)
    expect(bars.length).toBeGreaterThan(0)
    for (let i = 0; i < bars.length; i++) {
      expect(bars[i]).toBeGreaterThan(1)
      expect(bars[i]).toBeLessThanOrEqual(5)
      if (i > 0) expect(bars[i]).toBeGreaterThan(bars[i - 1])
    }
  })
})

describe('tempoAt', () => {
  it('без синка — null, у каждого дека своя скорость', () => {
    expect(tempoAt(planOf('echo'), 1)).toBeNull()
  })

  it('с синком — из TA в TB/beatRatio по smoothstep, без рывков', () => {
    const plan = planOf('bass', { tempoA: 124, tempoB: 126 })
    expect(tempoAt(plan, 0)).toBe(124)
    expect(tempoAt(plan, 8)).toBe(126)
    expect(tempoAt(plan, 4)).toBeCloseTo(125, 9)
    expect(tempoAt(plan, 20)).toBe(126)
    let prev = 0
    for (const bar of sample(8)) {
      const t = tempoAt(plan, bar)!
      expect(t).toBeGreaterThanOrEqual(prev)
      prev = t
    }
  })

  it('B в половинной сетке: общий темп идёт к удвоенному темпу B', () => {
    expect(tempoAt(planOf('bass', { tempoA: 128, tempoB: 64, beatRatio: 0.5 }), 8)).toBe(128)
  })
})
