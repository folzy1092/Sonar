// Оценка исхода трека волны (docs/WAVE.md 1.3) — одна шкала для всех сигналов. Та же функция в
// Rust (`wave.rs` `reward`), тесты на обе.
//
// | исход                                         | оценка |
// |-----------------------------------------------|--------|
// | 👎                                            | −2     |
// | лайк во время трека или трек уже в Любимых    | +1.5   |
// | пропуск, f < 0.25 или < 30 с — ранний          | −1     |
// | пропуск, 0.25 ≤ f < 0.5                       | −0.4   |
// | пропуск, 0.5 ≤ f < 0.8                        | 0      |
// | f ≥ 0.8 (как угодно закончился)               | +1     |
// | сменился не пропуском, f < 0.8                | 0      |
//
// f = прослушано / длительность. Длительность 0 — по секундам: < 30 с — ранний пропуск,
// ≥ 150 с — дослушан.
import type { Track } from '../lib/api'

export interface Outcome {
  listenedMs: number
  durationMs: number
  /** Пропущен вручную (кнопка, клавиша, переход по очереди), а не закончился сам. */
  manualSkip: boolean
  liked: boolean
  disliked: boolean
}

export function reward(o: Outcome): number {
  if (o.disliked) return -2
  if (o.liked) return 1.5
  const early = o.listenedMs < 30_000
  if (o.durationMs <= 0) {
    if (o.listenedMs >= 150_000) return 1
    return o.manualSkip && early ? -1 : 0
  }
  const f = o.listenedMs / o.durationMs
  if (f >= 0.8) return 1
  if (!o.manualSkip) return 0
  if (f < 0.25 || early) return -1
  if (f < 0.5) return -0.4
  return 0
}

/** Ранний пропуск (−1 без 👎 и лайка) — два подряд у артиста ставят его на паузу. */
export const isEarlySkip = (o: Outcome) => reward(o) === -1

/** Главный артист трека, как `wave.rs` `artist_key`: первый из списка `artists` (нижний регистр,
 *  без крайних пробелов), а если списка нет — строка `artist` целиком (по запятым не режем). */
export function artistKey(t: Pick<Track, 'artist' | 'artists'>): string {
  for (const a of t.artists ?? []) {
    const k = a.name.trim().toLowerCase()
    if (k) return k
  }
  return t.artist.trim().toLowerCase()
}
