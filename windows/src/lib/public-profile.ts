// Публичный профиль (TZ.md 10а, SPEC §4.5а): ссылка `https://sonar.folzy.ru/@username` и то, что по ней
// увидит гость. `PublicProfile` — тот же объект, что потом отдаст `GET /public/users/{username}`
// (docs/API.md) и нарисует страница сайта `site/`. До сервера предпросмотр «Как видят мой профиль»
// собирает его здесь, на компьютере: профиль из настроек (`profile.*`), Любимые, плейлисты Sonar,
// статистика из `plays` и то, что играет сейчас. Приватности пока нет (вопрос владельцу, NEXT_PROMPT
// этап 0 п. 9) — предпросмотр показывает всё как открытое, в том числе плейлисты, скрытые из «Все».
// Имя и аватар — только профиля Sonar: аккаунт SoundCloud / Яндекса сервер гостю не покажет.
import type { ListTrack, Playlist, Stats, Track } from './api'
import { cleanUsername, USERNAME_RE } from './avatar'
import { SITE_URL } from './site'
/** Сколько Любимых видно на странице профиля (остальное — числом). */
export const PROFILE_LIKES_SHOWN = 8
export const PROFILE_PLAYLISTS_SHOWN = 12
export const PROFILE_ARTISTS_SHOWN = 6
/** Часы музыки до этого числа показываются с одной цифрой после точки («1.4»), дальше — целыми. */
const HOURS_DECIMAL_BELOW = 10

/** Ссылка на профиль: `https://sonar.folzy.ru/@folzy`. Нет @username или он с ошибкой — null. */
export function profileUrl(username: string): string | null {
  const name = cleanUsername(username)
  return USERNAME_RE.test(name) ? `${SITE_URL}/@${name}` : null
}

export interface PublicTrack {
  ref: string
  title: string
  artist: string
  cover_url: string | null
  duration_ms: number
}

export interface PublicPlaylist {
  id: string
  name: string
  track_count: number
  duration_ms: number
  covers: string[]
}

export interface PublicArtist {
  name: string
  avatar_url: string | null
  ref: string | null
  plays: number
}

export interface PublicStats {
  plays: number
  total_ms: number
  tracks: number
  artists: number
  streak_days: number
}

export interface PublicProfile {
  /** Без «@»; null — @username не задан. */
  username: string | null
  /** Пусто — имени нет (интерфейс пишет «Без имени»). */
  display_name: string
  /** `#номер` и дата регистрации приходят с сервера; до него — null. */
  number: number | null
  avatar_url: string | null
  created_at: number | null
  now_playing: PublicTrack | null
  /** null — ещё ничего не прослушано. */
  stats: PublicStats | null
  top_artists: PublicArtist[]
  likes: { count: number; tracks: PublicTrack[] }
  playlists: PublicPlaylist[]
  playlist_count: number
}

/** Из чего собирается профиль. Не загрузилось (вне приложения, ошибка) — null, раздел просто пуст. */
export interface ProfileSource {
  name: string
  username: string
  avatar: string
  favorites?: ListTrack[] | null
  playlists?: Playlist[] | null
  stats?: Stats | null
  current?: Track | null
  /** Играет ли `current` сейчас: на паузе или восстановленный при запуске трек гостю не виден. */
  playing?: boolean
}

export function toPublicTrack(track: Track): PublicTrack {
  return {
    ref: track.ref,
    title: track.title,
    artist: track.artist,
    cover_url: track.cover_url,
    duration_ms: track.duration_ms,
  }
}

function toPublicPlaylist(p: Playlist): PublicPlaylist {
  return { id: p.id, name: p.name, track_count: p.track_count, duration_ms: p.duration_ms, covers: p.covers.slice(0, 4) }
}

function publicStats(stats: Stats | null | undefined): PublicStats | null {
  if (!stats?.plays) return null
  return {
    plays: stats.plays,
    total_ms: stats.total_ms,
    tracks: stats.tracks,
    artists: stats.artists,
    streak_days: stats.streak_days,
  }
}

function topArtists(stats: Stats | null | undefined): PublicArtist[] {
  if (!stats?.plays) return []
  return [stats.top_artist, ...stats.more_artists]
    .filter((a): a is NonNullable<typeof a> => !!a)
    .slice(0, PROFILE_ARTISTS_SHOWN)
    .map((a) => ({ name: a.name, avatar_url: a.avatar_url, ref: a.ref, plays: a.plays }))
}

export function buildPublicProfile(src: ProfileSource): PublicProfile {
  const username = cleanUsername(src.username)
  const favorites = src.favorites ?? []
  const playlists = src.playlists ?? []
  return {
    username: USERNAME_RE.test(username) ? username : null,
    display_name: src.name.trim(),
    number: null,
    avatar_url: src.avatar || null,
    created_at: null,
    now_playing: src.playing && src.current ? toPublicTrack(src.current) : null,
    stats: publicStats(src.stats),
    top_artists: topArtists(src.stats),
    likes: { count: favorites.length, tracks: favorites.slice(0, PROFILE_LIKES_SHOWN).map(toPublicTrack) },
    playlists: playlists.slice(0, PROFILE_PLAYLISTS_SHOWN).map(toPublicPlaylist),
    playlist_count: playlists.length,
  }
}

/** Первая буква имени — заглушка аватара (как на iPhone `LocalProfile.initial`). */
export function profileInitial(profile: Pick<PublicProfile, 'display_name' | 'username'>): string {
  const source = profile.display_name.trim() || profile.username || 'S'
  return [...source][0].toUpperCase()
}

/** Часы музыки так, как их видно на странице: до 10 — с одной цифрой после точки, дальше — целыми. */
export function formatHours(hours: number): string {
  return hours < HOURS_DECIMAL_BELOW ? hours.toFixed(1) : String(Math.round(hours))
}

/**
 * Число для `tn` к подписи часов: дробное («1.4») требует «часа» / «години» / «hours», как у 2, —
 * поэтому форма выбирается по показанной строке, а не по округлённому числу.
 */
export function hoursPluralCount(hours: number): number {
  const shown = formatHours(hours)
  return shown.includes('.') ? 2 : Number(shown)
}
