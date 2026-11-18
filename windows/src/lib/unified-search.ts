// Единый поиск (NEXT_PROMPT этап 14, решение владельца 2026-11-18): один список по всем сервисам,
// сверху — предпочтительный сервис из настроек (`search.preferred`), дальше — по порядку
// `audio.fallback_order`. Один и тот же трек из разных сервисов — одна строка: остаётся версия того
// сервиса, что стоит выше. Сервис не подключён или упал — просто молча выпадает из выдачи.
import type { Album, Artist, SearchMore, ServicePlaylist, Track } from './api'
import { fallbackOrder } from './fallback'
import { byId, IMPLEMENTED, type ServiceId } from './services'

/** Сервисы, по которым ищет единый поиск: реализованы и умеют искать (локальные файлы — своим блоком). */
export const searchableServices = (): ServiceId[] =>
  IMPLEMENTED.filter((s) => s.caps.search && s.id !== 'local').map((s) => s.id)

/** Порядок выдачи: предпочтительный первым, остальные — как в резерве, затем все прочие с поиском. */
export function searchOrder(preferred: unknown, savedFallback: unknown): ServiceId[] {
  const all = searchableServices()
  const out: ServiceId[] = []
  const pref = typeof preferred === 'string' ? byId(preferred)?.id : undefined
  if (pref && all.includes(pref)) out.push(pref)
  for (const id of fallbackOrder(savedFallback)) if (all.includes(id) && !out.includes(id)) out.push(id)
  for (const id of all) if (!out.includes(id)) out.push(id)
  return out
}

/** Сервис по ref: `ym:123` → 'ym', `ympl:…` → 'ym'. */
export function serviceOfRef(ref: string): ServiceId | null {
  const prefix = ref.slice(0, ref.indexOf(':'))
  for (const s of IMPLEMENTED) {
    const p = s.prefixes
    if ([p.track, p.album, p.artist, p.playlist].includes(prefix)) return s.id
  }
  return null
}

/** Для сравнения: регистр, «ё», скобки «(feat. …)», «- Remastered», знаки и лишние пробелы прочь. */
export function normalizeName(s: string): string {
  return s
    .toLowerCase()
    .replace(/ё/g, 'е')
    .replace(/[([](feat|ft|prod|with)\.?[^)\]]*[)\]]/g, ' ')
    .replace(/\s(feat|ft)\.?\s.*$/, ' ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
}

/** Главный артист: «A, B», «A & B», «A feat. B» → «a». */
const mainArtist = (s: string) => normalizeName(s.split(/,|&| x | feat\.? | ft\.? /i)[0] ?? s)

/** Ключ «один и тот же трек»: название + главный артист; длительность отличается больше 10 с — разные. */
export function trackKey(t: Pick<Track, 'title' | 'artist'>): string {
  return `${normalizeName(t.title)}\u0000${mainArtist(t.artist)}`
}

const SAME_TRACK_MS = 10_000

/** Списки по сервисам → один список в порядке `order`, без повторов. */
export function mergeTracks(byService: Partial<Record<ServiceId, Track[]>>, order: readonly ServiceId[]): Track[] {
  const out: Track[] = []
  const seen = new Map<string, number[]>()
  for (const id of order) {
    for (const t of byService[id] ?? []) {
      const key = trackKey(t)
      const lens = seen.get(key) ?? []
      const dupe = lens.some((ms) => !ms || !t.duration_ms || Math.abs(ms - t.duration_ms) <= SAME_TRACK_MS)
      if (dupe) continue
      seen.set(key, [...lens, t.duration_ms])
      out.push(t)
    }
  }
  return out
}

function mergeBy<T>(lists: (T[] | undefined)[], key: (x: T) => string): T[] {
  const out: T[] = []
  const seen = new Set<string>()
  for (const list of lists)
    for (const x of list ?? []) {
      const k = key(x)
      if (seen.has(k)) continue
      seen.add(k)
      out.push(x)
    }
  return out
}

/** Артисты, альбомы и плейлисты сервисов — тем же порядком; артист и альбом склеиваются по имени. */
export function mergeMore(byService: Partial<Record<ServiceId, SearchMore>>, order: readonly ServiceId[]): SearchMore {
  const lists = order.map((id) => byService[id])
  return {
    artists: mergeBy<Artist>(lists.map((m) => m?.artists), (a) => normalizeName(a.name)),
    albums: mergeBy<Album>(lists.map((m) => m?.albums), (a) => `${normalizeName(a.title)}\u0000${mainArtist(a.artist)}`),
    playlists: mergeBy<ServicePlaylist>(lists.map((m) => m?.playlists), (p) => p.ref),
  }
}
