import { describe, expect, test } from 'vitest'
import { href, langParam, pluralIndex, splitLang, translate, translatePlural } from '.'

describe('href', () => {
  test.each([
    ['ru', '/', '/'],
    ['ru', '/pay', '/pay'],
    ['en', '/', '/en/'],
    ['en', '/pay', '/en/pay'],
    ['uk', 'faq', '/uk/faq'],
  ] as const)('%s %s → %s', (lang, path, want) => {
    expect(href(lang, path)).toBe(want)
  })
})

describe('splitLang', () => {
  test('разбирает префикс языка', () => {
    expect(splitLang('/en/@folzy')).toEqual({ lang: 'en', rest: '/@folzy' })
    expect(splitLang('/uk')).toEqual({ lang: 'uk', rest: '/' })
    expect(splitLang('/@folzy')).toEqual({ lang: 'ru', rest: '/@folzy' })
  })

  test('не путает похожие пути', () => {
    expect(splitLang('/english')).toEqual({ lang: 'ru', rest: '/english' })
  })
})

test('langParam: неизвестное — русский', () => {
  expect(langParam(undefined)).toBe('ru')
  expect(langParam('uk')).toBe('uk')
  expect(langParam('de')).toBe('ru')
})

test('контекст в ключе не виден по-русски', () => {
  expect(translate('ru', 'статус::Работает')).toBe('Работает')
})

describe('множественное число', () => {
  test.each([[1, 0], [2, 1], [4, 1], [5, 2], [11, 2], [12, 2], [21, 0], [22, 1], [25, 2], [111, 2]])('ru %i → форма %i', (n, i) => {
    expect(pluralIndex('ru', n)).toBe(i)
  })

  test('подставляет число', () => {
    expect(translatePlural('ru', 3, '{n} день|{n} дня|{n} дней')).toBe('3 дня')
    expect(translatePlural('ru', 30, '{n} день|{n} дня|{n} дней')).toBe('30 дней')
  })
})
