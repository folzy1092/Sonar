import { describe, expect, it } from 'vitest'
import { badge, clampPitch, clampRate, linkedSemitones, pitchRatio } from './tempo.svelte'

describe('скорость и тон', () => {
  it('скорость в пределах 0.5–2 с точностью до сотых', () => {
    expect(clampRate(0.1)).toBe(0.5)
    expect(clampRate(3)).toBe(2)
    expect(clampRate(1.1549)).toBe(1.15)
    expect(clampPitch(-20)).toBe(-12)
    expect(clampPitch(1.26)).toBe(1.3)
  })
  it('связанный тон: вдвое быстрее — октава вверх, 0.8× — почти −4 полутона', () => {
    expect(linkedSemitones(2)).toBe(12)
    expect(linkedSemitones(1)).toBe(0)
    expect(linkedSemitones(0.8)).toBeCloseTo(-3.9, 1)
    expect(pitchRatio(12)).toBe(2)
  })
  it('подпись кнопки', () => {
    expect(badge(1, 0, 0)).toBe('')
    expect(badge(0.8, 0, 0)).toBe('0.8×')
    expect(badge(1, 2, 0)).toBe('+2')
    expect(badge(1, 0, 0.3)).toBe('Reverb')
  })
})

describe('питч, связанный со скоростью', () => {
  it('−2 st ≈ x0.89, а шаг 0.1 st всё равно двигает скорость', async () => {
    const { tempo } = await import('./tempo.svelte')
    tempo.setLinked(true)
    tempo.setRate(1)
    tempo.setPitch(-2)
    expect(tempo.rate).toBe(0.89)
    const r = tempo.rate
    tempo.setPitch(tempo.semitones - 0.1)
    expect(tempo.rate).toBeLessThan(r)
    tempo.setPitch(tempo.semitones + 0.1)
    expect(tempo.rate).toBe(r)
  })
})

describe('звук трека («Для этого трека»)', () => {
  it('выключенный реверб уходит нулём, кривая копируется', async () => {
    const { toSound } = await import('./tempo.svelte')
    const g = Array(12).fill(2)
    const s = toSound({ rate: 0.8, pitch: 0, linked: true, reverb: 0.5, reverbOn: false }, g)
    expect(s).toEqual({ rate: 0.8, pitch: 0, linked: true, reverb: 0, eq: g })
    g[0] = 9
    expect(s.eq?.[0]).toBe(2)
    expect(toSound({ rate: 3, pitch: -20, linked: false, reverb: 0.456, reverbOn: true }, null)).toEqual({
      rate: 2,
      pitch: -12,
      linked: false,
      reverb: 0.46,
      eq: null,
    })
  })
  it('реверб 0 — выключен, сила остаётся прежней', async () => {
    const { fromSound } = await import('./tempo.svelte')
    expect(fromSound({ rate: 0.8, pitch: 0, linked: true, reverb: 0, eq: null }, 0.35)).toEqual({
      rate: 0.8,
      pitch: 0,
      linked: true,
      reverb: 0.35,
      reverbOn: false,
    })
    expect(fromSound({ rate: 1, pitch: 2, linked: false, reverb: 0.6, eq: null }, 0.35).reverbOn).toBe(true)
  })
})
