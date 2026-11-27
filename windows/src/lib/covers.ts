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

/**
 * Обложка в размере под место на экране (память WebView2, 2026-11-27): сервисы отдают 400–640 px, а в строке
 * списка картинка 44 px — каждая декодированная 500×500 весит ~1 МБ, тысяча строк Любимых — гигабайт.
 * Берём ближайший размер сервиса не меньше `cssPx × dpr`; только уменьшаем, неизвестный адрес — как есть.
 * Ключ коллажей (`coverKey`) от размера не зависит — повторы ловятся по-прежнему.
 */
export function thumbUrl(url: string, cssPx: number, dpr = 1): string {
  const need = Math.ceil(cssPx * Math.max(1, dpr))
  // SoundCloud: -large (100) · -t300x300 · -t500x500 / -crop / -original
  if (/\.sndcdn\.com\//i.test(url)) {
    const m = /-(t500x500|t300x300|crop|original)(\.\w+)(\?.*)?$/i.exec(url)
    if (!m) return url
    const to = need <= 100 ? 'large' : need <= 300 ? 't300x300' : null
    if (!to || to === m[1]) return url
    return url.slice(0, m.index) + `-${to}${m[2]}${m[3] ?? ''}`
  }
  // Яндекс: …/400x400 → 100x100 / 200x200
  if (/avatars\.(mds\.)?yandex\.net\//i.test(url)) {
    const m = /\/(\d+)x(\d+)$/.exec(url)
    if (!m) return url
    const side = need <= 100 ? 100 : need <= 200 ? 200 : null
    return side && side < +m[1] ? url.slice(0, m.index) + `/${side}x${side}` : url
  }
  // YouTube Music / Google: =w544-h544… или =s544
  if (/\.(googleusercontent|ggpht)\.com\//i.test(url)) {
    const side = need <= 120 ? 120 : need <= 240 ? 240 : null
    if (!side) return url
    return url.replace(/=w(\d+)-h(\d+)/, (s, w) => (+w > side ? `=w${side}-h${side}` : s)).replace(/=s(\d+)(?=[-?]|$)/, (s, w) => (+w > side ? `=s${side}` : s))
  }
  // Spotify: обложка альбома 640 → 300 / 64
  if (/i\.scdn\.co\/image\/ab67616d0000b273/i.test(url)) {
    return need <= 64 ? url.replace(/ab67616d0000b273/i, 'ab67616d00004851') : need <= 300 ? url.replace(/ab67616d0000b273/i, 'ab67616d00001e02') : url
  }
  return url
}
