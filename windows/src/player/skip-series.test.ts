import { describe, expect, it } from 'vitest'
import { SERIES_COOLDOWN_MS, SkipSeries } from './skip-series'

const EARLY = -1
const SOFT = -0.4
const DONE = 1

describe('SkipSeries', () => {
  it('два ранних пропуска подряд — пересборка', () => {
    const s = new SkipSeries()
    expect(s.push(EARLY, true, 0)).toBe(false)
    expect(s.push(EARLY, true, 5_000)).toBe(true)
  })

  it('пропуск, дослушал, пропуск — серии нет', () => {
    const s = new SkipSeries()
    expect(s.push(EARLY, true, 0)).toBe(false)
    expect(s.push(DONE, false, 10_000)).toBe(false)
    expect(s.push(EARLY, true, 20_000)).toBe(false)
  })

  it('мягкий минус (слушал четверть трека) серию обрывает', () => {
    const s = new SkipSeries()
    s.push(EARLY, true, 0)
    expect(s.push(SOFT, true, 1_000)).toBe(false)
    expect(s.push(EARLY, true, 2_000)).toBe(false)
  })

  it('👎 — тоже ранний пропуск', () => {
    const s = new SkipSeries()
    s.push(EARLY, true, 0)
    expect(s.push(-2, true, 1_000)).toBe(true)
  })

  it('не ранний «исход» без ручного пропуска серию не набирает', () => {
    const s = new SkipSeries()
    s.push(EARLY, true, 0)
    expect(s.push(EARLY, false, 1_000)).toBe(false)
  })

  it('защита: не чаще раза в 60 секунд', () => {
    const s = new SkipSeries()
    s.push(EARLY, true, 0)
    expect(s.push(EARLY, true, 1_000)).toBe(true)
    // новая порция тоже мимо — но минута ещё не прошла
    s.push(EARLY, true, 10_000)
    expect(s.push(EARLY, true, 20_000)).toBe(false)
    // серия не потеряна: как только минута прошла, следующий ранний пропуск запускает пересборку
    expect(s.push(EARLY, true, 1_000 + SERIES_COOLDOWN_MS)).toBe(true)
  })

  it('после пересборки серия считается заново', () => {
    const s = new SkipSeries()
    s.push(EARLY, true, 0)
    expect(s.push(EARLY, true, 1_000)).toBe(true)
    expect(s.push(EARLY, true, 100_000)).toBe(false)
    expect(s.push(EARLY, true, 101_000)).toBe(true)
  })

  it('reset: новая сессия волны начинается с нуля, в том числе защита', () => {
    const s = new SkipSeries()
    s.push(EARLY, true, 0)
    expect(s.push(EARLY, true, 1_000)).toBe(true)
    s.reset()
    s.push(EARLY, true, 2_000)
    expect(s.push(EARLY, true, 3_000)).toBe(true)
  })
})
