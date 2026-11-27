import { describe, expect, it } from 'vitest'
import { growLimit, LIST_STEP, LIST_WINDOW, rowWindow } from './list-window'

describe('окно длинного списка', () => {
  it('растёт на шаг, но не дальше конца списка', () => {
    expect(growLimit(LIST_WINDOW, 1000)).toBe(LIST_WINDOW + LIST_STEP)
    expect(growLimit(LIST_WINDOW, LIST_WINDOW + 5)).toBe(LIST_WINDOW + 5)
  })
  it('не сжимается, если список стал короче окна', () => {
    expect(growLimit(LIST_WINDOW, 10)).toBe(LIST_WINDOW)
  })
})

describe('окно строк по прокрутке', () => {
  it('наверху — с нуля, экран плюс запас, кратно 10', () => {
    expect(rowWindow(0, 800, 58, 1500)).toEqual({ start: 0, end: 40 })
  })
  it('в середине — строки вокруг экрана, а не все до него', () => {
    const r = rowWindow(58 * 700, 800, 58, 1500)
    expect(r.start).toBe(680)
    expect(r.end).toBe(740)
    expect(r.end - r.start).toBeLessThan(100)
  })
  it('внизу — до конца списка, не дальше', () => {
    expect(rowWindow(58 * 1490, 800, 58, 1500).end).toBe(1500)
  })
  it('короткий список и неизвестная высота строки', () => {
    expect(rowWindow(0, 800, 58, 7)).toEqual({ start: 0, end: 7 })
    expect(rowWindow(0, 800, 0, 1500)).toEqual({ start: 0, end: LIST_WINDOW })
    expect(rowWindow(0, 800, 58, 0)).toEqual({ start: 0, end: 0 })
  })
  it('прокрутка на пару строк не двигает окно', () => {
    expect(rowWindow(58 * 300, 800, 58, 1500)).toEqual(rowWindow(58 * 302, 800, 58, 1500))
  })
})
