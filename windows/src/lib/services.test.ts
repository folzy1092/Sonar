import { describe, expect, it } from 'vitest'
import type { ServiceState } from './api'
import {
  ACCOUNT_SERVICES,
  IMPLEMENTED,
  isLocalRef,
  SERVICES,
  byId,
  connected,
  isTrackRef,
  parseRef,
  playlistWebUrl,
  refKind,
  serviceOf,
  statusOf,
  type RefKind,
  type ServiceId,
  type ServiceInfo,
} from './services'

// §1.2: порядок строк — порядок показа.
const TABLE = [
  { id: 'sc', key: 'soundcloud', name: 'SoundCloud', short: 'SC', color: '#FF5500', pre: ['sc', 'scalb', 'sca', 'scpl'], caps: '1111111', implemented: true },
  { id: 'ym', key: 'yandex', name: 'Яндекс Музыка', short: 'Я', color: '#FFBC0D', pre: ['ym', 'ymalb', 'yma', 'ympl'], caps: '1111111', implemented: true },
  { id: 'yt', key: 'youtube', name: 'YouTube Music', short: 'YT', color: '#FF0033', pre: ['yt', 'ytalb', 'yta', 'ytpl'], caps: '1111110', implemented: false },
  { id: 'vk', key: 'vk', name: 'VK Музыка', short: 'VK', color: '#0077FF', pre: ['vk', 'vkalb', 'vka', 'vkpl'], caps: '1111111', implemented: false },
  { id: 'sp', key: 'spotify', name: 'Spotify', short: 'SP', color: '#1ED760', pre: ['sp', 'spalb', 'spa', 'sppl'], caps: '1011110', implemented: false },
  { id: 'local', key: 'local', name: 'Локальные файлы', short: '♪', color: '#8E8E93', pre: ['local', null, null, null], caps: '0110000', implemented: true },
] as const

const capsString = (s: ServiceInfo) =>
  [s.caps.search, s.caps.stream, s.caps.library, s.caps.playlists, s.caps.similar, s.caps.login, s.caps.key].map((c) => (c ? '1' : '0')).join('')

// §1.3: ref → (сервис, вид).
const EXAMPLES: [string, ServiceId | null, RefKind | null][] = [
  ['sc:123', 'sc', 'track'],
  ['scalb:9', 'sc', 'album'],
  ['sca:7', 'sc', 'artist'],
  ['scpl:likes', 'sc', 'playlist'],
  ['ympl:42:1003', 'ym', 'playlist'],
  ['ymalb:5', 'ym', 'album'],
  ['yma:1', 'ym', 'artist'],
  ['yt:abc', 'yt', 'track'],
  ['local:abc', 'local', 'track'],
  ['pl_x', null, null],
  ['similar:sc:1', null, null],
  ['sc', null, null],
  ['', null, null],
  [':1', null, null],
]

const row = (id: ServiceId, isConnected: boolean): ServiceState => {
  const s = byId(id)!
  return {
    id: s.id,
    key: s.key,
    name: s.name,
    color: s.color,
    icon: null,
    icon_mono: null,
    prefixes: s.prefixes,
    caps: s.caps,
    implemented: s.implemented,
    connected: isConnected,
    account_name: null,
    avatar_url: null,
    premium: null,
  }
}

describe('реестр сервисов', () => {
  it('строки в порядке таблицы, поля совпадают с §1.2', () => {
    expect(SERVICES.map((s) => s.id)).toEqual(TABLE.map((r) => r.id))
    SERVICES.forEach((s, i) => {
      const r = TABLE[i]
      expect(s.key, s.id).toBe(r.key)
      expect(s.name, s.id).toBe(r.name)
      expect(s.short, s.id).toBe(r.short)
      expect(s.color, s.id).toBe(r.color)
      expect([s.prefixes.track, s.prefixes.album, s.prefixes.artist, s.prefixes.playlist], s.id).toEqual(r.pre)
      expect(capsString(s), s.id).toBe(r.caps)
      expect(s.implemented, s.id).toBe(r.implemented)
    })
  })

  it('цвета — hex в верхнем регистре', () => {
    for (const s of SERVICES) expect(s.color).toMatch(/^#[0-9A-F]{6}$/)
  })

  it('префиксы всех сервисов попарно различны', () => {
    const all = SERVICES.flatMap((s) => Object.values(s.prefixes)).filter((p): p is string => p !== null)
    expect(new Set(all).size).toBe(all.length)
  })

  it('реестр заморожен', () => {
    expect(Object.isFrozen(SERVICES)).toBe(true)
    expect(Object.isFrozen(IMPLEMENTED)).toBe(true)
  })
})

describe('parseRef / serviceOf / refKind', () => {
  it.each(EXAMPLES)('%j → %s / %s', (ref, service, kind) => {
    expect(serviceOf(ref)).toBe(service)
    expect(refKind(ref)).toBe(kind)
    const parsed = parseRef(ref)
    expect(parsed?.service.id ?? null).toBe(service)
    expect(parsed?.kind ?? null).toBe(kind)
  })

  it('каждый префикс каждого сервиса узнаётся', () => {
    for (const s of SERVICES) {
      for (const [kind, prefix] of Object.entries(s.prefixes)) {
        if (prefix === null) continue
        expect(serviceOf(`${prefix}:1`), prefix).toBe(s.id)
        expect(refKind(`${prefix}:1`), prefix).toBe(kind)
      }
    }
  })

  it('никаких startsWith: похожие префиксы не считаются', () => {
    for (const ref of ['scx:1', 'ymx:1', 'scalbum:1', 'SC:1', ' sc:1', 'yt-:1']) expect(serviceOf(ref), ref).toBeNull()
  })

  it('null и undefined — нет сервиса', () => {
    expect(serviceOf(null)).toBeNull()
    expect(serviceOf(undefined)).toBeNull()
    expect(refKind(null)).toBeNull()
    expect(parseRef(undefined)).toBeNull()
  })
})

describe('byId', () => {
  it('короткий id и длинный ключ — один сервис', () => {
    expect(byId('sc')).toBe(byId('soundcloud'))
    expect(byId('ym')).toBe(byId('yandex'))
    for (const s of SERVICES) {
      expect(byId(s.id)).toBe(s)
      expect(byId(s.key)).toBe(s)
    }
  })

  it('неизвестное и пустое — null', () => {
    expect(byId('nope')).toBeNull()
    expect(byId(null)).toBeNull()
    expect(byId(undefined)).toBeNull()
    expect(byId('')).toBeNull()
  })
})

describe('IMPLEMENTED', () => {
  it('sc, ym и локальные файлы, в порядке таблицы', () => {
    expect(IMPLEMENTED.map((s) => s.id)).toEqual(['sc', 'ym', 'local'])
  })

  it('сервисы с аккаунтом — без локальных файлов', () => {
    expect(ACCOUNT_SERVICES.map((s) => s.id)).toEqual(['sc', 'ym'])
    expect(Object.isFrozen(ACCOUNT_SERVICES)).toBe(true)
  })
})

describe('isLocalRef', () => {
  it('только local:…', () => {
    expect(isLocalRef('local:' + 'a'.repeat(40))).toBe(true)
    expect(isLocalRef('sc:1')).toBe(false)
    expect(isLocalRef('localx:1')).toBe(false)
    expect(isLocalRef(null)).toBe(false)
  })
})

describe('connected', () => {
  it('только сервисы с аккаунтом и подключённые, в порядке реестра; yt и local игнорируются', () => {
    const list = [row('yt', true), row('ym', true), row('vk', true), row('sc', true), row('local', true)]
    expect(connected(list).map((s) => s.id)).toEqual(['sc', 'ym'])
  })

  it('неподключённые отбрасываются', () => {
    expect(connected([row('sc', false), row('ym', true)]).map((s) => s.id)).toEqual(['ym'])
    expect(connected([row('sc', false), row('ym', false)])).toEqual([])
    expect(connected([])).toEqual([])
  })
})

describe('statusOf', () => {
  it('берёт статус по длинному ключу', () => {
    const sc = { connected: true, name: 'dj', avatar_url: null }
    const ym = { connected: false, name: null, avatar_url: null }
    const status = { soundcloud: sc, yandex: ym }
    expect(statusOf(status, byId('sc')!)).toBe(sc)
    expect(statusOf(status, byId('ym')!)).toBe(ym)
    expect(statusOf(status, byId('yt')!)).toBeNull()
    expect(statusOf(null, byId('sc')!)).toBeNull()
  })
})

describe('isTrackRef', () => {
  it('трек реализованного сервиса', () => {
    expect(isTrackRef('sc:1')).toBe(true)
    expect(isTrackRef('ym:1')).toBe(true)
    expect(isTrackRef('local:abc')).toBe(true)
    expect(isTrackRef('yt:1')).toBe(false)
    expect(isTrackRef('scpl:likes')).toBe(false)
    expect(isTrackRef('pl_x')).toBe(false)
    expect(isTrackRef(null)).toBe(false)
  })
})

describe('playlistWebUrl', () => {
  it('ссылки как раньше', () => {
    expect(playlistWebUrl('ympl:42:1003')).toBe('https://music.yandex.ru/users/42/playlists/1003')
    expect(playlistWebUrl('scpl:likes')).toBe('https://soundcloud.com/you/likes')
    expect(playlistWebUrl('scpl:123')).toBeNull()
    expect(playlistWebUrl('pl_x')).toBeNull()
    expect(playlistWebUrl('ympl:likes')).toBeNull()
  })
})

describe('совместимость со старой логикой', () => {
  const LEGACY = ['sc:1', 'scpl:likes', 'scalb:2', 'sca:3', 'ym:1', 'ympl:1:2', 'ymalb:2', 'yma:3']
  it.each(LEGACY)('%s', (r) => {
    expect(serviceOf(r)).toBe(r.startsWith('sc') ? 'sc' : 'ym')
    expect(refKind(r) === 'track').toBe(r.startsWith('sc:') || r.startsWith('ym:'))
  })
})
