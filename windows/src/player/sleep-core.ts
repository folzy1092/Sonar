// Таймер сна — чистая часть (тесты в sleep.test.ts): сколько осталось и насколько приглушить звук.

/** Сколько длится затухание перед паузой: по времени — 30 с, «до конца трека» — 8 с. */
export const FADE_MS = 30_000
export const FADE_TRACK_MS = 8_000

/** Готовые длительности, минуты. */
export const SLEEP_PRESETS = [15, 30, 45, 60, 90] as const

/** Ползунок минут: шаг 1, 5…180; без выбора — 30. Зеркало — iPhone `SleepPick` (PlayerExtras.swift). */
export const SLEEP_MIN = 5
export const SLEEP_MAX = 180
export const SLEEP_DEFAULT = 30

/** Минуты в пределах ползунка, целые. */
export function clampMinutes(n: number): number {
  if (!Number.isFinite(n)) return SLEEP_DEFAULT
  return Math.min(SLEEP_MAX, Math.max(SLEEP_MIN, Math.round(n)))
}

/** Какой пресет подсветить: совпал с минутами ползунка — он, иначе ни один. */
export function presetOf(minutes: number): number | null {
  return (SLEEP_PRESETS as readonly number[]).includes(minutes) ? minutes : null
}

/** Когда встанет на паузу, если запустить сейчас (мс, как Date.now). */
export function stopAt(now: number, minutes: number): number {
  return now + clampMinutes(minutes) * 60_000
}

/** «Изменить» у идущего таймера: ползунок встаёт на остаток, округлённый вверх до минуты. */
export function minutesFromLeft(leftMs: number): number {
  return clampMinutes(Math.ceil(Math.max(0, leftMs) / 60_000))
}

/** «08:44» — время остановки; 12 или 24 часа — как в системе. */
export function clockLabel(at: number, locale?: string): string {
  return new Date(at).toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit' })
}

/** Обратный отсчёт крупно: «42:05», с часом — «1:02:05». */
export function countdownLabel(leftMs: number): string {
  const total = Math.max(0, Math.ceil(leftMs / 1000))
  const h = Math.floor(total / 3600)
  const m = Math.floor(total / 60) % 60
  const s = String(total % 60).padStart(2, '0')
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`
}

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
