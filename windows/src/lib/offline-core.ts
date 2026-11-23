// Офлайн-режим (`docs/OFFLINE.md`): чистые помощники для экранов и плеера — без Tauri, проверяются тестами.
// Что доступно, знает Rust (`offline_refs`: кэш треков, локальные файлы, двойники из кэша); здесь только фильтры.

interface TrackLike {
  ref: string
  title: string
  artist: string
  album?: { title: string } | null
}

/** Трек играет без сети. Режим выключен — играет всё. */
export function isAvailable(ref: string, on: boolean, refs: ReadonlySet<string>): boolean {
  return !on || refs.has(ref)
}

/** Только то, что играет без сети (порядок тот же). */
export function availableOnly<T extends { ref: string }>(tracks: readonly T[], on: boolean, refs: ReadonlySet<string>): T[] {
  return on ? tracks.filter((t) => refs.has(t.ref)) : [...tracks]
}

/** Без повторов по ref, первый встреченный остаётся. */
export function uniqueByRef<T extends { ref: string }>(tracks: readonly T[]): T[] {
  const seen = new Set<string>()
  return tracks.filter((t) => !seen.has(t.ref) && (seen.add(t.ref), true))
}

function norm(s: string): string {
  return s.toLocaleLowerCase().replace(/\s+/g, ' ').trim()
}

/** Поиск в офлайне — по скачанному и локальному: все слова запроса есть в названии, исполнителе или альбоме. */
export function searchOffline<T extends TrackLike>(pool: readonly T[], query: string, limit: number): T[] {
  const words = norm(query).split(' ').filter(Boolean)
  if (!words.length) return []
  const hits = pool.filter((t) => {
    const hay = norm(`${t.title} ${t.artist} ${t.album?.title ?? ''}`)
    return words.every((w) => hay.includes(w))
  })
  return uniqueByRef(hits).slice(0, limit)
}

/** Автопродолжение без сети: случайные доступные треки, которых нет в очереди и которые не «не нравится». */
export function autoplayFromPool<T extends { ref: string }>(
  pool: readonly T[],
  inQueue: ReadonlySet<string>,
  disliked: (ref: string) => boolean,
  n: number,
  rand: () => number = Math.random,
): T[] {
  const left = uniqueByRef(pool).filter((t) => !inQueue.has(t.ref) && !disliked(t.ref))
  // Фишер — Йетс на копии
  const out = [...left]
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1))
    ;[out[i], out[j]] = [out[j], out[i]]
  }
  return out.slice(0, n)
}

const LOCAL_HOSTS = new Set(['127.0.0.1', 'localhost', '[::1]'])

/**
 * Адрес картинки для `<img>`: в офлайне чужой адрес (CDN обложек, аватары) уходит на локальный `/cover`
 * (`stream.rs`) — он отдаёт файл из кэша на диске, а без кэша отвечает ошибкой, не выходя в сеть.
 * Порт ещё не известен — `undefined`: картинки нет, запроса тоже. Локальное, `data:`, `blob:` и ресурсы
 * сборки — как есть.
 */
export function imageSrc(url: string | null | undefined, on: boolean, port: number | null): string | undefined {
  if (!url) return undefined
  if (!on) return url
  let parsed: URL
  try {
    parsed = new URL(url)
  } catch {
    return url
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return url
  if (LOCAL_HOSTS.has(parsed.hostname)) return url
  if (port == null) return undefined
  return `http://127.0.0.1:${port}/cover?u=${encodeURIComponent(url)}`
}
