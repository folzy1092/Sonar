// Сдвиг текста на трек (LYRICS.md §5): секунды −15..+15, 3 знака; в базе — мс, 0 → нет записи.
import { t } from '../../lib/i18n.svelte'

export const OFFSET_MAX = 15

export function clampOffset(sec: number): number {
  const v = Math.min(OFFSET_MAX, Math.max(-OFFSET_MAX, sec))
  return Math.round(v * 1000) / 1000 || 0
}

export const toMs = (sec: number) => Math.round(clampOffset(sec) * 1000)
export const fromMs = (ms: number | null | undefined) => clampOffset((ms ?? 0) / 1000)

/** «+0.250 с», «−1.000 с», «0.000 с». */
export function formatOffset(sec: number): string {
  const v = clampOffset(sec)
  const sign = v > 0 ? '+' : v < 0 ? '−' : ''
  return `${sign}${t('{sec} с', { sec: Math.abs(v).toFixed(3) })}`
}
