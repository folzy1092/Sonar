// Пульт (remote/ в Rust, docs/API.md «Пульт»): чистая часть — что уходит телефону в `state` и какие
// команды от него принимаются. Без Svelte и Tauri, проверяется тестами (remote-core.test.ts).
import type { Repeat, Track } from './api'

/** Столько треков «Далее» видно на телефоне (как QUEUE_LIMIT в remote/protocol.rs). */
export const QUEUE_LIMIT = 50
/** Даже без изменений состояние уходит так часто — телефон сверяет позицию. */
export const STATE_REFRESH_MS = 5000
/** Позиция ушла дальше этого от ожидаемой — перемотали, шлём сразу. */
export const SEEK_JUMP_MS = 1500

/** Трек для телефона — те же поля, что у Track в API, без служебных (`why`, `plays`). */
export type RemoteTrack = Pick<Track, 'ref' | 'title' | 'artist' | 'artists' | 'album' | 'duration_ms' | 'cover_url' | 'url' | 'explicit' | 'available'>

export interface RemoteState {
  track: RemoteTrack | null
  position_ms: number
  /** Когда снята позиция (мс с 1970) — телефон двигает полосу сам, пока играет. */
  position_at: number
  duration_ms: number
  playing: boolean
  volume: number
  repeat: Repeat
  shuffle: boolean
  liked: boolean
  queue: RemoteTrack[]
  context_title: string | null
}

export interface PlayerSnapshot {
  current: Track | null
  positionMs: number
  durationMs: number
  playing: boolean
  volume: number
  repeat: Repeat
  shuffle: boolean
  liked: boolean
  upNext: readonly Track[]
  contextTitle: string | null
}

export function slimTrack(t: Track): RemoteTrack {
  return {
    ref: t.ref,
    title: t.title,
    artist: t.artist,
    artists: t.artists,
    album: t.album,
    duration_ms: t.duration_ms,
    cover_url: t.cover_url,
    url: t.url,
    explicit: t.explicit,
    available: t.available,
  }
}

const clamp01 = (v: number) => (Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 0)
const ms = (v: number) => (Number.isFinite(v) && v > 0 ? Math.round(v) : 0)

export function buildState(p: PlayerSnapshot, now: number): RemoteState {
  return {
    track: p.current ? slimTrack(p.current) : null,
    position_ms: ms(p.positionMs),
    position_at: now,
    duration_ms: ms(p.durationMs || p.current?.duration_ms || 0),
    playing: p.playing && !!p.current,
    volume: Math.round(clamp01(p.volume) * 100) / 100,
    repeat: p.repeat,
    shuffle: p.shuffle,
    liked: p.liked,
    queue: p.upNext.slice(0, QUEUE_LIMIT).map(slimTrack),
    context_title: p.contextTitle,
  }
}

/** Всё, кроме позиции: поменялось — шлём сразу. */
export function stateKey(s: RemoteState): string {
  return JSON.stringify({ ...s, position_ms: 0, position_at: 0 })
}

/** Где должна быть позиция сейчас, если с прошлой отправки трек просто играл. */
export function expectedPosition(sent: RemoteState, now: number): number {
  if (!sent.playing) return sent.position_ms
  return Math.min(sent.duration_ms || Infinity, sent.position_ms + Math.max(0, now - sent.position_at))
}

/** Пора ли слать состояние: изменилось, перемотали или давно не слали. */
export function shouldSend(next: RemoteState, sent: RemoteState | null, now: number): boolean {
  if (!sent) return true
  if (stateKey(next) !== stateKey(sent)) return true
  if (now - sent.position_at >= STATE_REFRESH_MS) return true
  return Math.abs(next.position_ms - expectedPosition(sent, now)) > SEEK_JUMP_MS
}

export type RemoteCommand =
  | { type: 'toggle' | 'next' | 'prev' }
  | { type: 'seek'; ms: number }
  | { type: 'volume'; value: number }
  | { type: 'like'; ref?: string; value?: boolean }
  | { type: 'play'; wave: true }
  | { type: 'play'; wave: false; ref: string; track?: Track }
  | { type: 'queue_add'; ref: string; track?: Track; next: boolean }
  | { type: 'queue_play_index'; index: number }

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const isRef = (v: unknown): v is string => typeof v === 'string' && v.length > 0 && v.length <= 256
const trackOf = (v: unknown, ref: string): Track | undefined => (isObj(v) && v.ref === ref && typeof v.title === 'string' ? (v as unknown as Track) : undefined)

/** Команда из события `remote-command` (Rust уже проверил; здесь — вторая линия и типы для TS). */
export function parseCommand(raw: unknown): RemoteCommand | null {
  if (!isObj(raw)) return null
  switch (raw.type) {
    case 'toggle':
    case 'next':
    case 'prev':
      return { type: raw.type }
    case 'seek':
      return typeof raw.ms === 'number' && raw.ms >= 0 ? { type: 'seek', ms: raw.ms } : null
    case 'volume':
      return typeof raw.value === 'number' ? { type: 'volume', value: clamp01(raw.value) } : null
    case 'like':
      return {
        type: 'like',
        ...(isRef(raw.ref) ? { ref: raw.ref } : {}),
        ...(typeof raw.value === 'boolean' ? { value: raw.value } : {}),
      }
    case 'play':
      if (raw.wave === true) return { type: 'play', wave: true }
      return isRef(raw.ref) ? { type: 'play', wave: false, ref: raw.ref, track: trackOf(raw.track, raw.ref) } : null
    case 'queue_add':
      return isRef(raw.ref) ? { type: 'queue_add', ref: raw.ref, track: trackOf(raw.track, raw.ref), next: raw.next === true } : null
    case 'queue_play_index':
      return Number.isInteger(raw.index) && (raw.index as number) >= 0 && (raw.index as number) < QUEUE_LIMIT ? { type: 'queue_play_index', index: raw.index as number } : null
    default:
      return null
  }
}

/**
 * Номер в «Далее» сейчас для `queue_play_index`: телефон видел очередь из последнего `state`, а она
 * могла сдвинуться (трек доиграл). Ищем тот же ref; не нашли — `null`.
 */
export function queueIndexNow(sentQueue: readonly string[], index: number, upNext: readonly string[]): number | null {
  const ref = sentQueue[index]
  if (!ref) return null
  if (upNext[index] === ref) return index
  const i = upNext.indexOf(ref)
  return i >= 0 ? i : null
}

/** Нужно ли переключать лайк: `value` нет — переключить, есть — только если отличается. */
export function likeNeedsToggle(liked: boolean, value: boolean | undefined): boolean {
  return value === undefined || value !== liked
}
