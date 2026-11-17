// Таймер сна — чистая часть (тесты в sleep.test.ts): сколько осталось и насколько приглушить звук.

/** Сколько длится затухание перед паузой: по времени — 30 с, «до конца трека» — 8 с. */
export const FADE_MS = 30_000
export const FADE_TRACK_MS = 8_000

/** Готовые длительности, минуты. */
export const SLEEP_PRESETS = [15, 30, 45, 60, 90] as const

/** Множитель громкости за `leftMs` до паузы: 1 — пока затухание не началось, к нулю — плавно
 *  (квадрат: на слух затухает ровно, а не обрывается в конце). */
export function fadeK(leftMs: number, fadeMs: number): number {
  if (leftMs >= fadeMs) return 1
  if (leftMs <= 0) return 0
  const k = leftMs / fadeMs
  return k * k
}

/** Подпись оставшегося времени на кнопке: «12» (минуты) или «0:45» на последней минуте. */
export function leftLabel(leftMs: number): string {
  const s = Math.max(0, Math.ceil(leftMs / 1000))
  if (s >= 60) return String(Math.ceil(s / 60))
  return `0:${String(s).padStart(2, '0')}`
}
