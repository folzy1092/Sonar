import { describe, expect, it } from 'vitest'
import { Clock } from './clock'
import { findLine } from './find'
import { progress } from './progress'
import { clampOffset, formatOffset, fromMs, toMs } from './offset'
import type { Line } from './types'

const L = (time: number, duration = 1): Line => ({ time, duration, text: String(time), isBackground: false })

describe('Clock', () => {
  it('идёт плавно между редкими timeupdate', () => {
    const c = new Clock()
    c.play(10, 0)
    expect(c.read(250)).toBeCloseTo(10.25)
    c.sample(10.5, 500) // timeupdate раз в 500 мс — совпадает
    expect(c.read(750)).toBeCloseTo(10.75)
  })

  it('мягко подстраивается под маленький дрейф', () => {
    const c = new Clock()
    c.play(0, 0)
    c.sample(1.2, 1000) // часы 1.0, звук 1.2
    expect(c.now(1000)).toBeCloseTo(1.05)
  })

  it('жёстко переносит якорь при большом расхождении', () => {
    const c = new Clock()
    c.play(0, 0)
    c.sample(5, 1000)
    expect(c.now(1000)).toBeCloseTo(5)
  })

  it('пауза держит время, плей продолжает', () => {
    const c = new Clock()
    c.play(3, 0)
    c.hold(3.4)
    expect(c.read(10_000)).toBeCloseTo(3.4)
    c.play(3.4, 10_000)
    expect(c.read(11_000)).toBeCloseTo(4.4)
  })

  it('монотонно, но seek назад разрешён', () => {
    const c = new Clock()
    c.play(10, 0)
    expect(c.read(1000)).toBeCloseTo(11)
    c.sample(10.9, 1000) // звук чуть позади — назад не прыгаем
    expect(c.read(1000)).toBeGreaterThanOrEqual(11)
    c.seek(2)
    expect(c.read(1000)).toBeCloseTo(2)
  })

  it('seek вперёд', () => {
    const c = new Clock()
    c.play(1, 0)
    c.seek(60)
    c.play(60, 100)
    expect(c.read(600)).toBeCloseTo(60.5)
  })

  it('скорость 0.5× и 2×', () => {
    const c = new Clock()
    c.play(0, 0, 0.5)
    expect(c.read(1000)).toBeCloseTo(0.5)
    c.setRate(2, 0.5, 1000)
    expect(c.read(2000)).toBeCloseTo(2.5)
  })

  it('не выходит за длительность и ноль', () => {
    const c = new Clock()
    c.duration = 3
    c.play(2.9, 0)
    expect(c.read(5000)).toBe(3)
    c.seek(-1)
    expect(c.read(0)).toBe(0)
  })
})

describe('findLine', () => {
  const lines = [L(1), L(3), L(5), L(8)]
  it('до первой строки и после последней', () => {
    expect(findLine(lines, 0.5)).toBe(-1)
    expect(findLine(lines, 100, 3)).toBe(3)
  })
  it('рядом с прошлым и далёкий прыжок', () => {
    expect(findLine(lines, 3.2, 0)).toBe(1)
    expect(findLine(lines, 8.1, 0)).toBe(3)
    expect(findLine(lines, 1.5, 3)).toBe(0)
  })
  it('пустой текст', () => {
    expect(findLine([], 5)).toBe(-1)
  })
})

describe('progress', () => {
  it('прошлое, текущее, будущее', () => {
    expect(progress(1, 2, 0.5)).toBe(0)
    expect(progress(1, 2, 2)).toBeCloseTo(0.5)
    expect(progress(1, 2, 3)).toBe(1)
  })
  it('слово нулевой длительности', () => {
    expect(progress(1, 0, 1.025)).toBeCloseTo(0.5)
    expect(progress(1, 0, 1.06)).toBe(1)
  })
})

describe('offset', () => {
  it('границы ±15 с и округление', () => {
    expect(clampOffset(20)).toBe(15)
    expect(clampOffset(-16)).toBe(-15)
    expect(clampOffset(0.12345)).toBe(0.123)
    expect(toMs(-0.25)).toBe(-250)
    expect(fromMs(null)).toBe(0)
    expect(formatOffset(0.25)).toBe('+0.250 с')
    expect(formatOffset(-1)).toBe('−1.000 с')
    expect(formatOffset(0)).toBe('0.000 с')
  })
})
