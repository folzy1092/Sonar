import { describe, expect, it } from 'vitest'
import { shouldAutoScroll, shouldPaint, USER_SCROLL_PAUSE } from './follow'

describe('кадр синхронного текста', () => {
  it('подсветка слов идёт, даже когда курсор на аннотации Genius', () => {
    // раньше открытая аннотация останавливала весь кадр — караоке вставало до ухода курсора
    expect(shouldPaint({ synced: true, lineCount: 12, hidden: false })).toBe(true)
  })

  it('открытая аннотация держит только прокрутку', () => {
    const base = { synced: true, sinceUserScroll: Infinity }
    expect(shouldAutoScroll({ ...base, noteOpen: 3 })).toBe(false)
    expect(shouldAutoScroll({ ...base, noteOpen: null })).toBe(true)
  })

  it('без синхронизации, без строк и в свёрнутом окне кадр ничего не считает', () => {
    expect(shouldPaint({ synced: false, lineCount: 12, hidden: false })).toBe(false)
    expect(shouldPaint({ synced: true, lineCount: 0, hidden: false })).toBe(false)
    expect(shouldPaint({ synced: true, lineCount: 12, hidden: true })).toBe(false)
  })

  it('после колеса автопрокрутка ждёт паузу', () => {
    expect(shouldAutoScroll({ synced: true, sinceUserScroll: USER_SCROLL_PAUSE - 1, noteOpen: null })).toBe(false)
    expect(shouldAutoScroll({ synced: true, sinceUserScroll: USER_SCROLL_PAUSE, noteOpen: null })).toBe(true)
  })
})
