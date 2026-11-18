// Маршруты, которых нет в статике: GitHub Pages отдаёт на них 404.html (SITE.md §5, `/@username`).
import { normalizeUsername } from './plans'

export type MissingRoute =
  | { readonly kind: 'profile'; readonly username: string }
  | { readonly kind: 'missing' }

const PROFILE_RE = /^\/@([^/]+)\/?$/

/** `/@folzy` → профиль `folzy`; всё остальное (и неверное имя) — обычная 404. Путь — уже без языка. */
export function parseMissingRoute(rest: string): MissingRoute {
  const m = rest.match(PROFILE_RE)
  if (!m) return { kind: 'missing' }
  let raw: string
  try {
    raw = decodeURIComponent(m[1])
  } catch {
    return { kind: 'missing' }
  }
  const username = normalizeUsername(raw)
  return username ? { kind: 'profile', username } : { kind: 'missing' }
}

/**
 * Куда вернуть адрес после перехода с корневой 404 на её языковую копию (`/en/404/?from=/en/@x`).
 * Только свой путь на том же языке — иначе null (никаких чужих адресов в `history`).
 */
export function restorePath(from: string | null, lang: string): string | null {
  if (!from || !from.startsWith(`/${lang}/`) || from.startsWith('//')) return null
  if (/[\\\s]/.test(from)) return null
  return from
}
