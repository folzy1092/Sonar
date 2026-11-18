// Вид профиля (Аккаунт → Профиль, SETTINGS_NEXT «Профиль»): цвет, шрифт и эффект ника, раскладка шапки,
// ссылки и витрина. Только чистые функции и списки — экран (pages/settings/Profile.svelte) и превью
// (components/profile/ProfileCard.svelte) берут всё отсюда. До сервера хранится в `profile.*`
// настройках, с сервером уйдёт в PATCH /me. Уровней и значков нет (решение владельца 2026-11-18).
import type { Album, Artist, Playlist, Track } from './api'

/** Цвет профиля: красит ник, кольцо аватара и акценты профиля. Пусто — цвет темы. */
export const PROFILE_COLORS = [
  { id: 'red', hex: '#ff5a5f' },
  { id: 'orange', hex: '#ff9f43' },
  { id: 'yellow', hex: '#ffd23f' },
  { id: 'lime', hex: '#a3e635' },
  { id: 'green', hex: '#2ecc71' },
  { id: 'teal', hex: '#22d3c5' },
  { id: 'blue', hex: '#4c8dff' },
  { id: 'violet', hex: '#8b5cf6' },
  { id: 'pink', hex: '#f472b6' },
  { id: 'white', hex: '#f4f4f5' },
] as const

export type ProfileColor = (typeof PROFILE_COLORS)[number]['id']

/** Hex цвета профиля; '' или неизвестное — null (берётся цвет темы). */
export function colorHex(id: string): string | null {
  return PROFILE_COLORS.find((c) => c.id === id)?.hex ?? null
}

/** Шрифты ника — из уже встроенных (theme/fonts.css, fontsource, открытые лицензии). */
export const NICK_FONTS = [
  { id: 'default', label: 'По умолчанию', family: null },
  { id: 'caveat', label: 'Caveat', family: 'Caveat Variable' },
  { id: 'marck', label: 'Marck', family: 'Marck Script' },
  { id: 'pacifico', label: 'Pacifico', family: 'Pacifico' },
  { id: 'lobster', label: 'Lobster', family: 'Lobster' },
  { id: 'amatic', label: 'Amatic', family: 'Amatic SC' },
  { id: 'pixel', label: 'Pixel', family: 'Pixelify Sans Variable' },
  { id: 'retro', label: 'Retro', family: 'Press Start 2P' },
  { id: 'russo', label: 'Russo', family: 'Russo One' },
  { id: 'unbounded', label: 'Unbounded', family: 'Unbounded Variable' },
  { id: 'tektur', label: 'Tektur', family: 'Tektur Variable' },
  { id: 'dela', label: 'Dela', family: 'Dela Gothic One' },
] as const

export type NickFont = (typeof NICK_FONTS)[number]['id']

/** CSS `font-family` шрифта ника; по умолчанию и неизвестное — null (шрифт интерфейса). */
export function nickFontStack(id: string): string | null {
  const family = NICK_FONTS.find((f) => f.id === id)?.family
  return family ? `'${family}', 'Inter Variable', 'Segoe UI', sans-serif` : null
}

/** Эффект ника. */
export const NICK_EFFECTS = [
  { id: 'none', label: 'Без эффекта' },
  { id: 'shimmer', label: 'Переливающийся' },
  { id: 'neon', label: 'Неон' },
  { id: 'cartoon', label: 'Мультфильм' },
  { id: 'highlight', label: 'Выделение' },
  { id: '3d', label: '3D' },
  { id: 'retro', label: 'Ретро' },
] as const

export type NickEffect = (typeof NICK_EFFECTS)[number]['id']

/** Вид шапки профиля: С аватаром · Большой ник · Баннер-обложка · По центру. */
export const PROFILE_LAYOUTS = [
  { id: 'avatar', label: 'С аватаром' },
  { id: 'big_name', label: 'Большой ник' },
  { id: 'banner', label: 'Баннер-обложка' },
  { id: 'center', label: 'По центру' },
] as const

export type ProfileLayout = (typeof PROFILE_LAYOUTS)[number]['id']

// ── Ссылки ───────────────────────────────────────────────────────────────────

export type LinkKind = 'telegram' | 'discord' | 'site'
export interface ProfileLink {
  kind: LinkKind
  url: string
}

export const LINKS_MAX = 5
const TELEGRAM_HOSTS = ['t.me', 'telegram.me', 'telegram.dog']
const DISCORD_HOSTS = ['discord.gg', 'discord.com', 'discordapp.com']
const TG_HANDLE = /^@?([a-z0-9_]{5,32})$/i

/**
 * Что ввёл человек → ссылка профиля. `@name` — Telegram, адрес Telegram или Discord узнаётся по домену,
 * любой другой http(s)-адрес — сайт. Без протокола дописывается https://. Не ссылка — null.
 */
export function parseLink(input: string): ProfileLink | null {
  const raw = input.trim()
  if (!raw) return null
  const handle = raw.match(TG_HANDLE)
  if (handle && raw.startsWith('@')) return { kind: 'telegram', url: `https://t.me/${handle[1]}` }
  let url: URL
  try {
    url = new URL(/^[a-z][a-z0-9+.-]*:\/\//i.test(raw) ? raw : `https://${raw}`)
  } catch {
    return null
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return null
  if (!url.hostname.includes('.')) return null
  const host = url.hostname.replace(/^www\./, '').toLowerCase()
  const kind: LinkKind = TELEGRAM_HOSTS.includes(host) ? 'telegram' : DISCORD_HOSTS.includes(host) ? 'discord' : 'site'
  return { kind, url: url.toString() }
}

/** Короткая подпись ссылки для капсулы: без протокола, www и косой черты в конце. */
export function linkLabel(link: ProfileLink): string {
  return link.url.replace(/^https?:\/\//, '').replace(/^www\./, '').replace(/\/$/, '')
}

/** Новый список со ссылкой в конце; та же ссылка или предел — список как был. */
export function addLink(links: readonly ProfileLink[], link: ProfileLink): ProfileLink[] {
  if (links.length >= LINKS_MAX || links.some((l) => l.url === link.url)) return [...links]
  return [...links, link]
}

export const removeLink = (links: readonly ProfileLink[], url: string): ProfileLink[] => links.filter((l) => l.url !== url)

// ── Витрина ──────────────────────────────────────────────────────────────────

export type ShowcaseKind = 'playlist' | 'album' | 'artist' | 'track'
export interface ShowcaseItem {
  kind: ShowcaseKind
  /** id плейлиста Sonar или ref сервиса (`sc:…`, `ym:…`). */
  ref: string
  title: string
  subtitle: string
  cover_url: string | null
}

export const SHOWCASE_MAX = 6

const sameItem = (a: ShowcaseItem, b: { kind: ShowcaseKind; ref: string }) => a.kind === b.kind && a.ref === b.ref

/** Можно ли поставить в витрину: плейлист, скрытый «от других», — нельзя. */
export function canShowcase(item: Pick<ShowcaseItem, 'kind' | 'ref'>, hiddenPlaylists: readonly string[]): boolean {
  return item.kind !== 'playlist' || !hiddenPlaylists.includes(item.ref)
}

/** Новая витрина с местом в конце; повтор, полная витрина или скрытый плейлист — как была. */
export function addShowcase(list: readonly ShowcaseItem[], item: ShowcaseItem, hiddenPlaylists: readonly string[] = []): ShowcaseItem[] {
  if (list.length >= SHOWCASE_MAX || list.some((i) => sameItem(i, item)) || !canShowcase(item, hiddenPlaylists)) return [...list]
  return [...list, item]
}

export const removeShowcase = (list: readonly ShowcaseItem[], kind: ShowcaseKind, ref: string): ShowcaseItem[] =>
  list.filter((i) => !sameItem(i, { kind, ref }))

/** Что увидят другие: плейлист, который позже скрыли, из витрины пропадает сам. */
export const visibleShowcase = (list: readonly ShowcaseItem[], hiddenPlaylists: readonly string[]): ShowcaseItem[] =>
  list.filter((i) => canShowcase(i, hiddenPlaylists)).slice(0, SHOWCASE_MAX)

/** Место витрины из медиатеки или поиска. */
export const showcasePlaylist = (p: Pick<Playlist, 'id' | 'name' | 'covers'>, subtitle = ''): ShowcaseItem => ({
  kind: 'playlist',
  ref: p.id,
  title: p.name,
  subtitle,
  cover_url: p.covers[0] ?? null,
})
export const showcaseTrack = (tr: Pick<Track, 'ref' | 'title' | 'artist' | 'cover_url'>): ShowcaseItem => ({
  kind: 'track',
  ref: tr.ref,
  title: tr.title,
  subtitle: tr.artist,
  cover_url: tr.cover_url,
})
export const showcaseAlbum = (a: Pick<Album, 'ref' | 'title' | 'artist' | 'cover_url'>): ShowcaseItem => ({
  kind: 'album',
  ref: a.ref,
  title: a.title,
  subtitle: a.artist,
  cover_url: a.cover_url,
})
export const showcaseArtist = (a: Pick<Artist, 'ref' | 'name' | 'avatar_url'>): ShowcaseItem => ({
  kind: 'artist',
  ref: a.ref,
  title: a.name,
  subtitle: '',
  cover_url: a.avatar_url,
})

/** Значение из настроек → витрина: битые записи отбрасываются (настройки приходят и из синхронизации). */
export function readShowcase(v: unknown): ShowcaseItem[] {
  if (!Array.isArray(v)) return []
  const kinds: readonly string[] = ['playlist', 'album', 'artist', 'track']
  return v
    .filter((i): i is ShowcaseItem => !!i && typeof i === 'object' && kinds.includes(i.kind) && typeof i.ref === 'string' && typeof i.title === 'string')
    .map((i) => ({ kind: i.kind, ref: i.ref, title: i.title, subtitle: typeof i.subtitle === 'string' ? i.subtitle : '', cover_url: typeof i.cover_url === 'string' ? i.cover_url : null }))
    .slice(0, SHOWCASE_MAX)
}

/** То же для ссылок. */
export function readLinks(v: unknown): ProfileLink[] {
  if (!Array.isArray(v)) return []
  return v
    .map((l) => (l && typeof l === 'object' && typeof l.url === 'string' ? parseLink(l.url) : null))
    .filter((l): l is ProfileLink => l !== null)
    .slice(0, LINKS_MAX)
}
