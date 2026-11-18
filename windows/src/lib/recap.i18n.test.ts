import { describe, expect, it, vi } from 'vitest'
import type { Recap } from './api'

let current = 'ru'
vi.mock('./settings.svelte', () => ({ settings: { get: () => current } }))

const { dictionary } = await import('./i18n.svelte')
const { buildCards } = await import('./recap-core')
const { cardText, periodTitle, recapKindTitle } = await import('./recap-text')
const en = (await import('../i18n/en/recap')).default
const uk = (await import('../i18n/uk/recap')).default

const CYRILLIC = /[А-Яа-яЁёІіЇїЄєҐґ]/
const UK_ONLY = /[ІіЇїЄєҐґ']/

const sample: Recap = {
  kind: 'month',
  year: 2026,
  month: 11,
  total_ms: 5_400_000,
  plays: 42,
  tracks: 20,
  artists: 9,
  active_days: 11,
  delta_pct: -12,
  top_tracks: [{ ref: 'sc:1', title: 'Song', artist: 'Band', cover_url: null, plays: 7, ms: 900_000 }],
  top_artists: [{ name: 'Band', avatar_url: null, ref: null, ms: 900_000, plays: 7 }],
  new_artist: { artist: { name: 'Fresh', avatar_url: null, ref: null, ms: 300_000, plays: 2 }, first_played: '2026-11-05' },
  hours: Array.from({ length: 24 }, (_, h) => h * 1000),
  peak_hour: 23,
  longest_day: { date: '2026-11-03', ms: 7_260_000, plays: 31 },
  repeat: { track: { ref: 'sc:1', title: 'Song', artist: 'Band', cover_url: null, plays: 7, ms: 900_000 }, count: 4, date: '2026-11-03' },
  services: [{ service: 'sc', ms: 5_400_000, pct: 100 }],
}

/** Весь текст карточек итогов на текущем языке (имена треков и артистов — латиницей). */
function allText(): string[] {
  const ref = { kind: sample.kind, year: sample.year, month: sample.month }
  const year = { kind: 'year' as const, year: 2026, month: null }
  const cards = buildCards(sample).flatMap((c) => {
    const x = cardText(c, ref)
    return [x.eyebrow, x.title, x.unit, ...x.lines]
  })
  return [...cards, periodTitle(ref), recapKindTitle(ref), recapKindTitle(year), cardText({ kind: 'intro' }, year).lines[0]]
}

describe('переводы итогов', () => {
  it.each(['en', 'uk'] as const)('%s: на карточках не остаётся русского', (l) => {
    current = l
    const text = allText()
    if (l === 'en') expect(text.filter((s) => CYRILLIC.test(s))).toEqual([])
    else expect(text.join(' ')).toMatch(UK_ONLY)
    current = 'ru'
  })

  it('en и uk переводят одни и те же строки', () => {
    expect(Object.keys(uk).sort()).toEqual(Object.keys(en).sort())
  })

  it('месяцы и множественное число — по форме языка', () => {
    expect(en['Январь|Февраль|Март|Апрель|Май|Июнь|Июль|Август|Сентябрь|Октябрь|Ноябрь|Декабрь'].split('|')).toHaveLength(12)
    expect(uk['Январь|Февраль|Март|Апрель|Май|Июнь|Июль|Август|Сентябрь|Октябрь|Ноябрь|Декабрь'].split('|')).toHaveLength(12)
    expect(en['раз за день|раза за день|раз за день'].split('|')).toHaveLength(2)
    expect(uk['раз за день|раза за день|раз за день'].split('|')).toHaveLength(3)
  })

  it('строки итогов попадают в общий словарь', () => {
    for (const l of ['en', 'uk'] as const) {
      const dict = dictionary(l)
      expect(Object.keys(en).filter((k) => !dict[k]?.trim())).toEqual([])
    }
  })

  it('по-английски период и подписи читаются', () => {
    current = 'en'
    expect(periodTitle({ kind: 'month', year: 2026, month: 11 })).toBe('November 2026')
    expect(cardText({ kind: 'repeat', track: sample.repeat!.track, count: 4, date: '2026-11-03' }, { kind: 'month', year: 2026, month: 11 }).unit).toBe(
      'times in one day',
    )
    current = 'ru'
  })
})
