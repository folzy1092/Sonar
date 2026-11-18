// Импорт плейлиста по ссылке (NEXT_PROMPT этап 5) — чистая логика экрана: события прогресса
// `import:progress` (src-tauri/src/import_link.rs) складываются в состояние без мутаций, из него —
// сводка «Нашлось N из M», ненайденные и треки нового плейлиста. Подбор пар — в Rust
// (services/import.rs, той же сверкой, что и резервный сервис).
import type { Track } from './api'
import type { ServiceId } from './services'
import { servicesQuery } from './local'

/** Apple Music: своего сервиса в Sonar нет — только источник импорта (значок, подпись). */
export const APPLE_MUSIC = 'am'
/** Сервис источника импорта: сервис реестра или Apple Music. */
export type ImportService = ServiceId | typeof APPLE_MUSIC

/** Откуда переносим (`ImportHead` в services/import.rs). */
export interface ImportHead {
  service: ImportService
  album: boolean
  title: string
  owner: string
  cover_url: string | null
  /** Сколько треков в источнике: у Apple Music страница отдаёт не все — тогда больше, чем прочитано. */
  total: number
  /** ref плейлиста/альбома сервиса или адрес страницы Apple Music. */
  source: string
}

/** kept — трек сервиса, который сам играет; found — нашлась пара; missing — пары нет. */
export type StepStatus = 'kept' | 'found' | 'missing'

export interface ImportStep {
  index: number
  status: StepStatus
  /** Что попадёт в плейлист: сам трек или найденная пара. */
  track: Track | null
}

export interface ImportResult {
  head: ImportHead
  tracks: Track[]
  steps: ImportStep[]
}

/** Событие `import:progress`: сначала шапка и треки, потом шаг на каждый трек (в любом порядке). */
export type ImportProgress =
  | { kind: 'head'; job: string; head: ImportHead; tracks: Track[] }
  | { kind: 'step'; job: string; step: ImportStep }

export interface ImportState {
  head: ImportHead | null
  /** Треки источника по порядку. */
  tracks: readonly Track[]
  /** Шаг на трек того же номера; `null` — ещё ищется. */
  steps: readonly (ImportStep | null)[]
}

export const EMPTY_IMPORT: ImportState = Object.freeze({ head: null, tracks: [], steps: [] })

/** Новое состояние после события (прежнее не меняется). */
export function applyProgress(state: ImportState, ev: ImportProgress): ImportState {
  if (ev.kind === 'head') return { head: ev.head, tracks: ev.tracks, steps: ev.tracks.map(() => null) }
  const { index } = ev.step
  if (index < 0 || index >= state.steps.length) return state
  return { ...state, steps: state.steps.map((s, i) => (i === index ? ev.step : s)) }
}

/** Итог команды `import_link` — окончательное состояние (события могли не дойти). */
export function fromResult(r: ImportResult): ImportState {
  return r.steps.reduce<ImportState>(
    (s, step) => applyProgress(s, { kind: 'step', job: '', step }),
    applyProgress(EMPTY_IMPORT, { kind: 'head', job: '', head: r.head, tracks: r.tracks }),
  )
}

export interface ImportSummary {
  /** Сколько треков уже проверено. */
  checked: number
  /** Нашлось: свои треки играющих сервисов + найденные пары. */
  matched: number
  /** Сколько треков прочитано из источника. */
  total: number
  /** Номера ненайденных треков по порядку. */
  missing: number[]
  done: boolean
}

export function importSummary(state: ImportState): ImportSummary {
  const steps = state.steps.filter((s): s is ImportStep => s !== null)
  const missing = steps.filter((s) => s.status === 'missing').map((s) => s.index).sort((a, b) => a - b)
  return {
    checked: steps.length,
    matched: steps.length - missing.length,
    total: state.tracks.length,
    missing,
    done: state.head !== null && steps.length === state.tracks.length,
  }
}

/** Треки нового плейлиста: по порядку источника, без повторов (две строки могли найти один трек). */
export function importTracks(state: ImportState): Track[] {
  const seen = new Set<string>()
  return state.steps.flatMap((s) => {
    const t = s?.track
    if (!t || seen.has(t.ref)) return []
    seen.add(t.ref)
    return [t]
  })
}

/** Источник отдал не все треки (страница Apple Music): сколько не прочиталось. */
export function unreadCount(state: ImportState): number {
  return state.head ? Math.max(0, state.head.total - state.tracks.length) : 0
}

/** Запрос «Искать вручную»: «исполнитель название», как у пропавшего локального файла. */
export function manualQuery(track: Pick<Track, 'title' | 'artist'>): string {
  return servicesQuery(track)
}

/** Доля проверенного для полоски прогресса, 0…1. */
export function progressShare(s: ImportSummary): number {
  return s.total ? s.checked / s.total : s.done ? 1 : 0
}

let seq = 0
/** id задачи импорта: по нему фильтруются события и работает отмена. */
export function newJobId(now = Date.now()): string {
  seq += 1
  return `imp-${now.toString(36)}-${seq}`
}
