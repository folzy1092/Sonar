import { describe, expect, it } from 'vitest'
import type { Recap, RecapPeriods, TrackStat } from './api'
import {
  buildCards,
  coverOf,
  ellipsize,
  imageName,
  inviteFor,
  markSeen,
  MAX_SEEN,
  seenIds,
  keyMove,
  MIN_INVITE_MS,
  partOfDay,
  readableOn,
  recapColors,
  recapId,
  step,
  WHEEL_GAP_MS,
  wheelMove,
  wrapLines,
} from './recap-core'

const track = (ref: string, cover: string | null = null): TrackStat => ({
  ref,
  title: `T ${ref}`,
  artist: 'A',
  cover_url: cover,
  plays: 3,
  ms: 600_000,
})

function recap(over: Partial<Recap> = {}): Recap {
  return {
    kind: 'month',
    year: 2026,
    month: 11,
    total_ms: 3_600_000,
    plays: 40,
    tracks: 20,
    artists: 8,
    active_days: 12,
    delta_pct: 15,
    top_tracks: [track('sc:1', 'https://img/1.jpg'), track('ym:2')],
    top_artists: [{ name: 'A', avatar_url: null, ref: null, ms: 1000, plays: 3 }],
    new_artist: { artist: { name: 'N', avatar_url: null, ref: null, ms: 500, plays: 1 }, first_played: '2026-11-10' },
    hours: Array.from({ length: 24 }, (_, h) => (h === 21 ? 9000 : 10)),
    peak_hour: 21,
    longest_day: { date: '2026-11-03', ms: 7_200_000, plays: 30 },
    repeat: { track: track('sc:1'), count: 5, date: '2026-11-03' },
    services: [
      { service: 'sc', ms: 2000, pct: 67 },
      { service: 'ym', ms: 1000, pct: 33 },
    ],
    ...over,
  }
}

const periods = (over: Partial<RecapPeriods> = {}): RecapPeriods => ({
  months: [
    { kind: 'month', year: 2026, month: 10, total_ms: MIN_INVITE_MS },
    { kind: 'month', year: 2026, month: 3, total_ms: MIN_INVITE_MS - 1 },
    { kind: 'month', year: 2025, month: 12, total_ms: MIN_INVITE_MS * 10 },
  ],
  years: [
    { kind: 'year', year: 2026, month: null, total_ms: MIN_INVITE_MS * 20 },
    { kind: 'year', year: 2025, month: null, total_ms: MIN_INVITE_MS * 10 },
  ],
  ...over,
})

describe('recapId', () => {
  it('builds stable ids for months and years', () => {
    expect(recapId({ kind: 'month', year: 2026, month: 3 })).toBe('month-2026-03')
    expect(recapId({ kind: 'year', year: 2026, month: null })).toBe('year-2026')
  })
})

describe('inviteFor', () => {
  it('invites to the previous month during the first week', () => {
    expect(inviteFor(new Date(2026, 10, 1), periods(), null)).toEqual({ kind: 'month', year: 2026, month: 10 })
    expect(inviteFor(new Date(2026, 10, 7, 23), periods(), null)).toEqual({ kind: 'month', year: 2026, month: 10 })
  })

  it('stays quiet in the middle of a month', () => {
    expect(inviteFor(new Date(2026, 10, 8), periods(), null)).toBeNull()
  })

  it('invites to the whole year all December and in early January', () => {
    expect(inviteFor(new Date(2026, 11, 20), periods(), null)).toEqual({ kind: 'year', year: 2026, month: null })
    expect(inviteFor(new Date(2026, 0, 3), periods(), null)).toEqual({ kind: 'year', year: 2025, month: null })
  })

  it('skips a recap already seen or too short', () => {
    expect(inviteFor(new Date(2026, 10, 2), periods(), 'month-2026-10')).toBeNull()
    expect(inviteFor(new Date(2026, 3, 2), periods(), null)).toBeNull()
    expect(inviteFor(new Date(2026, 5, 2), periods(), null)).toBeNull()
    expect(inviteFor(new Date(2026, 11, 20), periods({ years: [] }), null)).toBeNull()
  })

  it('remembers several seen recaps, so opening an old one does not bring the invite back', () => {
    const seen = markSeen(markSeen('', 'month-2026-10'), 'month-2025-12')
    expect(inviteFor(new Date(2026, 10, 2), periods(), seen)).toBeNull()
  })

  it('offers the previous month in early December and January once the year is seen', () => {
    const base = periods()
    const withNov = periods({ months: [{ kind: 'month', year: 2026, month: 11, total_ms: MIN_INVITE_MS }, ...base.months] })
    expect(inviteFor(new Date(2026, 11, 2), withNov, null)).toEqual({ kind: 'year', year: 2026, month: null })
    expect(inviteFor(new Date(2026, 11, 2), withNov, 'year-2026')).toEqual({ kind: 'month', year: 2026, month: 11 })
    expect(inviteFor(new Date(2026, 11, 2), withNov, 'year-2026,month-2026-11')).toBeNull()
    expect(inviteFor(new Date(2026, 11, 2), base, 'year-2026')).toBeNull()
    expect(inviteFor(new Date(2026, 0, 3), periods(), 'year-2025')).toEqual({ kind: 'month', year: 2025, month: 12 })
    expect(inviteFor(new Date(2026, 11, 20), withNov, 'year-2026')).toBeNull()
  })
})

describe('seenIds / markSeen', () => {
  it('reads the old single-id value and empty input', () => {
    expect(seenIds('month-2026-10')).toEqual(['month-2026-10'])
    expect(seenIds('')).toEqual([])
    expect(seenIds(null)).toEqual([])
    expect(seenIds(' a , ,b ')).toEqual(['a', 'b'])
  })

  it('appends without duplicates and keeps only the latest ids', () => {
    expect(markSeen('a,b', 'a')).toBe('b,a')
    expect(markSeen('', 'year-2026')).toBe('year-2026')
    let raw = ''
    for (let i = 0; i < MAX_SEEN + 5; i++) raw = markSeen(raw, `id-${i}`)
    const ids = seenIds(raw)
    expect(ids).toHaveLength(MAX_SEEN)
    expect(ids[0]).toBe('id-5')
    expect(ids.at(-1)).toBe(`id-${MAX_SEEN + 4}`)
  })
})

describe('buildCards', () => {
  it('lists every card in order when there is data', () => {
    expect(buildCards(recap()).map((c) => c.kind)).toEqual([
      'intro',
      'minutes',
      'tracks',
      'artists',
      'new_artist',
      'hour',
      'day',
      'repeat',
      'services',
    ])
  })

  it('rounds minutes and carries the delta', () => {
    const minutes = buildCards(recap({ total_ms: 89_999 })).find((c) => c.kind === 'minutes')
    expect(minutes).toEqual({ kind: 'minutes', minutes: 1, delta: 15, days: 12, plays: 40 })
  })

  it('skips cards without data', () => {
    const cards = buildCards(
      recap({ top_artists: [], new_artist: null, peak_hour: null, longest_day: null, repeat: null, services: [] }),
    )
    expect(cards.map((c) => c.kind)).toEqual(['intro', 'minutes', 'tracks'])
  })

  it('returns nothing for an empty period', () => {
    expect(buildCards(recap({ total_ms: 0 }))).toEqual([])
  })
})

describe('coverOf', () => {
  it('takes the first cover of the top, then the repeat track', () => {
    expect(coverOf(recap())).toBe('https://img/1.jpg')
    const r = recap({ top_tracks: [track('sc:9')], repeat: { track: track('sc:8', 'https://img/8.jpg'), count: 3, date: '2026-11-01' } })
    expect(coverOf(r)).toBe('https://img/8.jpg')
    expect(coverOf(recap({ top_tracks: [], repeat: null }))).toBeNull()
  })
})

describe('navigation', () => {
  it('clamps steps to the deck', () => {
    expect(step(0, -1, 5)).toBe(0)
    expect(step(4, 1, 5)).toBe(4)
    expect(step(2, 1, 5)).toBe(3)
    expect(step(3, 0, 0)).toBe(0)
  })

  it('maps keys to moves', () => {
    expect(keyMove('ArrowRight')).toBe(1)
    expect(keyMove(' ')).toBe(1)
    expect(keyMove('PageUp')).toBe(-1)
    expect(keyMove('Home')).toBe('first')
    expect(keyMove('End')).toBe('last')
    expect(keyMove('a')).toBeNull()
  })

  it('turns one wheel gesture into one move', () => {
    expect(wheelMove(120, 0, 1000, 0)).toBe(1)
    expect(wheelMove(-120, 0, 1000, 0)).toBe(-1)
    expect(wheelMove(0, 60, 1000, 0)).toBe(1)
    expect(wheelMove(120, 0, 1000, 1000 - WHEEL_GAP_MS + 1)).toBe(0)
    expect(wheelMove(2, 1, 1000, 0)).toBe(0)
  })
})

describe('recapColors', () => {
  it('keeps text readable for any cover', () => {
    const covers: ([number, number, number] | null)[] = [null, [255, 0, 0], [250, 240, 20], [10, 10, 10], [255, 255, 255], [0, 140, 255]]
    for (const c of covers) expect(readableOn(recapColors(c))).toBe(true)
  })

  it('follows the cover hue', () => {
    const red = recapColors([220, 30, 30])
    const blue = recapColors([30, 60, 220])
    expect(red.accent[0]).toBeGreaterThan(red.accent[2])
    expect(blue.accent[2]).toBeGreaterThan(blue.accent[0])
  })
})

describe('wrapLines', () => {
  const measure = (s: string) => s.length

  it('wraps by words', () => {
    expect(wrapLines('one two three four', 9, measure, 3)).toEqual(['one two', 'three', 'four'])
  })

  it('ellipsizes what does not fit', () => {
    expect(wrapLines('one two three four', 9, measure, 2)).toEqual(['one two', 'three…'])
    expect(wrapLines('supercalifragilistic', 6, measure, 2)).toEqual(['super…'])
    expect(wrapLines('   ', 6, measure, 2)).toEqual([])
  })

  it('ellipsize leaves short text alone', () => {
    expect(ellipsize('ok', 5, measure)).toBe('ok')
    expect(ellipsize('toolong', 5, measure)).toBe('tool…')
  })
})

describe('misc', () => {
  it('names image files by period, position and kind', () => {
    expect(imageName({ kind: 'month', year: 2026, month: 11 }, 2, 'tracks')).toBe('Sonar month-2026-11 03-tracks')
  })

  it('splits the day into four parts', () => {
    expect([0, 5, 6, 11, 12, 17, 18, 23, 24].map(partOfDay)).toEqual([0, 0, 1, 1, 2, 2, 3, 3, 0])
  })
})
