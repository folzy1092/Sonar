// Вызовы Rust (src-tauri/src/commands.rs). Типы — те же, что в docs/API.md.
import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import { isTauri } from './tauri'

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

  getSetting: <T>(key: string) => call<T | null>('get_setting', { key }),
  setSetting: (key: string, value: unknown) => call<void>('set_setting', { key, value }),

  mediaUpdate: (info: MediaInfo) => (isTauri ? invoke<void>('media_update', { info }) : Promise.resolve()),
}

/** Медиа-клавиши и плашка Windows: play, pause, toggle, next, previous, stop, seek:<мс>. */
export function onMediaControl(cb: (action: string) => void): () => void {
  if (!isTauri) return () => {}
  const off = listen<string>('media-control', (e) => cb(e.payload))
  return () => void off.then((fn) => fn())
}
