import { describe, expect, it } from 'vitest'
import { growLimit, LIST_STEP, LIST_WINDOW } from './list-window'

describe('окно длинного списка', () => {
  it('растёт на шаг, но не дальше конца списка', () => {
    expect(growLimit(LIST_WINDOW, 1000)).toBe(LIST_WINDOW + LIST_STEP)
    expect(growLimit(LIST_WINDOW, LIST_WINDOW + 5)).toBe(LIST_WINDOW + 5)
  })
  it('не сжимается, если список стал короче окна', () => {
    expect(growLimit(LIST_WINDOW, 10)).toBe(LIST_WINDOW)
  })
})
