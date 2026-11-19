import { describe, expect, test } from 'vitest'
import { DICTS, LANGS, LANG_NAMES, href, langParam, pluralIndex, splitLang, translate, translatePlural } from '.'

describe('href', () => {
  test.each([
    ['ru', '/', '/'],
    ['ru', '/pay', '/pay'],
    ['en', '/', '/en/'],
    ['en', '/pay', '/en/pay'],
    ['uk', 'faq', '/uk/faq'],
    ['pl', '/pay', '/pl/pay'],
  ] as const)('%s %s → %s', (lang, path, want) => {
    expect(href(lang, path)).toBe(want)
  })
})

describe('splitLang', () => {
  test('разбирает префикс языка', () => {
    expect(splitLang('/en/@folzy')).toEqual({ lang: 'en', rest: '/@folzy' })
    expect(splitLang('/uk')).toEqual({ lang: 'uk', rest: '/' })
    expect(splitLang('/@folzy')).toEqual({ lang: 'ru', rest: '/@folzy' })
    expect(splitLang('/de/pay')).toEqual({ lang: 'de', rest: '/pay' })
    expect(splitLang('/es')).toEqual({ lang: 'es', rest: '/' })
  })

  test('не путает похожие пути', () => {
    expect(splitLang('/english')).toEqual({ lang: 'ru', rest: '/english' })
    expect(splitLang('/plans')).toEqual({ lang: 'ru', rest: '/plans' })
  })
})

test('langParam: неизвестное — русский', () => {
  expect(langParam(undefined)).toBe('ru')
  expect(langParam('uk')).toBe('uk')
  expect(langParam('de')).toBe('de')
  expect(langParam('fr')).toBe('ru')
})

test('языки — по порядку списка, с родными названиями', () => {
  expect(LANGS).toEqual(['ru', 'en', 'uk', 'es', 'de', 'pl'])
  expect(LANGS.map((l) => LANG_NAMES[l])).toEqual(['Русский', 'English', 'Українська', 'Español', 'Deutsch', 'Polski'])
})

test('нет строки в es / de / pl — английская, в uk — русская', () => {
  const key = '{n} месяц|{n} месяца|{n} месяцев'
  const dicts = DICTS as Record<string, Record<string, string>>
  const saved = { de: dicts.de[key], pl: dicts.pl[key], uk: dicts.uk[key] }
  try {
    for (const l of ['de', 'pl', 'uk']) delete dicts[l][key]
    expect(translatePlural('de', 2, key)).toBe(translatePlural('en', 2, key))
    // английская подмена в польском — с английским правилом: 22 → вторая из двух форм
    expect(translatePlural('pl', 22, key)).toBe(translatePlural('en', 22, key))
    expect(translatePlural('uk', 2, key)).toBe('2 месяца')
  } finally {
    Object.assign(dicts.de, { [key]: saved.de })
    Object.assign(dicts.pl, { [key]: saved.pl })
    Object.assign(dicts.uk, { [key]: saved.uk })
  }
})

test('контекст в ключе не виден по-русски', () => {
  expect(translate('ru', 'статус::Работает')).toBe('Работает')
})

describe('множественное число', () => {
  test.each([[1, 0], [2, 1], [4, 1], [5, 2], [11, 2], [12, 2], [21, 0], [22, 1], [25, 2], [111, 2]])('ru %i → форма %i', (n, i) => {
    expect(pluralIndex('ru', n)).toBe(i)
  })

  test.each([[1, 0], [2, 1], [4, 1], [5, 2], [12, 2], [14, 2], [21, 2], [22, 1], [25, 2], [102, 1], [0, 2]])('pl %i → форма %i', (n, i) => {
    expect(pluralIndex('pl', n)).toBe(i)
  })

  test.each(['en', 'es', 'de'] as const)('%s — две формы', (lang) => {
    expect([1, 2, 5, 21].map((n) => pluralIndex(lang, n))).toEqual([0, 1, 1, 1])
  })

  test('подставляет число', () => {
    expect(translatePlural('ru', 3, '{n} день|{n} дня|{n} дней')).toBe('3 дня')
    expect(translatePlural('ru', 30, '{n} день|{n} дня|{n} дней')).toBe('30 дней')
  })
})
