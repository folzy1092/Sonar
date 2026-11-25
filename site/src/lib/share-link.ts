// Ссылка «Поделиться» треком: `https://try-sonar.ru/t/#<данные>` (docs/SPACE_SHARE_PROMPT.md §3).
// Данные — в хэше: серверу Pages не уходят, страница одна, роутер не нужен. Компактный JSON → UTF-8 →
// base64url. Без личного: ни токенов, ни логина, ни `?si=`-трекеров.
//
// Файл — в двух местах, байт в байт: `site/src/lib/share-link.ts` и `windows/src/lib/share-link.ts`
// (тест сайта сверяет). Формат на iPhone — `ios/Sonar/Core/Share/ShareLink.swift`; общий пример —
// `site/src/lib/share-link.fixture.json`, его читают тесты всех трёх.

export const SHARE_VERSION = 1
/** Длиннее — выкидываем обложку (сайт возьмёт превью YouTube, если есть). */
export const SHARE_MAX_LEN = 600
/** Название и артист — не длиннее (обрезаем, а не ломаем ссылку). */
const TEXT_MAX = 160

export type ShareService = 'ym' | 'sc' | 'yt' | 'sp'
export const SHARE_SERVICES: readonly ShareService[] = ['ym', 'sc', 'yt', 'sp']
/** Что сайт может сыграть целиком без входа. */
export type SharePlayer = 'yt' | 'sc'

export interface ShareData {
  /** Название. */
  t: string
  /** Артист. */
  a: string
  /** Длительность, с. */
  d?: number
  /** Обложка: https и только с хостов сервисов. */
  c?: string
  /** Откуда делились. */
  src: ShareService
  /** Id трека в каждом сервисе, где он нашёлся (без префикса ref). */
  ids: Partial<Record<ShareService, string>>
  /** Путь SoundCloud «user/slug» — для кнопки (по одному числовому id страницу трека не открыть). */
  sl?: string
  /** Что играть на сайте по умолчанию. */
  play?: SharePlayer
  /** Кто поделился — `@username` без «@», если вошёл в аккаунт Sonar. Аватара нет: до сервера его негде взять. */
  by?: string
}

const ID_RE: Record<ShareService, RegExp> = {
  ym: /^\d{1,12}$/,
  sc: /^\d{1,14}$/,
  yt: /^[\w-]{11}$/,
  sp: /^[A-Za-z0-9]{22}$/,
}
const SC_PATH_RE = /^[\w-]{1,80}\/[\w-]{1,160}$/
/** @username — как на сервере (API.md): латиница, цифры и «_», 3–32 знака. */
const BY_RE = /^[A-Za-z0-9_]{3,32}$/
/** Хосты обложек: SoundCloud, Яндекс, YouTube / Google, Spotify. */
const COVER_HOST_RE =
  /^(?:i\d?\.sndcdn\.com|avatars\.yandex\.net|i\d?\.ytimg\.com|(?:lh\d|yt\d)\.googleusercontent\.com|i\.scdn\.co|[\w-]+\.spotifycdn\.com)$/

export const isShareService = (v: unknown): v is ShareService =>
  typeof v === 'string' && (SHARE_SERVICES as readonly string[]).includes(v)

export function validId(service: ShareService, id: unknown): id is string {
  return typeof id === 'string' && ID_RE[service].test(id)
}

export function validCover(url: unknown): url is string {
  if (typeof url !== 'string' || url.length > 400) return false
  try {
    const u = new URL(url)
    return u.protocol === 'https:' && !u.username && !u.password && !u.port && COVER_HOST_RE.test(u.hostname)
  } catch {
    return false
  }
}

const clip = (s: string) => {
  const one = s.replace(/\s+/g, ' ').trim()
  return one.length > TEXT_MAX ? `${one.slice(0, TEXT_MAX - 1)}…` : one
}

/**
 * Что сайт играет: YouTube (всегда целиком), иначе SoundCloud, если трек не Go+-отрывок.
 * Яндекс и Spotify во встройке без входа — 30 секунд, их не играем.
 */
export function pickPlay(ids: ShareData['ids'], scFull: boolean): SharePlayer | undefined {
  if (ids.yt) return 'yt'
  if (ids.sc && scFull) return 'sc'
  return undefined
}

/** «user/slug» из ссылки SoundCloud (без `?si=` и прочего); не трек — undefined. */
export function scPath(url: string | null | undefined): string | undefined {
  if (!url) return undefined
  try {
    const u = new URL(url)
    if (!/^(?:www\.|m\.)?soundcloud\.com$/.test(u.hostname)) return undefined
    const path = u.pathname.replace(/^\/+|\/+$/g, '')
    if (!SC_PATH_RE.test(path) || /^(?:discover|search|you|stations|charts)\//.test(path)) return undefined
    return path
  } catch {
    return undefined
  }
}

/** Чистые данные: лишнее и битое — прочь. Ничего не нашлось вовсе — null. */
export function normalize(raw: unknown): ShareData | null {
  if (!raw || typeof raw !== 'object') return null
  const r = raw as Record<string, unknown>
  if (r.v !== SHARE_VERSION) return null
  const t = typeof r.t === 'string' ? clip(r.t) : ''
  const a = typeof r.a === 'string' ? clip(r.a) : ''
  if (!t || !isShareService(r.src)) return null
  const ids: ShareData['ids'] = {}
  const rawIds = r.ids && typeof r.ids === 'object' ? (r.ids as Record<string, unknown>) : {}
  for (const s of SHARE_SERVICES) if (validId(s, rawIds[s])) ids[s] = rawIds[s] as string
  const out: ShareData = { t, a, src: r.src, ids }
  if (typeof r.d === 'number' && Number.isFinite(r.d) && r.d > 0 && r.d < 6 * 3600) out.d = Math.round(r.d)
  if (validCover(r.c)) out.c = r.c
  if (typeof r.sl === 'string' && SC_PATH_RE.test(r.sl)) out.sl = r.sl
  if ((r.play === 'yt' || r.play === 'sc') && ids[r.play]) out.play = r.play
  if (typeof r.by === 'string' && BY_RE.test(r.by)) out.by = r.by
  return out
}

// ——— base64url поверх UTF-8 (без Buffer: и в браузере, и в WebView) ———

function toBase64Url(text: string): string {
  let bin = ''
  for (const b of new TextEncoder().encode(text)) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function fromBase64Url(s: string): string | null {
  if (!/^[\w-]*$/.test(s)) return null
  try {
    const bin = atob(s.replace(/-/g, '+').replace(/_/g, '/'))
    const bytes = Uint8Array.from(bin, (ch) => ch.charCodeAt(0))
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes)
  } catch {
    return null
  }
}

/** Порядок полей — постоянный: одинаковые данные дают одинаковую ссылку (и на iPhone тоже). */
function serialize(d: ShareData): string {
  const ids: Record<string, string> = {}
  for (const s of SHARE_SERVICES) if (d.ids[s]) ids[s] = d.ids[s] as string
  // undefined JSON.stringify пропускает — порядок ключей остаётся этим
  return JSON.stringify({ v: SHARE_VERSION, t: d.t, a: d.a, d: d.d || undefined, c: d.c, src: d.src, ids, sl: d.sl, play: d.play, by: d.by })
}

export function encodeShare(data: ShareData): string {
  const clean = normalize({ ...data, v: SHARE_VERSION })
  if (!clean) throw new Error('share: нечем делиться')
  const full = toBase64Url(serialize(clean))
  if (full.length <= SHARE_MAX_LEN || !clean.c) return full
  return toBase64Url(serialize({ ...clean, c: undefined }))
}

/** Хэш страницы (`#…` или без решётки) → данные; битое — null. */
export function decodeShare(hash: string): ShareData | null {
  const json = fromBase64Url(hash.replace(/^#/, '').trim())
  if (json === null) return null
  try {
    return normalize(JSON.parse(json))
  } catch {
    return null
  }
}

/** Полная ссылка. Не русский — `/en/t/` и т. п., чтобы друг открыл страницу на твоём языке. */
export function shareUrl(data: ShareData, lang = 'ru', site = 'https://try-sonar.ru'): string {
  const prefix = lang && lang !== 'ru' ? `/${lang}` : ''
  return `${site}${prefix}/t/#${encodeShare(data)}`
}
