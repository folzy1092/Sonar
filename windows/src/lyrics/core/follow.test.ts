import { describe, expect, it } from 'vitest'
import { scrollsSmoothly, shouldAutoScroll, shouldPaint, SMOOTH_LINES, USER_SCROLL_PAUSE } from './follow'

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

  it('открыли текст на середине трека — на строку сразу, а не плавно с самого верха', () => {
    // новый текст стартует с -1, первый кадр находит, скажем, 24-ю строку
    expect(scrollsSmoothly(-1, 24)).toBe(false)
    expect(scrollsSmoothly(-1, SMOOTH_LINES + 1)).toBe(false)
  })

  it('строка за строкой — плавно, включая выход из вступления на первую', () => {
    expect(scrollsSmoothly(-1, 0)).toBe(true)
    expect(scrollsSmoothly(7, 8)).toBe(true)
    expect(scrollsSmoothly(7, 7 + SMOOTH_LINES)).toBe(true)
  })

  it('перемотка далеко назад или вперёд — сразу', () => {
    expect(scrollsSmoothly(30, 5)).toBe(false)
    expect(scrollsSmoothly(5, 30)).toBe(false)
  })
})
