// Вызовы Rust (src-tauri/src/commands.rs). Типы — те же, что в docs/API.md.
import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import { isTauri } from './tauri'
import { t } from './i18n.svelte'
import type { Lyrics } from '../lyrics/core/types'
import type { SmartRules } from './smart'
import type { ServiceId, ServiceKey, ServiceCaps, ServicePrefixes } from './services'
import type { Via } from './fallback'
import type { ImportHead, ImportProgress, ImportResult } from './import'

/** Короткий id сервиса (lib/services): параметр `src` поиска, корень префикса ref. */
export type Source = ServiceId
export type Repeat = 'off' | 'all' | 'one'

/** Звук, запомненный для трека (store/track_sound.rs): reverb 0 — выключен, eq null — общая кривая. */
export interface TrackSound {
  rate: number
  pitch: number
  linked: boolean
  reverb: number
  eq: number[] | null
}

export interface ArtistRef {
  ref: string
  name: string
  avatar_url: string | null
}

/** Строка сводки журнала волны (`wave_stats`): `key` — режим или источник кандидатов. */
export interface WaveStatRow {
  key: string
  served: number
  played: number
  /** Доля ранних пропусков среди сыгранных. */
  early_skip_share: number
  /** Доля дослушанных или лайкнутых среди сыгранных. */
  finished_share: number
  avg_reward: number
}
export interface WaveStats {
  days: number
  by_mode: WaveStatRow[]
  by_source: WaveStatRow[]
}

/** Трек на странице исполнителя: плюс то, по чему сортируют «Треки». */
export type ArtistTrack = Track & { likes: number | null; released: string | null }

/** Ответ `share_twins`: ключ сервиса → ref и ссылка найденного трека; SoundCloud играется целиком. */
export interface ShareTwins {
  refs: Record<string, string>
  urls: Record<string, string>
  sc_full: boolean
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
  /** Прослушивания на сервисе (SoundCloud), у Яндекса нет. */
  plays?: number
  /** «Почему этот трек» — только у треков Sonar Mix (wave.rs `why`). */
  why?: WaveWhy
}

/** Откуда трек пришёл в волну: `liked` — свой забытый лайк, `artist` — популярное у любимого
 *  артиста, `explore` — разведка, `session` — похож на зашедшее сейчас, `seed` — волна по треку,
 *  `similar` — похож на твой лайк или дослушанный. `title` / `artist` — сид (у `artist` — имя). */
export interface WaveWhy {
  kind: 'liked' | 'artist' | 'explore' | 'session' | 'seed' | 'similar'
  title?: string
  artist?: string
}

/** Новинка исполнителя: альбом / сингл (`album`) или трек SoundCloud (`track`, с самим треком). */
export interface ReleaseItem {
  ref: string
  kind: 'album' | 'track'
  title: string
  artist: string
  cover_url: string | null
  /** `YYYY-MM-DD`. */
  released: string
  track: Track | null
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
  /** Кто добавил трек в совместный плейлист (`username`); в своём плейлисте и Любимых — нет. */
  added_by?: string
}

/** Участник совместного плейлиста (docs/API.md §4 «Совместные плейлисты»). */
export interface PlaylistMember {
  username: string
  display_name: string | null
  avatar_url: string | null
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
  /** Совместный плейлист: владелец и соавторы приходят с сервера; обычный — `null` и `[]`. */
  owner: PlaylistMember | null
  collaborators: PlaylistMember[]
}

/** Где ищутся дубли: Любимые или id своего плейлиста (`pl_…`). */
export type DupeListId = 'favorites' | `pl_${string}`

/** Группа дублей (dupes/mod.rs): `keep` — кого оставить по умолчанию, он же первый в `items`. */
export interface DupeGroup {
  keep: string
  items: ListTrack[]
}

/** Что убрали одной правкой «Убрать отмеченные» — для «Отменить». */
export interface RemovedDupes {
  list: DupeListId
  items: { item_id: string; added_at: number }[]
}

/** Умный плейлист (`sm_…`): правила из lib/smart.ts, треки пересчитываются при открытии. */
export interface SmartPlaylist {
  id: string
  name: string
  rules: unknown
  created_at: number
  updated_at: number
  track_count: number
  duration_ms: number
  covers: string[]
  tracks: ListTrack[] | null
  /** Не посчитался: правила не читаются или исходного плейлиста больше нет. */
  error: 'invalid' | 'source_missing' | null
}

/** Предпросмотр правил в конструкторе: счётчик и первые треки. */
export interface SmartPreview {
  track_count: number
  duration_ms: number
  covers: string[]
  tracks: ListTrack[]
  error: 'invalid' | 'source_missing' | null
}

export interface SearchMore {
  artists: Artist[]
  albums: Album[]
  playlists: ServicePlaylist[]
}

/** Длинный ключ сервиса (lib/services): имя в хранилище ключей, `general.platform`, поля ServicesStatus. */
export type Service = ServiceKey

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
  /** Подписка (Яндекс Плюс); у SoundCloud всегда null. */
  premium?: boolean | null
  /** Профиль на сайте сервиса; null — сервис адрес не отдал (тогда просто подпись сервиса). */
  profile_url?: string | null
}

export interface ServicesStatus {
  soundcloud: ServiceStatus
  yandex: ServiceStatus
  /** YouTube Music: подключён — есть cookie аккаунта (каталог работает и без него). */
  youtube: ServiceStatus
  spotify: ServiceStatus
}

/** Строка `services_list`: реестр + состояние подключения (ключи — snake_case, как в Rust). */
export interface ServiceState {
  id: ServiceId
  key: ServiceKey
  name: string
  color: string
  icon: string | null
  icon_mono: string | null
  prefixes: ServicePrefixes
  caps: ServiceCaps
  implemented: boolean
  connected: boolean
  account_name: string | null
  avatar_url: string | null
  premium: boolean | null
}

export interface StreamUrl {
  kind: 'file' | 'hls'
  url: string
  /** Что реально играет: «AAC 160», «MP3 320», «FLAC», «Opus 160 · YouTube Music». */
  quality: string
  /** Играет не со своего сервиса (резервный сервис, lib/fallback.ts); null — со своего. */
  via: Via | null
}

export type StatsPeriod = 'day' | 'week' | 'month' | 'half_year' | 'year' | 'all'

export interface ArtistStat {
  name: string
  avatar_url: string | null
  ref: string | null
  ms: number
  plays: number
}

/** Привязанный к пульту телефон (без ключа — он только на телефоне). */
export interface RemoteDevice {
  id: string
  name: string
  paired_at: number
  last_seen: number
  online: boolean
}

export interface RemoteStatus {
  running: boolean
  port: number
  /** Адрес ПК в локальной сети. */
  host: string | null
  name: string
  /** Объявить ПК в сети не вышло — телефон подключится только по QR. */
  mdns_error: string | null
  error: string | null
  pairing: boolean
  devices: RemoteDevice[]
  /** Сервера Sonar нет — привязанные телефоны синкаются с этим ПК по Wi-Fi (remote/sync_hub.rs). */
  lan_sync: boolean
  /** Когда телефон последний раз синкался с ПК: id → секунды. */
  synced: Record<string, number>
}

export interface RemotePairStart {
  code: string
  expires_in_ms: number
  qr_svg: string
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

/** Месяц (`month` 1–12) или год (`month` = null), за который есть прослушивания (store/recap.rs). */
export interface RecapPeriod {
  kind: 'month' | 'year'
  year: number
  month: number | null
  total_ms: number
}

export interface RecapPeriods {
  months: RecapPeriod[]
  years: RecapPeriod[]
}

/** Итоги месяца или года — карточки «Итогов» (docs/API.md §5 `GET /stats/recap`). */
export interface Recap {
  kind: 'month' | 'year'
  year: number
  month: number | null
  total_ms: number
  plays: number
  tracks: number
  artists: number
  active_days: number
  delta_pct: number | null
  top_tracks: TrackStat[]
  top_artists: ArtistStat[]
  new_artist: { artist: ArtistStat; first_played: string } | null
  /** Время по часам суток, 24 значения в мс. */
  hours: number[]
  peak_hour: number | null
  longest_day: { date: string; ms: number; plays: number } | null
  repeat: { track: TrackStat; count: number; date: string } | null
  /** Доли сервисов: id из реестра, проценты в сумме 100. */
  services: { service: string; ms: number; pct: number }[]
}

export interface StorageUsage {
  covers: number
  covers_bytes: number
  tracks: number
  tracks_bytes: number
  lyrics: number
  lyrics_bytes: number
  track_prefs: number
  db_bytes: number
  /** Скачанное (`downloads.rs`): не вытесняется и «Очистить» его не трогает. */
  downloaded: number
  downloaded_bytes: number
  /** Анализ для сведения (`blend_analysis`). */
  blend: number
  blend_bytes: number
}

/** Откуда воркеру сведения взять файл трека (`blend.rs`): `temp` — временный, после анализа отпустить. */
export interface BlendSource {
  url: string
  temp: boolean
}

/** Состояние трека в очереди скачивания (`downloads.rs` `Job`). Скачанный из очереди уходит. */
export type DownloadJob = { state: 'queued' } | { state: 'active' } | { state: 'failed'; error: string } | { state: 'unsupported' }

/** Очередь скачивания целиком (`downloads.rs` `Snapshot`): `done` — скачано в текущей пачке, `left` — ещё в работе. */
export interface DownloadsSnapshot {
  paused: boolean
  done: number
  left: number
  jobs: Record<string, DownloadJob>
}

export interface MediaInfo {
  /** ref трека — кнопка «Слушать в Sonar» в Discord, обложка и «сейчас играет» в OBS. */
  track_ref?: string
  /** Фото главного артиста — мини-значок в Discord. */
  artist_avatar?: string | null
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
  if (!isTauri) return Promise.reject(new Error(t('Работает только в приложении (npm run tauri dev)')))
  return invoke<T>(cmd, args)
}

/** Текст ошибки из Rust (строка) или из JS (Error) — на языке интерфейса: известные сообщения Rust
 *  есть в словарях (i18n/<язык>/player.ts), ошибка сервиса `http_error` (providers/mod.rs) —
 *  «Сервис: причина (HTTP 429)» — переводится по частям. Неизвестное — как есть. */
/** Исходный текст ошибки (до перевода) — чтобы узнавать её по словам, не завися от языка. */
export function rawError(e: unknown): string {
  return e instanceof Error ? e.message : String(e)
}

export function errorText(e: unknown): string {
  const s = e instanceof Error ? e.message : String(e)
  const http = /^(.+?): (.+) \(HTTP (\d+)\)$/.exec(s)
  if (http) return `${t(http[1])}: ${t(http[2])} (HTTP ${http[3]})`
  return t(s)
}

/** Что нашлось по ссылке из строки поиска (services.rs `LinkItem`). */
export type LinkItem =
  | { kind: 'track'; track: Track }
  | { kind: 'album'; album: Album }
  | { kind: 'artist'; artist: Artist }
  | { kind: 'playlist'; playlist: ServicePlaylist }
  /** Плейлист или альбом Apple Music: своего сервиса нет — только перенос с подбором пар. */
  | { kind: 'import'; head: ImportHead }

/** Адреса сервисов, которые узнаёт links.rs, и без `https://` (вставили «open.spotify.com/…»). */
const LINK_HOSTS = ['soundcloud.com/', 'music.yandex.', 'open.spotify.com/', 'youtube.com/', 'youtu.be/', 'music.apple.com/']

/** Похоже на ссылку музыкального сервиса, а не на поисковый запрос (как links.rs `looks_like_link`). */
export function looksLikeLink(s: string): boolean {
  const t = s.trim()
  if (!t || /\s/.test(t)) return false
  return /^https?:\/\//.test(t) || t.startsWith('spotify:') || LINK_HOSTS.some((h) => t.includes(h))
}

/** Отчёт прошлого запуска (crashlog.rs): было падение или ошибки. */
export interface CrashReport {
  crashed: boolean
  errors: number
  last: string
}
export type ReportSent = { kind: 'telegram' } | { kind: 'saved'; path: string }
/** Итог «Проверить сервисы» по одному подключённому сервису (services.rs `ServiceCheck`). */
export interface ServiceCheck {
  service: ServiceKey
  ok: boolean
  ms: number
  error: string | null
}

export const api = {
  servicesStatus: () => call<ServicesStatus>('services_status'),
  /** Дочитать ссылки на профили у старых аккаунтов (один раз за запуск) и вернуть статус. */
  servicesFillLinks: () => call<ServicesStatus>('services_fill_links'),
  /** Поиск на одну строку в каждом подключённом сервисе: жив ли ключ и отвечает ли сервис. */
  checkServices: () => call<ServiceCheck[]>('check_services'),
  /** Все сервисы реестра в порядке показа, с состоянием подключения. */
  servicesList: () => call<ServiceState[]>('services_list'),
  /** «Вставить ключ»: поля по сервису (sc: client_id, oauth_token; ym: token; yt: cookie). Значения в ошибках не возвращаются. */
  connectServiceKey: (service: ServiceId | ServiceKey, fields: Record<string, string>) =>
    call<ServiceStatus>('connect_service_key', { service, fields }),
  resolveLink: (url: string) => call<LinkItem>('resolve_link', { url }),
  reportPending: () => call<CrashReport | null>('report_pending'),
  reportSend: (context: { style: string; queue: number }) => call<ReportSent>('report_send', { context }),
  reportDismiss: () => call<void>('report_dismiss'),
  logFrontend: (level: 'error' | 'warn', message: string) => call<void>('log_frontend', { level, message }),
  syncNow: () => call<{ pushed: number; pulled: number; plays: number }>('sync_now'),
  connectSoundcloud: (clientId: string, oauthToken: string | null) =>
    call<ServiceStatus>('connect_soundcloud', { clientId, oauthToken }),
  connectYandex: (token: string) => call<ServiceStatus>('connect_yandex', { token }),
  /** Вход в один клик: окно входа сервиса, ключи Sonar забирает сам. */
  /** Плашка OBS: адрес источника «Браузер» и работает ли сервер плашки. */
  obsStatus: () => call<{ url: string; ok: boolean }>('obs_status'),
  obsNewToken: () => call<{ url: string; ok: boolean }>('obs_new_token'),
  discordStatus: () => call<{ enabled: boolean; connected: boolean }>('discord_status'),
  loginService: (service: Service) => call<ServiceStatus>('login_service', { service }),
  /** Отменить ожидание входа через браузер (Яндекс по коду). */
  cancelLogin: () => call<void>('cancel_login'),
  disconnectService: (service: Service) => call<void>('disconnect_service', { service }),

  search: (q: string, src: Source, limit = 30) => call<Track[]>('search', { q, src, limit }),
  /** `track` — трек из интерфейса: по нему ищется замена, если свой сервис его не отдаёт. */
  streamUrl: (trackRef: string, track?: Track) => call<StreamUrl>('stream_url', { trackRef, track: track ?? null }),
  /** Свой поток открылся, но не играет — тот же трек из резервного сервиса (или ошибка). */
  /** «Поделиться»: тот же трек в YouTube Music, SoundCloud и Яндексе (services/share.rs, ≤ 4 с). */
  shareTwins: (trackRef: string, track?: Track) => call<ShareTwins>('share_twins', { trackRef, track: track ?? null }),
  streamFallback: (trackRef: string, track?: Track) => call<StreamUrl>('stream_fallback', { trackRef, track: track ?? null }),

  cacheTracks: (tracks: Track[]) => call<void>('cache_tracks', { tracks }),
  /** «Sonar Mix офлайн»: следующие треки — в кэш треков заранее (фоном; кэш выключен — ничего). */
  prefetchTracks: (refs: string[]) => call<void>('prefetch_tracks', { refs }),
  /** Горячие клавиши (hotkeys.rs): действие → сочетание. Вернёт действия, чьё сочетание не встало. */
  setHotkeys: (keys: Record<string, string>) => call<string[]>('set_hotkeys', { keys }),
  // пульт с iPhone (remote/): сервер в локальной сети, привязка кодом, состояние плеера телефонам
  remoteSetEnabled: (on: boolean) => call<void>('remote_set_enabled', { on }),
  remoteStatus: () => call<RemoteStatus>('remote_status'),
  remotePairStart: () => call<RemotePairStart>('remote_pair_start'),
  remotePairCancel: () => call<void>('remote_pair_cancel'),
  remoteUnpair: (id: string) => call<void>('remote_unpair', { id }),
  remoteState: (state: unknown) => (isTauri ? invoke<void>('remote_state', { state }) : Promise.resolve()),
  /** Экспорт плейлиста (export.rs): окно «Сохранить как» и запись готового текста; `null` — окно
   *  закрыли, иначе имя сохранённого файла. */
  exportPlaylist: (name: string, format: 'm3u8' | 'csv' | 'json', title: string, contents: string) =>
    call<string | null>('export_playlist', { name, format, title, contents }),
  /** Карточка итогов картинкой (export.rs `save_image`): PNG в base64 → окно «Сохранить как». */
  saveImage: (name: string, title: string, pngBase64: string) =>
    call<string | null>('save_image', { name, title, pngBase64 }),
  savePlayerState: (state: PlayerState) => call<void>('save_player_state', { state }),
  loadPlayerState: () => call<{ state: PlayerState; tracks: Track[] } | null>('load_player_state'),
  recordPlay: (play: { ref: string; artist: string; context: string | null; played_at: number; listened_ms: number }) =>
    call<void>('record_play', { play }),

  searchMore: (q: string, src: Source, limit = 12) => call<SearchMore>('search_more', { q, src, limit }),
  artistPage: (artistRef: string) => call<{ artist: Artist; top: Track[]; albums: Album[] }>('artist_page', { artistRef }),
  /** Все треки исполнителя (до 1000) — сначала самые прослушиваемые; лайки есть только у SoundCloud. */
  artistTracks: (artistRef: string) => call<ArtistTrack[]>('artist_tracks', { artistRef }),
  /** Репосты исполнителя SoundCloud; у других сервисов — пусто. */
  artistReposts: (artistRef: string) => call<Track[]>('artist_reposts', { artistRef }),
  albumPage: (albumRef: string) => call<{ album: Album; tracks: Track[] }>('album_page', { albumRef }),
  servicePlaylists: (service: Service) => call<ServicePlaylist[]>('service_playlists', { service }),
  servicePlaylist: (plRef: string) => call<{ playlist: ServicePlaylist; tracks: Track[] }>('service_playlist', { plRef }),
  importPlaylist: (plRef: string, name?: string) => call<Playlist>('import_playlist', { plRef, name }),
  /** Импорт по ссылке (этап 5): прочитать источник и подобрать пары; шаги — `onImportProgress`. */
  importLink: (link: string, job: string) => call<ImportResult>('import_link', { link, job }),
  importCancel: (job: string) => call<void>('import_cancel', { job }),
  /** Сохранить найденное смешанным плейлистом; тот же `source` второй раз дописывает прежний. */
  importCreate: (name: string, source: string, tracks: Track[]) => call<Playlist>('import_create', { name, source, tracks }),

  setLike: (itemRef: string, on: boolean, item?: Track | Album | Artist) => call<void>('set_like', { itemRef, on, item }),
  likedRefs: () => call<string[]>('liked_refs'),
  favorites: () => call<ListTrack[]>('favorites'),
  /** «Очистить Любимые»: снять все лайки треков; вернёт, сколько убрано. */
  clearFavorites: () => call<number>('clear_favorites'),
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
  /** Дубли в Любимых или своём плейлисте — офлайн, по сохранённым метаданным. */
  findDuplicates: (list: DupeListId) => call<DupeGroup[]>('find_duplicates', { list }),
  /** Убрать строки одной правкой; ответ — для «Отменить». */
  removeDuplicates: (list: DupeListId, itemIds: string[]) => call<RemovedDupes>('remove_duplicates', { list, itemIds }),
  /** Вернуть убранное; вернёт, сколько строк вернулось. */
  restoreDuplicates: (removed: RemovedDupes) => call<number>('restore_duplicates', { removed }),
  smartPlaylists: () => call<SmartPlaylist[]>('smart_playlists'),
  smartPlaylist: (id: string) => call<SmartPlaylist>('smart_playlist', { id }),
  smartPreview: (rules: SmartRules) => call<SmartPreview>('smart_preview', { rules }),
  createSmartPlaylist: (name: string, rules: SmartRules) => call<SmartPlaylist>('create_smart_playlist', { name, rules }),
  updateSmartPlaylist: (id: string, patch: { name?: string; rules?: SmartRules }) =>
    call<void>('update_smart_playlist', { id, ...patch }),
  deleteSmartPlaylist: (id: string) => call<void>('delete_smart_playlist', { id }),

  getSetting: <T>(key: string) => call<T | null>('get_setting', { key }),
  setSetting: (key: string, value: unknown) => call<void>('set_setting', { key, value }),

  lyrics: (track: Track, refresh = false) => call<Lyrics | null>('lyrics', { track, refresh }),
  lyricsTranslate: (lines: string[], to: string) => call<{ lines: string[]; source: string }>('lyrics_translate', { lines, to }),
  lyricsAnnotations: (track: Track) =>
    call<{ lines: string[]; body: string; reviewed: boolean }[]>('lyrics_annotations', { track }),
  lyricsOffset: (trackRef: string) => call<number>('lyrics_offset', { trackRef }),
  setLyricsOffset: (trackRef: string, ms: number) => call<void>('set_lyrics_offset', { trackRef, ms }),

  /** Звук трека («Для этого трека»): скорость, тон, реверб, эквалайзер; null — общие настройки. */
  trackSound: (trackRef: string) => call<TrackSound | null>('track_sound', { trackRef }),
  setTrackSound: (trackRef: string, sound: TrackSound | null) => call<void>('set_track_sound', { trackRef, sound }),
  /** Все ref со своим звуком — значок в списках одним запросом. */
  trackSoundRefs: () => call<string[]>('track_sound_refs'),

  wavePortion: (req: {
    exclude?: string[]
    paused_artists?: string[]
    seed?: Track | null
    /** Дослушанные / лайкнутые в этой сессии волны — сиды следующих порций. */
    session?: Track[]
    /** Артисты, пропущенные в сессии хотя бы раз. */
    skipped_artists?: string[]
    /** Пропущенные в сессии треки (оценка < 0): их теги идут в минус следующим порциям. */
    skipped_tracks?: Track[]
    /** Артисты всех выданных в сессии треков (с повторами). */
    served_artists?: string[]
    n?: number
    mode?: string
    tz_min?: number
    /** Сессия волны — выданные треки пишутся в журнал `wave_events` под этим id. */
    session_id?: string
  }) =>
    call<Track[]>('wave_portion', { req }),
  /** `end` — исход трека волны для журнала: `sessionId` и `reward` (`reward.ts`), `playedMs` — прослушано. */
  waveFeedback: (
    event: 'dislike' | 'undislike' | 'skip' | 'end',
    track: Track,
    playedMs?: number,
    extra?: { sessionId?: string; reward?: number },
  ) => call<void>('wave_feedback', { event, track, playedMs, sessionId: extra?.sessionId, reward: extra?.reward }),
  /** Сводка по журналу волны за `days` дней: по режимам и по источникам кандидатов. Экрана пока нет. */
  waveStats: (days = 30) => call<WaveStats>('wave_stats', { days }),
  dislikedRefs: () => call<string[]>('disliked_refs'),
  similarTracks: (trackRef: string, limit = 20) => call<Track[]>('similar_tracks', { trackRef, limit }),
  cachedTracks: (refs: string[]) => call<Track[]>('cached_tracks', { refs }),
  recentTracks: (limit = 20) => call<Track[]>('recent_tracks', { limit }),
  homeReleases: () => call<Album[]>('home_releases'),
  /** Новинки любимых исполнителей для колокольчика (commands.rs `release_feed`). */
  releaseFeed: () => call<ReleaseItem[]>('release_feed'),
  /** Подборка под время суток на главной: что слушаешь в эти часы + лайки. */
  daypartMix: (limit = 24) => call<Track[]>('daypart_mix', { tzMin: new Date().getTimezoneOffset(), limit }),
  stats: (period: StatsPeriod) => call<Stats>('stats', { period, tzMin: -new Date().getTimezoneOffset() }),
  recap: (kind: 'month' | 'year', year: number, month: number | null) =>
    call<Recap>('recap', { kind, year, month, tzMin: -new Date().getTimezoneOffset() }),
  recapPeriods: () => call<RecapPeriods>('recap_periods', { tzMin: -new Date().getTimezoneOffset() }),

  streamPort: () => call<number>('stream_port'),
  allSettings: () => call<Record<string, unknown>>('all_settings'),
  resetSettings: () => call<void>('reset_settings'),
  storageUsage: () => call<StorageUsage>('storage_usage'),
  clearStorage: (kind: 'covers' | 'tracks' | 'lyrics' | 'track_prefs' | 'blend' | 'all') => call<void>('clear_storage', { kind }),
  /** Сведение (`blend.rs`): файл трека для анализа, сохранённые анализы, оценки переходов. */
  blendSource: (trackRef: string) => call<BlendSource>('blend_source', { trackRef }),
  blendRelease: (trackRef: string) => call<void>('blend_release', { trackRef }),
  blendGet: (refs: string[]) => call<Record<string, { version: number; data: string }>>('blend_get', { refs }),
  blendPut: (trackRef: string, version: number, json: string) => call<void>('blend_put', { trackRef, version, json }),
  blendRate: (from: string, to: string, kind: string, score: 1 | -1) => call<void>('blend_rate', { from, to, kind, score }),
  /** Перевес оценок по видам перехода с `sinceMs`: −1…1. */
  blendBalance: (sinceMs: number) => call<Record<string, number>>('blend_balance', { sinceMs }),
  addSearchHistory: (entry: import('./search-history.svelte').SearchEntry) => call<void>('add_search_history', { entry }),
  searchHistory: (limit = 20) => call<import('./search-history.svelte').SearchEntry[]>('search_history', { limit }),
  searchHistoryCount: () => call<number>('search_history_count'),
  clearSearchHistory: () => call<void>('clear_search_history'),
  /** Кэш треков на диске (Хранилище): включить и лимит, МБ (track_cache.rs). */
  setTrackCache: (on: boolean, limitMb: number) => call<void>('set_track_cache', { on, limitMb }),
  openUrl: (url: string) => call<void>('open_url', { url }),
  /** Ярлык Sonar в меню «Пуск»; true — создан сейчас, false — уже был. */
  addToStartMenu: () => call<boolean>('add_to_start_menu'),
  /** Показать ярлык в Проводнике — оттуда «Закрепить на панели задач» (тихо Windows закрепить не даёт). */
  revealStartShortcut: () => call<void>('reveal_start_shortcut'),
  setZoom: (kind: 'window' | 'fullscreen', percent: number) => call<void>('set_zoom', { kind, percent }),
  /** Прозрачность окна: Mica (Windows 11) / Acrylic (Windows 10) под окном; вернёт, что включилось. */
  setGlass: (on: boolean) => call<'mica' | 'acrylic' | 'off'>('set_glass', { on }),
  setAutostart: (on: boolean) => call<void>('set_autostart', { on }),
  autostartEnabled: () => call<boolean>('autostart_enabled'),
  setTrayMode: (on: boolean) => call<void>('set_tray_mode', { on }),

  /** Локальные файлы (local/commands.rs): выбрать папку (null — отмена), пересканировать папки
   *  `storage.music_folders`, все найденные треки и поиск по ним. */
  localPickFolder: (title: string) => call<string | null>('local_pick_folder', { title }),
  localRescan: () => call<LocalSummary>('local_rescan'),
  localTracks: () => call<Track[]>('local_tracks'),
  localSearch: (query: string, limit?: number) => call<Track[]>('local_search', { query, limit }),
  /** Офлайн-режим (`docs/OFFLINE.md`): включён ли, что играет без сети, треки из кэша для офлайн-списков. */
  offlineState: () => call<boolean>('offline_state'),
  offlineRefs: () => call<string[]>('offline_refs'),
  offlineTracks: () => call<Track[]>('offline_tracks'),
  /** Сколько запросов в сеть отрезано с включения офлайн-режима (`offline.rs` `blocked`). */
  offlineBlocked: () => call<number>('offline_blocked'),
  /** Сигналы для «Sonar Mix офлайн»: прослушивания, пропуски и теги доступных треков (`store/offline.rs`). */
  offlineMixSignals: (refs: string[]) => call<MixSignals>('offline_mix_signals', { refs }),
  /** Скачивание (`downloads.rs`, `docs/OFFLINE.md` §8): поставить в очередь (вернёт, сколько добавлено), очередь,
   *  что скачано, пауза, повтор упавших, отмена, удалить скачанное, удалить всё, открыть папку, свободно на диске. */
  downloadTracks: (tracks: Track[]) => call<number>('download_tracks', { tracks }),
  downloadsState: () => call<DownloadsSnapshot>('downloads_state'),
  downloadedRefs: () => call<string[]>('downloaded_refs'),
  downloadsPause: (paused: boolean) => call<void>('downloads_pause', { paused }),
  downloadsRetry: () => call<void>('downloads_retry'),
  downloadsCancel: (refs: string[]) => call<void>('downloads_cancel', { refs }),
  downloadsRemove: (refs: string[]) => call<void>('downloads_remove', { refs }),
  downloadsClear: () => call<void>('downloads_clear'),
  downloadsReveal: () => call<void>('downloads_reveal'),
  diskFree: () => call<number | null>('disk_free'),

  mediaUpdate: (info: MediaInfo) => (isTauri ? invoke<void>('media_update', { info }) : Promise.resolve()),
}

/** Что Sonar знает о треке для «Sonar Mix офлайн»: прослушивания, последний раз (мс), пропуски, теги. */
export interface MixSignal {
  ref: string
  plays: number
  last_played: number
  skips: number
  tags: string[]
}

/** Сигналы по доступным трекам и теги последних прослушиваний. */
export interface MixSignals {
  tracks: MixSignal[]
  recent_tags: string[]
}

/** Итог скана папок с музыкой: сколько файлов в индексе и что изменилось. */
export interface LocalSummary {
  total: number
  added: number
  updated: number
  removed: number
  /** Строк, чьих файлов сейчас нет на диске («Файл не найден»). */
  missing: number
  /** Файлов больше 50 000 — просканированы не все. */
  truncated: boolean
}

/** Папки с музыкой изменились (скан после правки на диске или в настройках). */
export function onLocalFilesChanged(cb: () => void): () => void {
  if (!isTauri) return () => {}
  const off = listen('local-files-changed', () => cb())
  return () => void off.then((fn) => fn())
}

/** Офлайн-режим включили или выключили (offline.rs, событие `offline-changed`). */
export function onOfflineChanged(cb: (on: boolean) => void): () => void {
  if (!isTauri) return () => {}
  const off = listen<boolean>('offline-changed', (e) => cb(e.payload))
  return () => void off.then((fn) => fn())
}

/** В кэше треков что-то легло или ушло (offline_index.rs, событие `offline-index-changed`). */
export function onOfflineIndexChanged(cb: () => void): () => void {
  if (!isTauri) return () => {}
  const off = listen('offline-index-changed', () => cb())
  return () => void off.then((fn) => fn())
}

/** Очередь скачивания поменялась (downloads.rs, событие `downloads-changed`). */
export function onDownloadsChanged(cb: (s: DownloadsSnapshot) => void): () => void {
  if (!isTauri) return () => {}
  const off = listen<DownloadsSnapshot>('downloads-changed', (e) => cb(e.payload))
  return () => void off.then((fn) => fn())
}

/** Прогресс импорта по ссылке (import_link.rs, событие `import:progress`). Промис `ready` — подписка
 *  уже действует (иначе первые шаги можно пропустить); `off` — отписаться. */
export function onImportProgress(cb: (ev: ImportProgress) => void): { ready: Promise<void>; off: () => void } {
  if (!isTauri) return { ready: Promise.resolve(), off: () => {} }
  const un = listen<ImportProgress>('import:progress', (e) => cb(e.payload))
  return { ready: un.then(() => undefined), off: () => void un.then((fn) => fn()) }
}

/** Горячие клавиши (hotkeys.rs): toggle, next, prev, like, volume_up, volume_down. */
export function onHotkey(cb: (action: string) => void): () => void {
  if (!isTauri) return () => {}
  const off = listen<string>('hotkey', (e) => cb(e.payload))
  return () => void off.then((fn) => fn())
}

/** Пульт: команда с телефона (remote-core.ts `parseCommand`). */
export function onRemoteCommand(cb: (cmd: unknown) => void): () => void {
  if (!isTauri) return () => {}
  const off = listen<unknown>('remote-command', (e) => cb(e.payload))
  return () => void off.then((fn) => fn())
}

/** Пульт: подключился / отключился телефон, сервер включён или выключен, код ввели неверно. */
export function onRemoteChanged(cb: () => void): () => void {
  if (!isTauri) return () => {}
  const off = listen('remote-changed', () => cb())
  return () => void off.then((fn) => fn())
}

/** Синк по Wi-Fi: телефон прислал изменения, ПК применил их у себя (сколько). */
export function onSyncApplied(cb: (count: number) => void): () => void {
  if (!isTauri) return () => {}
  const off = listen<number>('sync-applied', (e) => cb(e.payload))
  return () => void off.then((fn) => fn())
}

/** SoundCloud: свои ключи не починились (services/sc_repair.rs) — нужен вход заново. */
export function onSoundCloudRelogin(cb: () => void): () => void {
  if (!isTauri) return () => {}
  const off = listen('soundcloud:relogin', () => cb())
  return () => void off.then((fn) => fn())
}

/** Пульт: телефон привязан (имя телефона). */
export function onRemotePaired(cb: (name: string) => void): () => void {
  if (!isTauri) return () => {}
  const off = listen<string>('remote-paired', (e) => cb(e.payload))
  return () => void off.then((fn) => fn())
}

/** Медиа-клавиши и плашка Windows: play, pause, toggle, next, previous, stop, seek:<мс>. */
export function onMediaControl(cb: (action: string) => void): () => void {
  if (!isTauri) return () => {}
  const off = listen<string>('media-control', (e) => cb(e.payload))
  return () => void off.then((fn) => fn())
}
