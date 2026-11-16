import { describe, expect, it } from 'vitest'
import { gainFor, MAX_GAIN_DB, MIN_GAIN_DB, rmsDb, smooth, TARGET_DB } from './leveler'

describe('нормализация громкости', () => {
  it('тихое поднимает, громкое опускает, с пределами', () => {
    expect(gainFor(TARGET_DB)).toBe(0)
    expect(gainFor(TARGET_DB - 4)).toBe(4)
    expect(gainFor(-60)).toBe(MAX_GAIN_DB)
    expect(gainFor(0)).toBe(MIN_GAIN_DB)
  })
  it('RMS синуса амплитуды 1 — около −3 дБ, тишина — минус бесконечность', () => {
    const sine = Float32Array.from({ length: 4800 }, (_, i) => Math.sin((2 * Math.PI * 440 * i) / 48000))
    expect(rmsDb(sine)).toBeCloseTo(-3.01, 1)
    expect(rmsDb(new Float32Array(16))).toBe(-Infinity)
  })
  it('сглаживание идёт к замеру и не перескакивает', () => {
    const a = smooth(-30, -10, 200, 6000)
    expect(a).toBeGreaterThan(-30)
    expect(a).toBeLessThan(-29)
    let v = -30
    for (let i = 0; i < 300; i++) v = smooth(v, -10, 200, 6000)
    expect(v).toBeCloseTo(-10, 1)
  })
})
