// Карта исполнителей — вызовы Rust (src-tauri/src/artist_graph/). Типы — как в build.rs.
// Свой `call`, а не общий lib/api.ts: модуль карты самостоятельный и не трогает общий файл.
import { invoke } from '@tauri-apps/api/core'
import { listen, type UnlistenFn } from '@tauri-apps/api/event'
import { isTauri } from '../tauri'
import { t } from '../i18n.svelte'
import { api, rawError, type Track } from '../api'

export type Follow = 'mutual' | 'one_way'

/** Почему два исполнителя рядом. */
export interface MapReasons {
  feats: number
  prods: number
  follow: Follow | null
  /** Имена общих соавторов (до трёх); всего — `common_count`. */
  common: string[]
  common_count: number
  similar: number
}

export interface MapNode {
  /** Ключ исполнителя (буквы и цифры в нижнем регистре) — по нему рёбра. */
  key: string
  name: string
  /** Ссылки в сервисах: `sca:…`, `yma:…`. */
  refs: string[]
  avatar_url: string | null
  tracks: number
  plays: number
  weight: number
  /** `false` — сосед снаружи медиатеки, рисуется бледнее. */
  discovered: boolean
}

export interface MapEdge {
  a: string
  b: string
  weight: number
  reasons: MapReasons
}

export interface MapGraph {
  nodes: MapNode[]
  edges: MapEdge[]
}

export interface Neighbor {
  key: string
  name: string
  weight: number
  discovered: boolean
}

/** Ход фоновой подкачки подписок SoundCloud. */
export interface FollowProgress {
  done: number
  total: number
  state: 'running' | 'done' | 'paused' | 'stopped'
}

const DEFAULT_RELATED = 12
const MAX_NEIGHBORS = 50

function call<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  if (!isTauri) return Promise.reject(new Error(t('Работает только в приложении (npm run tauri dev)')))
  return invoke<T>(cmd, args)
}

export const mapApi = {
  graph: () => call<MapGraph>('artist_graph'),
  neighbors: (name: string, limit?: number) => call<Neighbor[]>('artist_neighbors', { name, limit }),
  clusterTracks: (names: string[], limit?: number) => call<Track[]>('artist_cluster_tracks', { names, limit }),
  /** Подкачать подписки и лайки сервисов сейчас (фоном). */
  refresh: () => call<void>('artist_graph_refresh'),
}

/** Соседи исполнителя по карте — имена, сильные первыми. Для «Похоже на» / «Для тебя» на главной.
 *  `onlyNew` — только тех, кого ещё нет в медиатеке. Ошибка уходит в журнал, ответ — пустой список. */
export async function related(artistName: string, opts: { limit?: number; onlyNew?: boolean } = {}): Promise<string[]> {
  const limit = opts.limit ?? DEFAULT_RELATED
  try {
    const list = await mapApi.neighbors(artistName, opts.onlyNew ? MAX_NEIGHBORS : limit)
    const picked = opts.onlyNew ? list.filter((n) => !n.discovered) : list
    return picked.slice(0, limit).map((n) => n.name)
  } catch (e) {
    if (isTauri) void api.logFrontend('warn', `карта исполнителей: соседи «${artistName}»: ${rawError(e)}`).catch(() => {})
    return []
  }
}

/** Подписка на события подкачки: ход и «граф обновился». */
export async function onMapEvents(handlers: {
  progress?: (p: FollowProgress) => void
  updated?: () => void
}): Promise<UnlistenFn> {
  if (!isTauri) return () => {}
  const off = await Promise.all([
    listen<FollowProgress>('artist-graph-progress', (e) => handlers.progress?.(e.payload)),
    listen('artist-graph-updated', () => handlers.updated?.()),
  ])
  return () => off.forEach((f) => f())
}
