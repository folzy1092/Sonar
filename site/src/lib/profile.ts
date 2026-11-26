// Публичный профиль `/@username` с сервера (`GET /public/users/{username}`, API.md §1 `PublicProfile`).
// Сервер отдаёт только открытые гостю разделы; пустой раздел — `null`, скрытый — `null` и имя в `private`.
// Разбор недоверчивый: кривое поле — раздел пропадает, страница не ломается.

export const SECTIONS = ['now_playing', 'stats', 'likes', 'playlists'] as const
export type Section = (typeof SECTIONS)[number]

export interface PublicTrack {
  readonly ref: string
  readonly title: string
  readonly artist: string
  readonly coverUrl: string | null
  readonly durationMs: number | null
}

export interface ProfileStats {
  readonly plays: number
  readonly totalMs: number
  readonly tracks: number
  readonly artists: number
  readonly streakDays: number
}

export interface TopArtist {
  readonly name: string
  readonly plays: number
}

export interface PublicPlaylist {
  readonly id: string
  readonly name: string
  readonly trackCount: number
  readonly durationMs: number
  readonly covers: readonly string[]
}

export interface ShowcaseItem {
  readonly kind: string
  readonly ref: string
  readonly title: string
  readonly subtitle: string
  readonly coverUrl: string | null
}

export interface PublicProfile {
  readonly username: string
  readonly displayName: string
  readonly number: number | null
  readonly createdAt: number | null
  readonly nowPlaying: PublicTrack | null
  readonly stats: ProfileStats | null
  readonly topArtists: readonly TopArtist[]
  readonly likes: { readonly count: number; readonly tracks: readonly PublicTrack[] } | null
  readonly playlists: readonly PublicPlaylist[] | null
  readonly playlistCount: number
  readonly showcase: readonly ShowcaseItem[]
  readonly private: readonly Section[]
}

export type ProfileResult =
  | { readonly kind: 'found'; readonly profile: PublicProfile }
  | { readonly kind: 'missing' }
  | { readonly kind: 'error' }

type Obj = Record<string, unknown>

const isObj = (v: unknown): v is Obj => !!v && typeof v === 'object' && !Array.isArray(v)
const text = (v: unknown): string => (typeof v === 'string' ? v.trim() : '')
const count = (v: unknown): number => (typeof v === 'number' && Number.isFinite(v) && v > 0 ? Math.floor(v) : 0)
const list = (v: unknown): unknown[] => (Array.isArray(v) ? v : [])
const compact = <T>(items: readonly (T | null)[]): T[] => items.filter((x): x is T => x !== null)

/** Картинка только по https — `javascript:`, `data:` и прочее не рисуем (CSP их бы и так не пустил). */
export function safeImage(v: unknown): string | null {
  const url = text(v)
  return /^https:\/\/[^\s"'<>]+$/i.test(url) ? url : null
}

function track(v: unknown): PublicTrack | null {
  if (!isObj(v) || !text(v.title)) return null
  return {
    ref: text(v.ref),
    title: text(v.title),
    artist: text(v.artist),
    coverUrl: safeImage(v.cover_url),
    durationMs: count(v.duration_ms) || null,
  }
}

function stats(v: unknown): ProfileStats | null {
  if (!isObj(v) || !count(v.plays)) return null
  return {
    plays: count(v.plays),
    totalMs: count(v.total_ms),
    tracks: count(v.tracks),
    artists: count(v.artists),
    streakDays: count(v.streak_days),
  }
}

function likes(v: unknown): PublicProfile['likes'] {
  if (!isObj(v) || !count(v.count)) return null
  return { count: count(v.count), tracks: compact(list(v.tracks).map(track)) }
}

function playlist(v: unknown): PublicPlaylist | null {
  if (!isObj(v) || !text(v.id)) return null
  return {
    id: text(v.id),
    name: text(v.name),
    trackCount: count(v.track_count),
    durationMs: count(v.duration_ms),
    covers: compact(list(v.covers).map(safeImage)),
  }
}

function showcaseItem(v: unknown): ShowcaseItem | null {
  if (!isObj(v) || !text(v.title)) return null
  return {
    kind: text(v.kind),
    ref: text(v.ref),
    title: text(v.title),
    subtitle: text(v.subtitle),
    coverUrl: safeImage(v.cover_url),
  }
}

function topArtist(v: unknown): TopArtist | null {
  return isObj(v) && text(v.name) ? { name: text(v.name), plays: count(v.plays) } : null
}

/** Ответ сервера → что показать. 404 — такого профиля нет; кривой ответ — ошибка, а не пустая страница. */
export function readProfile(status: number, body: unknown, username: string): ProfileResult {
  if (status === 404) return { kind: 'missing' }
  if (status !== 200 || !isObj(body)) return { kind: 'error' }
  const b = body
  const name = text(b.username) || username
  const playlists = Array.isArray(b.playlists) ? compact(b.playlists.map(playlist)) : null
  return {
    kind: 'found',
    profile: {
      username: name,
      displayName: text(b.display_name) || name,
      number: Number.isInteger(b.number) && (b.number as number) > 0 ? (b.number as number) : null,
      createdAt: count(b.created_at) || null,
      nowPlaying: track(b.now_playing),
      stats: stats(b.stats),
      topArtists: compact(list(b.top_artists).map(topArtist)),
      likes: likes(b.likes),
      playlists: playlists?.length ? playlists : null,
      playlistCount: Math.max(count(b.playlist_count), playlists?.length ?? 0),
      showcase: compact(list(b.showcase).map(showcaseItem)),
      private: SECTIONS.filter((s) => list(b.private).includes(s)),
    },
  }
}

/** `@mira · #7` */
export function profileHandle(p: PublicProfile): string {
  return p.number ? `@${p.username} · #${p.number}` : `@${p.username}`
}

/** Есть ли что показать, кроме шапки. Нет — сайт рисует «пока тихо», а не ряд нулей. */
export function hasContent(p: PublicProfile): boolean {
  return !!(p.nowPlaying || p.stats || p.topArtists.length || p.likes || p.playlists || p.showcase.length)
}

/** Длина трека `3:07`, час и больше — `1:02:05`. */
export function formatDuration(ms: number): string {
  const s = Math.round(ms / 1000)
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = String(s % 60).padStart(2, '0')
  return h ? `${h}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`
}

/** Сколько всего слушал: целые часы, меньше часа — минуты (хотя бы одна). */
export function listenParts(ms: number): { readonly unit: 'h' | 'min'; readonly n: number } {
  const hours = Math.floor(ms / 3_600_000)
  return hours >= 1 ? { unit: 'h', n: hours } : { unit: 'min', n: Math.max(1, Math.round(ms / 60_000)) }
}
