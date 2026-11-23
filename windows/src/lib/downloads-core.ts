// Скачивание (`docs/OFFLINE.md` §8): чистые помощники без Tauri — оценка размера пачки, нужно ли
// подтверждение, подпись прогресса. Проверяются тестами (`downloads-core.test.ts`).
import { t } from './i18n.svelte'

export type Quality = 'low' | 'medium' | 'high' | 'max'

/** Пачка больше — спросить перед скачиванием (§8.2). */
export const CONFIRM_TRACKS = 50
export const CONFIRM_BYTES = 1024 ** 3

/** Битрейт Яндекса по настройке `audio.quality` — как `quality_kbps` в `services.rs`; max — FLAC, в среднем ~1000 кбит/с. */
const YM_KBPS: Record<Quality, number> = { low: 192, medium: 256, high: 320, max: 1000 }
/** Остальные сервисы отдают свой максимум сами — берём среднее по ним. */
const OTHER_KBPS = 160
/** Длительность неизвестна — считаем средней песней. */
const FALLBACK_MS = 210_000

interface Sized {
  ref: string
  duration_ms: number
}

/** Примерный размер трека в байтах: длительность × битрейт. */
export function trackBytes(t: Sized, quality: Quality): number {
  const kbps = t.ref.startsWith('ym:') ? YM_KBPS[quality] : OTHER_KBPS
  const ms = t.duration_ms > 0 ? t.duration_ms : FALLBACK_MS
  return Math.round((ms / 1000) * kbps * 125)
}

export function batchBytes(tracks: readonly Sized[], quality: Quality): number {
  return tracks.reduce((sum, t) => sum + trackBytes(t, quality), 0)
}

export function needsConfirm(count: number, bytes: number): boolean {
  return count > CONFIRM_TRACKS || bytes > CONFIRM_BYTES
}

/** Что из пачки ещё качать: без локальных файлов, уже скачанного и повторов. */
export function toDownload<T extends { ref: string }>(tracks: readonly T[], downloaded: ReadonlySet<string>): T[] {
  const seen = new Set<string>()
  return tracks.filter((t) => {
    if (t.ref.startsWith('local:') || downloaded.has(t.ref) || seen.has(t.ref)) return false
    seen.add(t.ref)
    return true
  })
}

/** Автоскачивание Любимых: что из списка (по порядку, новые лайки первыми) влезает в лимит поверх уже скачанного.
 * Первый не влезший останавливает подбор — иначе мелкие старые треки обгоняли бы свежие лайки. */
export function fitToLimit<T extends Sized>(tracks: readonly T[], usedBytes: number, limitBytes: number, quality: Quality): T[] {
  let total = usedBytes
  const over = tracks.findIndex((t) => (total += trackBytes(t, quality)) > limitBytes)
  return tracks.slice(0, over < 0 ? tracks.length : over)
}

/** Автоскачивание Любимых целиком (как iPhone `LikedAutoDownload.plan`): недостающие лайки по порядку, пока скачанное
 * + уже стоящее в очереди + новое не больше лимита. `only` — подобрать один свежий лайк. */
export function likedPlan<T extends Sized>(
  liked: readonly T[],
  downloaded: ReadonlySet<string>,
  queued: ReadonlySet<string>,
  usedBytes: number,
  limitBytes: number,
  quality: Quality,
  only?: string,
): T[] {
  const inQueue = liked.filter((t) => queued.has(t.ref))
  const missing = toDownload(liked, downloaded).filter((t) => !queued.has(t.ref) && (!only || t.ref === only))
  return fitToLimit(missing, usedBytes + batchBytes(inQueue, quality), limitBytes, quality)
}

/** Доля готового в пачке, 0…1. Пусто — 0. */
export function progress(done: number, left: number): number {
  const all = done + left
  return all ? done / all : 0
}

const MB = 1024 ** 2
const GB = 1024 ** 3

/** «340 МБ» или «1.2 ГБ» — для подтверждения пачки и карточки «Скачанное». */
export function bytesText(b: number): string {
  return b >= GB ? t('{n} ГБ', { n: (b / GB).toFixed(1) }) : t('{n} МБ', { n: Math.max(1, Math.round(b / MB)) })
}
