// Вызовы Rust (src-tauri/src/commands.rs). Типы — те же, что в docs/API.md.
import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import { isTauri } from './tauri'
import type { Lyrics } from '../lyrics/core/types'

export type Source = 'sc' | 'ym'
export type Repeat = 'off' | 'all' | 'one'

export interface ArtistRef {
  ref: string
  name: string
  avatar_url: string | null
}

export interface Track {
  ref: string
  title: string
  artist: string
  artists: ArtistRef[]
  album: { ref: string; title: string } | null
  duration_ms: number
  cover_url: string | null
  url: string | null
  explicit: boolean
  available: boolean
}

export interface Album {
  ref: string
  title: string
  artist: string
  artists: ArtistRef[]
  cover_url: string | null
  year: number | null
  /** Дата выхода `YYYY-MM-DD` (если известна). */
  released?: string | null
  track_count: number
  url: string | null
}

export interface Artist {
  ref: string
  name: string
  avatar_url: string | null
  followers: number | null
  url: string | null
}

/** Плейлист сервиса (фантомный): scpl:<id>, scpl:likes, ympl:<uid>:<kind>, ympl:likes. */
export interface ServicePlaylist {
  ref: string
  title: string
  owner: string
  cover_url: string | null
  track_count: number
}

/** Трек в Любимых или плейлисте Sonar: трек + id строки и время добавления. */
export interface ListTrack extends Track {
  item_id: string
  added_at: number
}

export interface Playlist {
  id: string
  name: string
  hidden: boolean
  source_ref: string | null
  created_at: number
  updated_at: number
  track_count: number
  duration_ms: number
  covers: string[]
  tracks: ListTrack[] | null
}

export interface SearchMore {
  artists: Artist[]
  albums: Album[]
  playlists: ServicePlaylist[]
}

export type Service = 'soundcloud' | 'yandex'

export interface PlayerState {
  device_id: string | null
  ref: string | null
  context: string | null
  is_playing: boolean
  position_ms: number
  queue: string[]
  queue_index: number | null
  shuffle: boolean
  repeat: Repeat
  client_ts: number
}

export interface ServiceStatus {
  connected: boolean
  name: string | null
  avatar_url: string | null
}

export interface ServicesStatus {
  soundcloud: ServiceStatus
  yandex: ServiceStatus
}

export interface StreamUrl {
  kind: 'file' | 'hls'
  url: string
  /** Что реально играет: «AAC 160», «MP3 320», «FLAC». */
  quality: string
}

export type StatsPeriod = 'day' | 'week' | 'month' | 'half_year' | 'year' | 'all'

export interface ArtistStat {
  name: string
  avatar_url: string | null
  ref: string | null
  ms: number
  plays: number
}

export interface TrackStat {
  ref: string
  title: string
  artist: string
  cover_url: string | null
  plays: number
  ms: number
}

/** `Stats` из docs/API.md §5 + поля экрана «Статистика» (pc/Screenshot_32). */
export interface Stats {
  period: StatsPeriod
  total_ms: number
  delta_pct: number | null
  buckets: { label: string; value_ms: number }[]
  top_artist: ArtistStat | null
  more_artists: ArtistStat[]
  top_tracks: TrackStat[]
  plays: number
  tracks: number
  artists: number
  streak_days: number
  peak_hour: number | null
  per_day: number
  fav_weekday: number | null
}

export interface StorageUsage {
  covers: number
  covers_bytes: number
  lyrics: number
  lyrics_bytes: number
  track_prefs: number
  db_bytes: number
}

export interface MediaInfo {
  title?: string
  artist?: string
  album?: string
  cover_url?: string | null
  duration_ms?: number
  playing: boolean
  position_ms?: number
  active: boolean
}

function call<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  if (!isTauri) return Promise.reject(new Error('Работает только в приложении (npm run tauri dev)'))
  return invoke<T>(cmd, args)
}

/** Текст ошибки из Rust (строка) или из JS (Error). */
export const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e))

export const api = {
  servicesStatus: () => call<ServicesStatus>('services_status'),
  connectSoundcloud: (clientId: string, oauthToken: string | null) =>
    call<ServiceStatus>('connect_soundcloud', { clientId, oauthToken }),
  connectYandex: (token: string) => call<ServiceStatus>('connect_yandex', { token }),
  disconnectService: (service: 'soundcloud' | 'yandex') => call<void>('disconnect_service', { service }),

  search: (q: string, src: Source, limit = 30) => call<Track[]>('search', { q, src, limit }),
  streamUrl: (trackRef: string) => call<StreamUrl>('stream_url', { trackRef }),

  cacheTracks: (tracks: Track[]) => call<void>('cache_tracks', { tracks }),
  savePlayerState: (state: PlayerState) => call<void>('save_player_state', { state }),
  loadPlayerState: () => call<{ state: PlayerState; tracks: Track[] } | null>('load_player_state'),
  recordPlay: (play: { ref: string; artist: string; context: string | null; played_at: number; listened_ms: number }) =>
    call<void>('record_play', { play }),

  searchMore: (q: string, src: Source, limit = 12) => call<SearchMore>('search_more', { q, src, limit }),
  artistPage: (artistRef: string) => call<{ artist: Artist; top: Track[]; albums: Album[] }>('artist_page', { artistRef }),
  albumPage: (albumRef: string) => call<{ album: Album; tracks: Track[] }>('album_page', { albumRef }),
  servicePlaylists: (service: Service) => call<ServicePlaylist[]>('service_playlists', { service }),
  servicePlaylist: (plRef: string) => call<{ playlist: ServicePlaylist; tracks: Track[] }>('service_playlist', { plRef }),
  importPlaylist: (plRef: string, name?: string) => call<Playlist>('import_playlist', { plRef, name }),

  setLike: (itemRef: string, on: boolean, item?: Track | Album | Artist) => call<void>('set_like', { itemRef, on, item }),
  likedRefs: () => call<string[]>('liked_refs'),
  favorites: () => call<ListTrack[]>('favorites'),
  likedCatalog: <T>(kind: 'album' | 'artist') => call<T[]>('liked_catalog', { kind }),
  playlists: () => call<Playlist[]>('playlists'),
  playlist: (id: string) => call<Playlist>('playlist', { id }),
  createPlaylist: (name: string, tracks?: Track[]) => call<Playlist>('create_playlist', { name, tracks }),
  updatePlaylist: (id: string, patch: { name?: string; hidden?: boolean }) => call<void>('update_playlist', { id, ...patch }),
  deletePlaylist: (id: string) => call<void>('delete_playlist', { id }),
  addToPlaylist: (id: string, tracks: Track[], position: 'start' | 'end' = 'end') =>
    call<void>('add_to_playlist', { id, tracks, position }),
  removeFromPlaylist: (id: string, itemIds: string[]) => call<void>('remove_from_playlist', { id, itemIds }),
  reorderPlaylist: (id: string, itemIds: string[]) => call<void>('reorder_playlist', { id, itemIds }),

  getSetting: <T>(key: string) => call<T | null>('get_setting', { key }),
  setSetting: (key: string, value: unknown) => call<void>('set_setting', { key, value }),

  lyrics: (track: Track, refresh = false) => call<Lyrics | null>('lyrics', { track, refresh }),
  lyricsOffset: (trackRef: string) => call<number>('lyrics_offset', { trackRef }),
  setLyricsOffset: (trackRef: string, ms: number) => call<void>('set_lyrics_offset', { trackRef, ms }),

  trackEq: (trackRef: string) => call<number[] | null>('track_eq', { trackRef }),
  setTrackEq: (trackRef: string, gains: number[] | null) => call<void>('set_track_eq', { trackRef, gains }),

  wavePortion: (req: { exclude?: string[]; paused_artists?: string[]; seed?: Track | null; n?: number }) =>
    call<Track[]>('wave_portion', { req }),
  waveFeedback: (event: 'dislike' | 'undislike' | 'skip', track: Track, playedMs?: number) =>
    call<void>('wave_feedback', { event, track, playedMs }),
  dislikedRefs: () => call<string[]>('disliked_refs'),
  similarTracks: (trackRef: string, limit = 20) => call<Track[]>('similar_tracks', { trackRef, limit }),
  cachedTracks: (refs: string[]) => call<Track[]>('cached_tracks', { refs }),
  recentTracks: (limit = 20) => call<Track[]>('recent_tracks', { limit }),
  homeReleases: () => call<Album[]>('home_releases'),
  stats: (period: StatsPeriod) => call<Stats>('stats', { period, tzMin: -new Date().getTimezoneOffset() }),

  streamPort: () => call<number>('stream_port'),
  allSettings: () => call<Record<string, unknown>>('all_settings'),
  resetSettings: () => call<void>('reset_settings'),
  storageUsage: () => call<StorageUsage>('storage_usage'),
  clearStorage: (kind: 'covers' | 'lyrics' | 'track_prefs' | 'all') => call<void>('clear_storage', { kind }),
  openUrl: (url: string) => call<void>('open_url', { url }),
  setZoom: (scale: number) => call<void>('set_zoom', { scale }),
  setAutostart: (on: boolean) => call<void>('set_autostart', { on }),
  autostartEnabled: () => call<boolean>('autostart_enabled'),
  setTrayMode: (on: boolean) => call<void>('set_tray_mode', { on }),

  mediaUpdate: (info: MediaInfo) => (isTauri ? invoke<void>('media_update', { info }) : Promise.resolve()),
}

/** Медиа-клавиши и плашка Windows: play, pause, toggle, next, previous, stop, seek:<мс>. */
export function onMediaControl(cb: (action: string) => void): () => void {
  if (!isTauri) return () => {}
  const off = listen<string>('media-control', (e) => cb(e.payload))
  return () => void off.then((fn) => fn())
}
