// Обложки для коллажа без повторов (docs/POLISH_PROMPT.md п. 1). Зеркало — Rust `covers.rs` (плейлисты
// и умные плейлисты) и iPhone `Core/Library/Covers.swift`.
//
// Повтор — тот же альбом, тот же адрес картинки после нормализации (без размера, схемы и `?…`)
// или, у трека без альбома, тот же исполнитель + адрес. Идём по списку по порядку и останавливаемся
// на четвёртой разной — порядок стабильный. Итог для показа: 4 разные → сетка 2×2; 1–3 → одна
// (первая) обложка во всю плитку: сетка с повтором выглядит как баг; 0 → пусто (значок).
// Сравнение по пикселям (perceptual hash) — потом, если повторы всё ещё будут видны.

/** Сколько обложек в сетке коллажа. */
export const COLLAGE_SIZE = 4

export interface CoverSource {
  cover_url: string | null
  artist?: string
  album?: { ref: string } | null
}

/** Адрес обложки без схемы, `?…`, `#…` и размера (SoundCloud, Яндекс, YouTube). */
export function coverKey(url: string): string {
  let u = url.trim()
  const proxied = /\/cover\?u=([^&#]+)/.exec(u)
  if (proxied) {
    try {
      u = decodeURIComponent(proxied[1])
    } catch {
      // битый адрес прокси — сравниваем как есть
    }
  }
  return u
    .replace(/^[a-z][a-z0-9+.-]*:\/\//i, '')
    .replace(/^\/\//, '')
    .replace(/[?#].*$/, '')
    .replace(/-(t\d+x\d+|large|crop|original|small|tiny|badge|mini|medium)(\.\w+)$/i, '$2')
    .replace(/\/(%%|m?\d+x\d+)$/i, '')
    .replace(/=(w\d+-h\d+|s\d+)[^/]*$/i, '')
    .toLowerCase()
}

/** Ключи, по которым обложка считается повтором уже показанной. */
function keysOf(t: CoverSource, url: string): string[] {
  const key = coverKey(url)
  const keys = [`u:${key}`]
  if (t.album?.ref) keys.push(`a:${t.album.ref}`)
  else keys.push(`p:${(t.artist ?? '').trim().toLowerCase()}|${key}`)
  return keys
}

/** До `n` разных обложек по порядку списка. */
export function distinctCovers(tracks: readonly CoverSource[], n = COLLAGE_SIZE): string[] {
  const seen = new Set<string>()
  const out: string[] = []
  for (const t of tracks) {
    if (out.length >= n) break
    if (!t.cover_url) continue
    const keys = keysOf(t, t.cover_url)
    if (keys.some((k) => seen.has(k))) continue
    keys.forEach((k) => seen.add(k))
    out.push(t.cover_url)
  }
  return out
}

/** Что рисовать: 4 разные — сетка, иначе одна первая обложка, или пусто. */
export function collage(tracks: readonly CoverSource[]): string[] {
  const covers = distinctCovers(tracks)
  return covers.length >= COLLAGE_SIZE ? covers : covers.slice(0, 1)
}
