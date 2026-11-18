import { describe, expect, it } from 'vitest'
import type { Track } from './api'
import { mergeMore, mergeTracks, normalizeName, searchOrder, serviceOfRef, trackKey } from './unified-search'

const tr = (ref: string, title: string, artist: string, duration_ms = 200_000): Track =>
  ({ ref, title, artist, artists: [], album: null, duration_ms, cover_url: null, url: null, explicit: false, available: true }) as Track

describe('unified search', () => {
  it('ставит предпочтительный сервис первым, остальные — по резерву', () => {
    expect(searchOrder('yt', ['ym', 'sc'])[0]).toBe('yt')
    expect(searchOrder('yt', ['ym', 'sc']).slice(1, 3)).toEqual(['ym', 'sc'])
    expect(searchOrder('nope', [])[0]).toBe('sc')
    expect(new Set(searchOrder('sc', ['sc', 'sc'])).size).toBe(searchOrder('sc', []).length)
  })

  it('нормализует названия', () => {
    expect(normalizeName('Ёлка (feat. Кто-то) ')).toBe('елка')
    expect(trackKey({ title: 'Song - Remix', artist: 'A, B' })).toBe(trackKey({ title: 'song  remix', artist: 'A & C' }))
  })

  it('склеивает один трек из разных сервисов, оставляя версию сервиса выше', () => {
    const merged = mergeTracks(
      {
        sc: [tr('sc:1', 'Song', 'Artist'), tr('sc:2', 'Other', 'X')],
        ym: [tr('ym:1', 'song (feat. Y)', 'Artist', 203_000), tr('ym:2', 'Only Yandex', 'Z')],
      },
      ['ym', 'sc'],
    )
    expect(merged.map((t) => t.ref)).toEqual(['ym:1', 'ym:2', 'sc:2'])
  })

  it('разная длительность — разные треки (live, extended)', () => {
    const merged = mergeTracks({ sc: [tr('sc:1', 'Song', 'A', 200_000)], ym: [tr('ym:1', 'Song', 'A', 400_000)] }, ['sc', 'ym'])
    expect(merged).toHaveLength(2)
  })

  it('сливает артистов по имени', () => {
    const a = (ref: string, name: string) => ({ ref, name, avatar_url: null, followers: null, url: null })
    const m = mergeMore(
      { sc: { artists: [a('sca:1', 'Artist')], albums: [], playlists: [] }, ym: { artists: [a('yma:1', 'artist'), a('yma:2', 'B')], albums: [], playlists: [] } },
      ['ym', 'sc'],
    )
    expect(m.artists.map((x) => x.ref)).toEqual(['yma:1', 'yma:2'])
  })

  it('узнаёт сервис по ref', () => {
    expect(serviceOfRef('ym:5')).toBe('ym')
    expect(serviceOfRef('???:1')).toBeNull()
  })
})
