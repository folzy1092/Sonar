import { describe, expect, it } from 'vitest'
import { FADE_MS, fadeK, leftLabel } from './sleep-core'

describe('таймер сна', () => {
  it('громкость: до затухания — полная, к концу — плавно в ноль', () => {
    expect(fadeK(FADE_MS + 1000, FADE_MS)).toBe(1)
    expect(fadeK(FADE_MS, FADE_MS)).toBe(1)
    expect(fadeK(FADE_MS / 2, FADE_MS)).toBeCloseTo(0.25)
    expect(fadeK(0, FADE_MS)).toBe(0)
    expect(fadeK(-5, FADE_MS)).toBe(0)
  })
  it('подпись: минуты вверх, последняя минута — секунды', () => {
    expect(leftLabel(15 * 60_000)).toBe('15')
    expect(leftLabel(14 * 60_000 + 1)).toBe('15')
    expect(leftLabel(60_000)).toBe('1')
    expect(leftLabel(45_000)).toBe('0:45')
    expect(leftLabel(0)).toBe('0:00')
  })
})
