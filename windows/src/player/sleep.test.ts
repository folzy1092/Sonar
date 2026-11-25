import { describe, expect, it } from 'vitest'
import {
  clampMinutes,
  clockLabel,
  countdownLabel,
  FADE_MS,
  fadeK,
  leftLabel,
  minutesFromLeft,
  presetOf,
  SLEEP_DEFAULT,
  SLEEP_MAX,
  SLEEP_MIN,
  stopAt,
} from './sleep-core'

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
  it('ползунок: целые минуты 5…180, мусор — по умолчанию', () => {
    expect(clampMinutes(1)).toBe(SLEEP_MIN)
    expect(clampMinutes(500)).toBe(SLEEP_MAX)
    expect(clampMinutes(44.6)).toBe(45)
    expect(clampMinutes(Number.NaN)).toBe(SLEEP_DEFAULT)
  })
  it('пресет подсвечен, только если ползунок стоит ровно на нём', () => {
    expect(presetOf(45)).toBe(45)
    expect(presetOf(46)).toBeNull()
    expect(presetOf(180)).toBeNull()
  })
  it('время остановки и минуты из остатка', () => {
    const now = Date.UTC(2026, 10, 25, 7, 44)
    expect(stopAt(now, 60)).toBe(now + 3_600_000)
    expect(stopAt(now, 2)).toBe(now + SLEEP_MIN * 60_000)
    expect(minutesFromLeft(42 * 60_000 + 1)).toBe(43)
    expect(minutesFromLeft(30_000)).toBe(SLEEP_MIN)
    expect(minutesFromLeft(400 * 60_000)).toBe(SLEEP_MAX)
  })
  it('часы остановки и обратный отсчёт', () => {
    expect(clockLabel(new Date(2026, 10, 25, 8, 44).getTime(), 'ru')).toBe('08:44')
    expect(countdownLabel(42 * 60_000 + 5_000)).toBe('42:05')
    expect(countdownLabel(3_725_000)).toBe('1:02:05')
    expect(countdownLabel(400)).toBe('0:01')
    expect(countdownLabel(0)).toBe('0:00')
  })
})
