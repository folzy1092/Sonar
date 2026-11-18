// Реестр сервисов — единый источник правды (docs/API.md «Префиксы ref»; тот же стол в Rust
// providers/registry.rs и Swift ServiceRegistry.swift). Порядок строк = порядок показа везде.
// Тексты — русские исходники для t(); у sc/ym они байт в байт прежние, чтобы словари совпадали.
// В интерфейсе показываются только `implemented` (IMPLEMENTED): остальные появятся сами, когда флаг включат.
import type { ServiceState, ServiceStatus, ServicesStatus } from './api'

export type ServiceId = 'sc' | 'ym' | 'yt' | 'vk' | 'sp' | 'local'
export type ServiceKey = 'soundcloud' | 'yandex' | 'youtube' | 'vk' | 'spotify' | 'local'
export type RefKind = 'track' | 'album' | 'artist' | 'playlist'

export interface ServiceCaps {
  search: boolean
  stream: boolean
  library: boolean
  playlists: boolean
  similar: boolean
  login: boolean
  key: boolean
}

export interface ServicePrefixes {
  track: string
  album: string | null
  artist: string | null
  playlist: string | null
}

export interface KeyField {
  /** Имя поля для `connect_service_key`: 'client_id' | 'oauth_token' | 'token'. */
  name: string
  /** Подпись (через t(); латиница вроде 'client_id' проходит t() как есть). */
  label: string
  /** input type=password. */
  secret: boolean
  optional: boolean
  /** Подсказка в поле (через t()). */
  placeholder: string
}

/** Кусок подсказки под полями: текст для t(), `<code>` или знаки препинания как есть. */
export type HintPart = { text: string } | { code: string } | { raw: string }

export interface ServiceInfo {
  id: ServiceId
  key: ServiceKey
  name: string
  short: string
  color: string
  prefixes: ServicePrefixes
  caps: ServiceCaps
  implemented: boolean
  /** Для «не подключён / не подключена». */
  gender: 'm' | 'f'
  /** Предложный падеж для «в {source}». */
  nameIn: string
  openIn: string | null
  status: { connectedAs: string; connected: string; disconnected: string }
  loginLabel: string | null
  loginBusyLabel: string | null
  reloginLabel: string | null
  /** Когда кнопка входа говорит «Войти заново»: SoundCloud — только при имени аккаунта, Яндекс — при любом подключении. */
  reloginWhen: 'named' | 'connected'
  keyFields: readonly KeyField[]
  keyHint: readonly HintPart[] | null
  /** Кнопка ручного ввода, когда сервис уже подключён. */
  keyReplaceLabel: string | null
}

const ALL_CAPS: ServiceCaps = { search: true, stream: true, library: true, playlists: true, similar: true, login: true, key: true }

const MALE_STATUS = { connectedAs: 'Подключён как {name}', connected: 'Подключён', disconnected: 'Не подключён' }
const FEMALE_STATUS = { connectedAs: 'Подключена как {name}', connected: 'Подключена', disconnected: 'Не подключена' }

const LOGIN_BUSY = 'Жду вход в браузере…'
const RELOGIN = 'Войти заново'

const prefixes = (p: string, withPages = true): ServicePrefixes =>
  withPages ? { track: p, album: `${p}alb`, artist: `${p}a`, playlist: `${p}pl` } : { track: p, album: null, artist: null, playlist: null }

export const SERVICES: readonly ServiceInfo[] = Object.freeze([
  {
    id: 'sc',
    key: 'soundcloud',
    name: 'SoundCloud',
    short: 'SC',
    color: '#FF5500',
    prefixes: prefixes('sc'),
    caps: ALL_CAPS,
    implemented: true,
    gender: 'm',
    nameIn: 'SoundCloud',
    openIn: 'Открыть в SoundCloud',
    status: {
      connectedAs: 'Подключён как {name}',
      connected: 'Подключён (без входа — только открытые треки)',
      disconnected: 'Без входа: поиск и открытые треки работают сами',
    },
    loginLabel: 'Войти через SoundCloud',
    loginBusyLabel: 'Войди в открывшемся окне…',
    reloginLabel: RELOGIN,
    reloginWhen: 'named',
    keyFields: [
      { name: 'client_id', label: 'client_id', secret: false, optional: false, placeholder: '32 символа' },
      { name: 'oauth_token', label: 'OAuth-токен', secret: true, optional: true, placeholder: '2-123456-…' },
    ],
    keyHint: [
      { text: 'Ключи нужны, чтобы играли и твои закрытые треки, а в W3 — подтянуть лайки и плейлисты.' },
      { raw: ' ' },
      { text: 'soundcloud.com → F12 → Сеть → любой запрос к api-v2:' },
      { raw: ' ' },
      { code: 'client_id' },
      { raw: ' ' },
      { text: 'в адресе, токен — в заголовке' },
      { raw: ' ' },
      { code: 'Authorization: OAuth …' },
      { raw: '.' },
    ],
    keyReplaceLabel: 'Заменить ключи',
  },
  {
    id: 'ym',
    key: 'yandex',
    name: 'Яндекс Музыка',
    short: 'Я',
    color: '#FFBC0D',
    prefixes: prefixes('ym'),
    caps: ALL_CAPS,
    implemented: true,
    gender: 'f',
    nameIn: 'Яндекс Музыке',
    openIn: 'Открыть в Яндекс Музыке',
    status: FEMALE_STATUS,
    loginLabel: 'Войти через Яндекс',
    loginBusyLabel: LOGIN_BUSY,
    reloginLabel: RELOGIN,
    reloginWhen: 'connected',
    keyFields: [{ name: 'token', label: 'Токен', secret: true, optional: false, placeholder: 'y0_…' }],
    keyHint: [
      { text: 'Токен вида' },
      { raw: ' ' },
      { code: 'y0_…' },
      { raw: ' (' },
      { text: 'подходит и старый' },
      { raw: ' ' },
      { code: 'AQAAAA…' },
      { raw: '). ' },
    ],
    keyReplaceLabel: 'Заменить токен',
  },
  {
    id: 'yt',
    key: 'youtube',
    name: 'YouTube Music',
    short: 'YT',
    color: '#FF0033',
    prefixes: prefixes('yt'),
    caps: { ...ALL_CAPS, key: false },
    implemented: false,
    gender: 'm',
    nameIn: 'YouTube Music',
    openIn: null,
    status: MALE_STATUS,
    loginLabel: 'Войти через YouTube Music',
    loginBusyLabel: LOGIN_BUSY,
    reloginLabel: RELOGIN,
    reloginWhen: 'connected',
    keyFields: [],
    keyHint: null,
    keyReplaceLabel: null,
  },
  {
    id: 'vk',
    key: 'vk',
    name: 'VK Музыка',
    short: 'VK',
    color: '#0077FF',
    prefixes: prefixes('vk'),
    caps: ALL_CAPS,
    implemented: false,
    gender: 'f',
    nameIn: 'VK Музыке',
    openIn: null,
    status: FEMALE_STATUS,
    loginLabel: 'Войти через VK',
    loginBusyLabel: LOGIN_BUSY,
    reloginLabel: RELOGIN,
    reloginWhen: 'connected',
    keyFields: [{ name: 'token', label: 'Токен', secret: true, optional: false, placeholder: '' }],
    keyHint: null,
    keyReplaceLabel: 'Заменить токен',
  },
  {
    id: 'sp',
    key: 'spotify',
    name: 'Spotify',
    short: 'SP',
    color: '#1ED760',
    prefixes: prefixes('sp'),
    caps: { ...ALL_CAPS, stream: false, key: false },
    implemented: false,
    gender: 'm',
    nameIn: 'Spotify',
    openIn: null,
    status: MALE_STATUS,
    loginLabel: 'Войти через Spotify',
    loginBusyLabel: LOGIN_BUSY,
    reloginLabel: RELOGIN,
    reloginWhen: 'connected',
    keyFields: [],
    keyHint: null,
    keyReplaceLabel: null,
  },
  {
    id: 'local',
    key: 'local',
    name: 'Локальные файлы',
    short: '♪',
    color: '#8E8E93',
    prefixes: prefixes('local', false),
    caps: { search: false, stream: true, library: true, playlists: false, similar: false, login: false, key: false },
    implemented: true,
    gender: 'm',
    nameIn: 'локальных файлах',
    openIn: null,
    status: MALE_STATUS,
    loginLabel: null,
    loginBusyLabel: null,
    reloginLabel: null,
    reloginWhen: 'connected',
    keyFields: [],
    keyHint: null,
    keyReplaceLabel: null,
  },
] satisfies ServiceInfo[])

export const IMPLEMENTED: readonly ServiceInfo[] = Object.freeze(SERVICES.filter((s) => s.implemented))

/** Реализованные сервисы с аккаунтом (вход или ключ): карточки «Сервисов», плейлисты сервисов,
 *  платформа главной. Локальные файлы — без аккаунта, их место — Хранилище и «На этом компьютере». */
export const ACCOUNT_SERVICES: readonly ServiceInfo[] = Object.freeze(IMPLEMENTED.filter((s) => s.caps.login || s.caps.key))

/** Трек с этого компьютера (`local:<sha1 пути>`). */
export function isLocalRef(ref: string | null | undefined): boolean {
  return serviceOf(ref) === 'local'
}

/** Сервис по короткому id ('sc') или длинному ключу ('soundcloud'). */
export function byId(idOrKey: string | null | undefined): ServiceInfo | null {
  if (!idOrKey) return null
  return SERVICES.find((s) => s.id === idOrKey || s.key === idOrKey) ?? null
}

const KINDS: readonly RefKind[] = ['track', 'album', 'artist', 'playlist']

/** Правило §1.3: префикс — до первого ':', точное совпадение (никаких startsWith). */
export function parseRef(ref: string | null | undefined): { service: ServiceInfo; kind: RefKind } | null {
  if (!ref) return null
  const colon = ref.indexOf(':')
  if (colon <= 0) return null
  const prefix = ref.slice(0, colon)
  for (const service of SERVICES) {
    const kind = KINDS.find((k) => service.prefixes[k] === prefix)
    if (kind) return { service, kind }
  }
  return null
}

export function serviceOf(ref: string | null | undefined): ServiceId | null {
  return parseRef(ref)?.service.id ?? null
}

export function refKind(ref: string | null | undefined): RefKind | null {
  return parseRef(ref)?.kind ?? null
}

/** Трек реализованного сервиса (лайки, счётчики «Мне нравится»): `sc:…` / `ym:…` / `local:…`. */
export function isTrackRef(ref: string | null | undefined): boolean {
  const parsed = parseRef(ref)
  return parsed !== null && parsed.kind === 'track' && parsed.service.implemented
}

/** Подключённые сервисы с аккаунтом, в порядке реестра. */
export function connected(list: readonly ServiceState[]): ServiceInfo[] {
  return ACCOUNT_SERVICES.filter((s) => list.some((row) => row.connected && (row.id === s.id || row.key === s.key)))
}

/** Статус сервиса из `services_status` по ключу (там только soundcloud/yandex). */
export function statusOf(status: ServicesStatus | null | undefined, service: ServiceInfo): ServiceStatus | null {
  const byKey: Partial<Record<ServiceKey, ServiceStatus>> | null | undefined = status
  return byKey?.[service.key] ?? null
}

/** Ссылка на плейлист на сайте сервиса (как раньше в PlaylistMenu.webUrl). */
export function playlistWebUrl(ref: string): string | null {
  const m = /^ympl:([^:]+):(.+)$/.exec(ref)
  if (m) return `https://music.yandex.ru/users/${m[1]}/playlists/${m[2]}`
  if (ref === 'scpl:likes') return 'https://soundcloud.com/you/likes'
  return null
}
