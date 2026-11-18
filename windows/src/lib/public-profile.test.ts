import { describe, expect, it } from 'vitest'
import type { ArtistStat, ListTrack, Playlist, Stats, Track } from './api'
import {
  buildPublicProfile,
  formatHours,
  hoursPluralCount,
  profileInitial,
  profileUrl,
  PROFILE_ARTISTS_SHOWN,
  PROFILE_LIKES_SHOWN,
  PROFILE_PLAYLISTS_SHOWN,
} from './public-profile'
import { SITE_URL } from './site'

const track = (n: number): Track => ({
  ref: `sc:${n}`,
  title: `Трек ${n}`,
  artist: `Артист ${n}`,
  artists: [],
  album: null,
  duration_ms: 180_000 + n,
  cover_url: n % 2 ? `https://img/${n}.jpg` : null,
  url: null,
  explicit: false,
  available: true,
})

const liked = (n: number): ListTrack => ({ ...track(n), item_id: `it_${n}`, added_at: 1_700_000_000_000 + n })

const playlist = (n: number, extra: Partial<Playlist> = {}): Playlist => ({
  id: `pl_${n}`,
  name: `Плейлист ${n}`,
  hidden: false,
  source_ref: null,
  created_at: 1,
  updated_at: 2,
  track_count: n,
  duration_ms: n * 60_000,
  covers: ['a', 'b', 'c', 'd', 'e'],
  tracks: null,
  ...extra,
})

const artist = (n: number): ArtistStat => ({ name: `А${n}`, avatar_url: null, ref: `sca:${n}`, ms: 1000 * n, plays: n })

const stats = (extra: Partial<Stats> = {}): Stats => ({
  period: 'all',
  total_ms: 7_200_000,
  delta_pct: null,
  buckets: [],
  top_artist: artist(1),
  more_artists: [2, 3, 4, 5, 6, 7, 8].map(artist),
  top_tracks: [],
  plays: 42,
  tracks: 30,
  artists: 12,
  streak_days: 3,
  peak_hour: 21,
  per_day: 5,
  fav_weekday: 4,
  ...extra,
})

const base = { name: '', username: '', avatar: '' }

describe('profileUrl', () => {
  it('ссылка на сайт с @username', () => {
    expect(profileUrl('folzy')).toBe(`${SITE_URL}/@folzy`)
    expect(profileUrl('@folzy')).toBe('https://sonar.folzy.ru/@folzy')
  })

  it('чистит «@», пробелы и регистр, как поле @username', () => {
    expect(profileUrl('  @Folzy_1 ')).toBe('https://sonar.folzy.ru/@folzy_1')
  })

  it('нет @username или он с ошибкой — ссылки нет', () => {
    expect(profileUrl('')).toBeNull()
    expect(profileUrl('ab')).toBeNull()
    expect(profileUrl('имя')).toBeNull()
    expect(profileUrl('a'.repeat(33))).toBeNull()
    expect(profileUrl('bad name')).toBeNull()
  })
})

describe('buildPublicProfile', () => {
  it('шапка из профиля в настройках', () => {
    const p = buildPublicProfile({ name: '  Folzy ', username: '@Folzy', avatar: 'data:image/webp;base64,AA' })
    expect(p.display_name).toBe('Folzy')
    expect(p.username).toBe('folzy')
    expect(p.avatar_url).toBe('data:image/webp;base64,AA')
    // номер и дата регистрации — только с сервера
    expect(p.number).toBeNull()
    expect(p.created_at).toBeNull()
  })

  it('пустой профиль — без имени и аватара: аккаунт SoundCloud / Яндекса гость не видит', () => {
    const p = buildPublicProfile({ ...base, name: '   ' })
    expect(p.display_name).toBe('')
    expect(p.avatar_url).toBeNull()
    expect(Object.keys(p)).not.toContain('account')
  })

  it('ничего нет — пустое имя, без аватара и @username', () => {
    const p = buildPublicProfile({ ...base, username: 'x y' })
    expect(p.display_name).toBe('')
    expect(p.avatar_url).toBeNull()
    expect(p.username).toBeNull()
    expect(p.stats).toBeNull()
    expect(p.top_artists).toEqual([])
    expect(p.likes).toEqual({ count: 0, tracks: [] })
    expect(p.playlists).toEqual([])
    expect(p.playlist_count).toBe(0)
    expect(p.now_playing).toBeNull()
  })

  it('Любимые: число — все, треки — первые по порядку, только публичные поля', () => {
    const favorites = Array.from({ length: PROFILE_LIKES_SHOWN + 5 }, (_, i) => liked(i))
    const p = buildPublicProfile({ ...base, favorites })
    expect(p.likes.count).toBe(PROFILE_LIKES_SHOWN + 5)
    expect(p.likes.tracks).toHaveLength(PROFILE_LIKES_SHOWN)
    expect(p.likes.tracks[0]).toEqual({ ref: 'sc:0', title: 'Трек 0', artist: 'Артист 0', cover_url: null, duration_ms: 180_000 })
    expect(Object.keys(p.likes.tracks[1])).not.toContain('item_id')
  })

  it('плейлисты: все, включая скрытые из «Все» (приватности пока нет), до лимита; коллаж — 4 обложки', () => {
    const playlists = Array.from({ length: PROFILE_PLAYLISTS_SHOWN + 2 }, (_, i) => playlist(i, { hidden: i === 0 }))
    const p = buildPublicProfile({ ...base, playlists })
    expect(p.playlist_count).toBe(PROFILE_PLAYLISTS_SHOWN + 2)
    expect(p.playlists).toHaveLength(PROFILE_PLAYLISTS_SHOWN)
    expect(p.playlists[0]).toEqual({ id: 'pl_0', name: 'Плейлист 0', track_count: 0, duration_ms: 0, covers: ['a', 'b', 'c', 'd'] })
  })

  it('статистика и любимые артисты из plays', () => {
    const p = buildPublicProfile({ ...base, stats: stats() })
    expect(p.stats).toEqual({ plays: 42, total_ms: 7_200_000, tracks: 30, artists: 12, streak_days: 3 })
    expect(p.top_artists).toHaveLength(PROFILE_ARTISTS_SHOWN)
    expect(p.top_artists[0]).toEqual({ name: 'А1', avatar_url: null, ref: 'sca:1', plays: 1 })
  })

  it('без прослушиваний статистики и артистов нет', () => {
    const p = buildPublicProfile({ ...base, stats: stats({ plays: 0, top_artist: null, more_artists: [] }) })
    expect(p.stats).toBeNull()
    expect(p.top_artists).toEqual([])
  })

  it('нет главного артиста — берутся остальные', () => {
    const p = buildPublicProfile({ ...base, stats: stats({ top_artist: null, more_artists: [artist(9)] }) })
    expect(p.top_artists.map((a) => a.name)).toEqual(['А9'])
  })

  it('сейчас играет — текущий трек', () => {
    const p = buildPublicProfile({ ...base, current: track(7), playing: true })
    expect(p.now_playing?.ref).toBe('sc:7')
    expect(p.now_playing?.cover_url).toBe('https://img/7.jpg')
  })

  it('трек на паузе или восстановленный при запуске — «Сейчас слушает» нет', () => {
    expect(buildPublicProfile({ ...base, current: track(7), playing: false }).now_playing).toBeNull()
    expect(buildPublicProfile({ ...base, current: track(7) }).now_playing).toBeNull()
  })

  it('артисты с одинаковым ref (Яндекс «A» и «A, B») остаются оба, имена разные', () => {
    const solo: ArtistStat = { name: 'A', avatar_url: null, ref: 'yma:1', ms: 9000, plays: 9 }
    const feat: ArtistStat = { name: 'A, B', avatar_url: null, ref: 'yma:1', ms: 5000, plays: 5 }
    const p = buildPublicProfile({ ...base, stats: stats({ top_artist: solo, more_artists: [feat] }) })
    const names = p.top_artists.map((a) => a.name)
    expect(names).toEqual(['A', 'A, B'])
    // список на странице ключуется по имени — оно уникально, ref нет
    expect(new Set(names).size).toBe(names.length)
  })
})

describe('часы музыки', () => {
  it('до 10 — с одной цифрой после точки, дальше целыми', () => {
    expect(formatHours(1.44)).toBe('1.4')
    expect(formatHours(0)).toBe('0.0')
    expect(formatHours(12.6)).toBe('13')
  })

  it('дробное число — форма как у 2 («1.4 часа», «1.4 hours»), целое — по самому числу', () => {
    expect(hoursPluralCount(1.4)).toBe(2)
    expect(hoursPluralCount(0.6)).toBe(2)
    expect(hoursPluralCount(1)).toBe(2) // «1.0» — тоже дробь
    expect(hoursPluralCount(21.2)).toBe(21)
    expect(hoursPluralCount(11)).toBe(11)
  })
})

describe('profileInitial', () => {
  it('первая буква имени, потом @username, потом S', () => {
    expect(profileInitial({ display_name: 'фолзи', username: 'folzy' })).toBe('Ф')
    expect(profileInitial({ display_name: ' ', username: 'folzy' })).toBe('F')
    expect(profileInitial({ display_name: '', username: null })).toBe('S')
  })
})

describe('приватность профиля', () => {
  const base = {
    name: 'Folzy',
    username: 'folzy',
    avatar: '',
    favorites: [liked(1), liked(2)],
    playlists: [playlist(1), playlist(2, { hidden: true })],
    stats: stats(),
    current: track(9),
    playing: true,
  }

  it('без настроек видно всё', () => {
    const p = buildPublicProfile(base)
    expect(p.likes.count).toBe(2)
    expect(p.playlist_count).toBe(2)
    expect(p.now_playing?.ref).toBe('sc:9')
  })

  it('скрытое гостю не уходит', () => {
    const p = buildPublicProfile({ ...base, privacy: { now_playing: false, stats: false, likes: false, playlists: 'none' } })
    expect(p.now_playing).toBeNull()
    expect(p.stats).toBeNull()
    expect(p.top_artists).toEqual([])
    expect(p.likes).toEqual({ count: 0, tracks: [] })
    expect(p.playlists).toEqual([])
    expect(p.playlist_count).toBe(0)
  })

  it('«Кроме скрытых» прячет плейлисты, скрытые из «Все»', () => {
    const p = buildPublicProfile({ ...base, privacy: { now_playing: true, stats: true, likes: true, playlists: 'visible' } })
    expect(p.playlists.map((x) => x.id)).toEqual(['pl_1'])
    expect(p.playlist_count).toBe(1)
  })
})
