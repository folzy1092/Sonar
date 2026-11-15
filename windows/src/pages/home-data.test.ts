import { describe, expect, it } from 'vitest'
import { daypart, releaseLabel, weekReleases } from './home-data.svelte'
import type { Album } from '../lib/api'

const album = (ref: string, released: string | null): Album =>
  ({ ref, title: ref, artist: 'A', artists: [], cover_url: null, year: 2026, released, track_count: 1, url: null }) as Album

describe('главная', () => {
  it('часть суток', () => {
    expect([4, 5, 11, 12, 17, 18, 22, 23].map(daypart)).toEqual(['night', 'morning', 'morning', 'day', 'day', 'evening', 'evening', 'night'])
  })
  it('релизы недели — последние 7 дней, без будущих и без даты', () => {
    const now = Date.parse('2026-11-15T12:00:00')
    const list = [album('a', '2026-11-15'), album('b', '2026-11-09'), album('c', '2026-11-08'), album('d', null), album('e', '2026-11-20')]
    expect(weekReleases(list, now).map((a) => a.ref)).toEqual(['a', 'b'])
  })
  it('подпись даты выхода', () => {
    const now = new Date(2026, 10, 15, 12)
    expect(releaseLabel('2026-11-15', now)).toBe('сегодня')
    expect(releaseLabel('2026-11-14', now)).toBe('вчера')
    expect(releaseLabel('2026-11-12', now)).toBe('12 ноя')
    expect(releaseLabel('2025-01-03', now)).toBe('3 янв 2025')
    expect(releaseLabel(null, now)).toBeUndefined()
  })
})
