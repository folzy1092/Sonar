import { describe, expect, it, vi } from 'vitest'
import type { MapReasons } from './api'

let current = 'ru'
vi.mock('../settings.svelte', () => ({ settings: { get: () => current } }))

const { dictionary } = await import('../i18n.svelte')
const { artistsCount, clusterTitle, strengthLabel, whyText } = await import('./why')
const en = (await import('../../i18n/en/artist-map')).default
const uk = (await import('../../i18n/uk/artist-map')).default

const CYRILLIC = /[А-Яа-яЁёІіЇїЄєҐґ]/
const UK_ONLY = /[ІіЇїЄєҐґ’]/

const reasons: MapReasons = {
  feats: 4,
  prods: 2,
  follow: 'mutual',
  common: ['Alpha', 'Beta', 'Gamma'],
  common_count: 5,
  similar: 1,
}

/** Все тексты карты на текущем языке (имена исполнителей — латиницей). */
function allText(): string[] {
  return [
    whyText(reasons, 'cowboyclicker'),
    whyText({ ...reasons, feats: 1, prods: 1, follow: 'one_way', common: ['Solo'], common_count: 1 }, 'x'),
    strengthLabel(5),
    strengthLabel(1.5),
    strengthLabel(0.3),
    clusterTitle('Band'),
    artistsCount(1),
    artistsCount(12),
  ]
}

describe('переводы карты исполнителей', () => {
  it.each(['en', 'uk'] as const)('%s: в текстах карты не остаётся русского', (l) => {
    current = l
    const text = allText()
    if (l === 'en') expect(text.filter((s) => CYRILLIC.test(s))).toEqual([])
    else expect(text.join(' ')).toMatch(UK_ONLY)
    current = 'ru'
  })

  it('en и uk переводят одни и те же строки', () => {
    expect(Object.keys(uk).sort()).toEqual(Object.keys(en).sort())
  })

  it('в en нет кириллицы, у форм числа — 2 формы в en и 3 в uk', () => {
    for (const [k, v] of Object.entries(en)) {
      expect(v, k).not.toMatch(CYRILLIC)
      if (k.split('|').length === 3) expect(v.split('|').length, k).toBe(2)
    }
    for (const [k, v] of Object.entries(uk)) {
      if (k.split('|').length === 3) expect(v.split('|').length, k).toBe(3)
    }
  })

  it('словари карты попали в общий словарь', () => {
    expect(dictionary('en')['Карта исполнителей']).toBe('Artist map')
    expect(dictionary('uk')['Карта исполнителей']).toBe('Карта виконавців')
  })

  it('русский остаётся как есть, числа — по форме языка', () => {
    current = 'ru'
    expect(artistsCount(3)).toBe('3 исполнителя')
    expect(whyText({ ...reasons, prods: 0, follow: null, common: [], common_count: 0, similar: 0 }, 'A')).toBe('4 фита с A')
    current = 'en'
    expect(artistsCount(1)).toBe('1 artist')
    expect(artistsCount(5)).toBe('5 artists')
    expect(whyText({ ...reasons, follow: null, common: [], common_count: 0, similar: 0 }, 'A')).toBe(
      '4 features with A · production on 2 tracks',
    )
    current = 'ru'
  })
})
