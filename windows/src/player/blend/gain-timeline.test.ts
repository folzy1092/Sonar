// Громкость на переходе (баг: «на переходе громко, потом, когда трек включился, резко тише»): поправка
// громкости B под A раньше держалась весь переход и снималась уже после него — тихий B звучал на +N дБ, а
// потом за 2 с проседал. Теперь поправка только убавляет и к концу перехода плавно уходит в 1.

import { describe, expect, it } from 'vitest'
import { deckValue, trimAt } from './automation'
import { curvesFor } from './curves'
import type { BlendKind, TransitionPlan } from './planner'

const NYQUIST = 24_000
const KINDS: BlendKind[] = ['bass', 'filter', 'echo', 'smooth', 'drop']

function planOf(kind: BlendKind): TransitionPlan {
  const bars = { bass: 8, filter: 8, echo: 3, smooth: 16, drop: 4 }[kind]
  return {
    kind,
    sync: kind !== 'echo',
    bars,
    outMs: 60_000,
    endAMs: 60_000 + (kind === 'echo' ? 1 : bars) * 1875,
    inMs: 0,
    inAtBar: { bass: 0, filter: 0, echo: 1, smooth: 0, drop: bars }[kind],
    tempoA: 128,
    tempoB: 128,
    beatRatio: 1,
    shift: 0,
    gainDb: 0,
    cutOutMs: 0,
    cutInMs: 0,
    score: 1,
    parts: { tempo: 1, key: 1, energy: 1, phrases: 1, cut: 1, vocal: 1, fit: 1, rating: 0.5 },
  }
}

const db = (v: number) => 20 * Math.log10(v)
// B тише A на 6 дБ (громкий фонк → тихий лоу-фай) и наоборот
const MULS = [10 ** (6 / 20), 10 ** (-6 / 20)]

describe('громкость на переходе', () => {
  it.each(KINDS)('%s: ни один дек не громче своей нормы, B в конце — ровно на своей громкости', (kind) => {
    const c = curvesFor(planOf(kind), NYQUIST)
    for (const mul of MULS) {
      for (let i = 0; i <= 400; i++) {
        const bar = (c.endBar * i) / 400
        expect(deckValue(c, 'a', 'gain', bar, mul)).toBeLessThanOrEqual(1 + 1e-9)
        expect(deckValue(c, 'b', 'gain', bar, mul)).toBeLessThanOrEqual(1 + 1e-9)
      }
      // после перехода дек B в нейтрали (gain 1) — значение на последнем такте должно совпасть, без скачка
      expect(deckValue(c, 'b', 'gain', c.endBar, mul)).toBeCloseTo(c.rest.gain, 9)
    }
  })

  it('поправка уходит плавно: за 1% перехода — не больше 0.1 дБ', () => {
    const c = curvesFor(planOf('smooth'), NYQUIST)
    for (const mul of MULS)
      for (const side of ['a', 'b'] as const)
        for (let i = 0; i < 100; i++) {
          const x = trimAt(c, side, (c.endBar * i) / 100, mul)
          const y = trimAt(c, side, (c.endBar * (i + 1)) / 100, mul)
          expect(Math.abs(db(y) - db(x))).toBeLessThanOrEqual(0.061)
        }
  })

  it('громкий B входит приглушённым под A, тихий A не раздувается', () => {
    const c = curvesFor(planOf('smooth'), NYQUIST)
    expect(db(trimAt(c, 'b', 0, 10 ** (-6 / 20)))).toBeCloseTo(-6, 6)
    expect(trimAt(c, 'b', 0, 10 ** (6 / 20))).toBe(1)
    // B тише — A к концу притихает до уровня B
    expect(db(trimAt(c, 'a', c.endBar, 10 ** (6 / 20)))).toBeCloseTo(-6, 6)
  })
})
