// Прогресс слова или строки 0..1 (LYRICS.md §4).

/** Нулевая длительность считается как 50 мс — иначе деление на ноль. */
export const MIN_DURATION = 0.05
/** Слово длиннее — лёгкая пульсация. */
export const LONG_WORD = 1.2

export function progress(start: number, duration: number, t: number): number {
  const d = Math.max(duration, MIN_DURATION)
  if (t >= start + d) return 1
  if (t < start) return 0
  return Math.min(1, Math.max(0, (t - start) / d))
}

/** Пульсация длинного слова: k = sin(π·p)², масштаб 1 + 0.04k. */
export function pulse(p: number): number {
  const s = Math.sin(Math.PI * p)
  return s * s
}
