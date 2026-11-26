import { describe, expect, it } from 'vitest'
import { formatDuration, hasContent, listenParts, profileHandle, readProfile, safeImage } from './profile'

const EMPTY = {
  nowPlaying: null,
  stats: null,
  topArtists: [],
  likes: null,
  playlists: null,
  playlistCount: 0,
  showcase: [],
  private: [],
}

describe('readProfile', () => {
  it('reads a bare profile header', () => {
    const r = readProfile(200, { username: 'mira', display_name: ' Мира ', number: 7, created_at: 1_700_000_000_000 }, 'mira')
    expect(r).toEqual({
      kind: 'found',
      profile: { username: 'mira', displayName: 'Мира', number: 7, createdAt: 1_700_000_000_000, ...EMPTY },
    })
    if (r.kind === 'found') {
      expect(profileHandle(r.profile)).toBe('@mira · #7')
      expect(hasContent(r.profile)).toBe(false)
    }
  })

  it('reads the open sections', () => {
    const r = readProfile(
      200,
      {
        username: 'nika',
        now_playing: { ref: 'sc:2', title: 'новый', artist: 'одиссея', cover_url: null, duration_ms: 93000 },
        stats: { plays: 5, total_ms: 300_000, tracks: 3, artists: 2, streak_days: 3 },
        top_artists: [{ name: 'одиссея', plays: 3 }, { name: '' }],
        likes: { count: 2, tracks: [{ ref: 'sc:2', title: 'новый', cover_url: 'https://i1.sndcdn.com/a.jpg' }, { title: '' }] },
        playlists: [{ id: 'pl_a', name: 'Ночь', track_count: 3, duration_ms: 3000, covers: ['https://c/1', 'javascript:x'] }],
        playlist_count: 1,
        showcase: [{ kind: 'track', ref: 'sc:2', title: 'новый', cover_url: 'data:x' }],
        private: ['stats', 'junk'],
      },
      'nika',
    )
    if (r.kind !== 'found') throw new Error(r.kind)
    const p = r.profile
    expect(p.nowPlaying).toEqual({ ref: 'sc:2', title: 'новый', artist: 'одиссея', coverUrl: null, durationMs: 93000 })
    expect(p.stats?.streakDays).toBe(3)
    expect(p.topArtists).toEqual([{ name: 'одиссея', plays: 3 }])
    expect(p.likes?.count).toBe(2)
    expect(p.likes?.tracks.map((t) => t.coverUrl)).toEqual(['https://i1.sndcdn.com/a.jpg'])
    expect(p.playlists?.[0].covers).toEqual(['https://c/1'])
    expect(p.showcase[0].coverUrl).toBeNull()
    expect(p.private).toEqual(['stats'])
    expect(hasContent(p)).toBe(true)
  })

  it('drops zeroed sections instead of drawing zeros', () => {
    const r = readProfile(200, { stats: { plays: 0 }, likes: { count: 0, tracks: [] }, playlists: [] }, 'zero')
    if (r.kind !== 'found') throw new Error(r.kind)
    expect([r.profile.stats, r.profile.likes, r.profile.playlists]).toEqual([null, null, null])
    expect(hasContent(r.profile)).toBe(false)
  })

  it('treats 404 as a missing profile', () => {
    expect(readProfile(404, { error: 'not_found' }, 'mira')).toEqual({ kind: 'missing' })
  })

  it('treats other statuses and junk bodies as an error', () => {
    expect(readProfile(500, {}, 'mira').kind).toBe('error')
    expect(readProfile(200, null, 'mira').kind).toBe('error')
    expect(readProfile(200, 'oops', 'mira').kind).toBe('error')
    expect(readProfile(200, [], 'mira').kind).toBe('error')
  })

  it('falls back on junk fields instead of breaking', () => {
    const r = readProfile(200, { display_name: '', number: -1, created_at: 'x', top_artists: 'x', showcase: {} }, 'mira')
    expect(r).toEqual({
      kind: 'found',
      profile: { username: 'mira', displayName: 'mira', number: null, createdAt: null, ...EMPTY },
    })
    if (r.kind === 'found') expect(profileHandle(r.profile)).toBe('@mira')
  })
})

describe('helpers', () => {
  it('lets only https images through', () => {
    expect(safeImage('https://i.scdn.co/a.jpg')).toBe('https://i.scdn.co/a.jpg')
    expect(safeImage('http://x/a.jpg')).toBeNull()
    expect(safeImage('javascript:alert(1)')).toBeNull()
    expect(safeImage('https://x/"onerror=')).toBeNull()
  })

  it('formats durations', () => {
    expect(formatDuration(93_000)).toBe('1:33')
    expect(formatDuration(3_725_000)).toBe('1:02:05')
  })

  it('shows listening time in hours or minutes', () => {
    expect(listenParts(300_000)).toEqual({ unit: 'min', n: 5 })
    expect(listenParts(10_000)).toEqual({ unit: 'min', n: 1 })
    expect(listenParts(7_300_000)).toEqual({ unit: 'h', n: 2 })
  })
})
