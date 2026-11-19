import { describe, expect, it, vi } from 'vitest'

let current = 'ru'
vi.mock('./settings.svelte', () => ({ settings: { get: () => current } }))

const { t, tn, ruPlural, plPlural, dictionary, LANGS } = await import('./i18n.svelte')

describe('i18n', () => {
  it('русский — как есть, нет перевода — русская строка', () => {
    current = 'ru'
    expect(t('Язык')).toBe('Язык')
    current = 'en'
    expect(t('Язык')).toBe('Language')
    expect(t('Строки нет в словаре')).toBe('Строки нет в словаре')
  })
  it('контекст: по-русски без него, перевод — свой', () => {
    current = 'ru'
    expect(t('список::Обновить')).toBe('Обновить')
    current = 'en'
    expect(t('список::Обновить')).toBe('Refresh')
    expect(t('Обновить')).toBe('Update')
  })
  it('подстановки', () => {
    current = 'ru'
    expect(t('Похожее на «{title}»', { title: 'X' })).toBe('Похожее на «X»')
  })
  it('множественное число', () => {
    expect([1, 2, 5, 11, 21, 22].map(ruPlural)).toEqual([0, 1, 2, 2, 0, 1])
    current = 'ru'
    expect(tn(5, ['трек', 'трека', 'треков'])).toBe('треков')
  })
  it('в словарях нет пустых переводов, у форм числа — нужное число форм', () => {
    const forms = { en: 2, uk: 3, es: 2, de: 2, pl: 3 } as const
    for (const l of ['en', 'uk', 'es', 'de', 'pl'] as const) {
      for (const [k, v] of Object.entries(dictionary(l))) {
        expect(v.trim(), `${l}: «${k}»`).not.toBe('')
        if (k.split('|').length === 3) expect(v.split('|').length, `${l}: «${k}»`).toBe(forms[l])
      }
    }
  })
  it('es / de / pl переводят всё, что переведено на английский', () => {
    const en = Object.keys(dictionary('en'))
    for (const l of ['es', 'de', 'pl'] as const) {
      const own = dictionary(l)
      expect(en.filter((k) => !(k in own)), l).toEqual([])
    }
  })
  it('шесть языков в порядке списка', () => {
    expect(LANGS).toEqual(['ru', 'en', 'uk', 'es', 'de', 'pl'])
  })
  it('польское множественное: 1 / 2–4 / 5+ (12–14 — как 5)', () => {
    expect([1, 2, 4, 5, 12, 14, 22, 25, 101, 102].map(plPlural)).toEqual([0, 1, 1, 2, 2, 2, 1, 2, 2, 1])
  })
  it('es / de / pl: свой перевод, формы числа и запасной английский', () => {
    current = 'de'
    expect(t('Язык')).toBe(dictionary('de')['Язык'])
    expect(t('Строки нет в словаре')).toBe('Строки нет в словаре')
    current = 'pl'
    const key = Object.keys(dictionary('pl')).find((k) => k.split('|').length === 3)!
    const [a, b, c] = dictionary('pl')[key].split('|')
    const forms = key.split('|') as [string, string, string]
    expect([1, 3, 7].map((n) => tn(n, forms))).toEqual([a, b, c])
  })
})
