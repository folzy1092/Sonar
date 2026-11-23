// Тональности сведения (docs/BLEND.md §7.4, §14): круг Camelot, совместимость и сдвиг тона.

import { describe, expect, it } from 'vitest'
import { camelot, camelotName, compat, keyMatch, MAX_SHIFT, UNKNOWN_SCORE } from './camelot'

const C = 0
const CSHARP = 1
const D = 2
const F = 5
const G = 7
const A_MINOR = 21
const E_MINOR = 16

describe('camelot', () => {
  it('до мажор — 8B, ля минор — 8A, соль — 9B, фа — 7B, ми минор — 9A', () => {
    expect(camelotName(C)).toBe('8B')
    expect(camelotName(A_MINOR)).toBe('8A')
    expect(camelotName(G)).toBe('9B')
    expect(camelotName(F)).toBe('7B')
    expect(camelotName(E_MINOR)).toBe('9A')
    expect(camelotName(null)).toBe('—')
  })

  it('все 24 тональности — разные клетки круга', () => {
    const cells = new Set(Array.from({ length: 24 }, (_, k) => camelotName(k)))
    expect(cells.size).toBe(24)
    for (let k = 0; k < 24; k++) expect(camelot(k).num).toBeGreaterThanOrEqual(1)
  })
})

describe('compat', () => {
  it('та же клетка и ±1 по кругу — 1, +2 — 0.6, дальше — 0', () => {
    expect(compat(C, C)).toBe(1)
    expect(compat(C, G)).toBe(1)
    expect(compat(C, F)).toBe(1)
    expect(compat(C, D)).toBe(0.6)
    expect(compat(C, CSHARP)).toBe(0)
  })

  it('мажор ↔ минор — только с тем же номером', () => {
    expect(compat(C, A_MINOR)).toBe(1)
    expect(compat(A_MINOR, C)).toBe(1)
    expect(compat(C, E_MINOR)).toBe(0)
  })
})

describe('keyMatch', () => {
  it('неизвестная тональность — середина, без сдвига и без «каши»', () => {
    expect(keyMatch(null, C, { allowShift: true })).toEqual({ score: UNKNOWN_SCORE, shift: 0, clash: false })
    expect(keyMatch(C, null, { allowShift: false })).toEqual({ score: UNKNOWN_SCORE, shift: 0, clash: false })
  })

  it('совместимые без сдвига', () => {
    expect(keyMatch(C, G, { allowShift: true })).toEqual({ score: 1, shift: 0, clash: false })
  })

  it('несовместимые — нужный сдвиг тона B, а без разрешения — «каша»', () => {
    expect(keyMatch(C, CSHARP, { allowShift: true })).toEqual({ score: 1, shift: -1, clash: false })
    expect(keyMatch(C, CSHARP, { allowShift: false })).toEqual({ score: 0, shift: 0, clash: true })
  })

  it('сдвиг не больше MAX_SHIFT полутонов', () => {
    for (let b = 0; b < 24; b++) {
      const m = keyMatch(C, b, { allowShift: true })
      expect(Math.abs(m.shift)).toBeLessThanOrEqual(MAX_SHIFT)
    }
  })

  it('связанная скорость сама сдвигает тон: до-диез на 0.944× — уже до', () => {
    const rate = 2 ** (-1 / 12)
    const m = keyMatch(C, CSHARP, { driftB: 12 * Math.log2(rate), allowShift: false })
    expect(m).toEqual({ score: 1, shift: 0, clash: false })
  })

  it('дробный дрейф от скорости — дробный сдвиг', () => {
    const m = keyMatch(C, C, { driftB: 0.5, allowShift: true })
    expect(m.clash).toBe(false)
    expect(m.shift).toBeCloseTo(-0.5, 2)
  })
})
