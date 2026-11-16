import { describe, expect, it, vi } from 'vitest'

let current = 'ru'
vi.mock('./settings.svelte', () => ({ settings: { get: () => current } }))

const { t, tn, ruPlural, dictionary } = await import('./i18n.svelte')

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
    for (const l of ['en', 'uk'] as const) {
      for (const [k, v] of Object.entries(dictionary(l))) {
        expect(v.trim(), `${l}: «${k}»`).not.toBe('')
        if (k.split('|').length === 3) expect(v.split('|').length, `${l}: «${k}»`).toBe(l === 'en' ? 2 : 3)
      }
    }
  })
})
