// Очередь без побочных эффектов: порядок (обычный или перемешанный) и переходы.
// Отдельно от движка, чтобы проверять тестами (queue.test.ts).
import type { Repeat } from '../lib/api'

/** Порядок индексов треков. При перемешивании текущий трек остаётся первым. */
export function makeOrder(length: number, current: number, shuffle: boolean, rand = Math.random): number[] {
  const order = Array.from({ length }, (_, i) => i)
  if (!shuffle || length < 2) return order
  const rest = order.filter((i) => i !== current)
  for (let i = rest.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1))
    ;[rest[i], rest[j]] = [rest[j], rest[i]]
  }
  return [current, ...rest]
}

/**
 * Следующая позиция в порядке. `manual` — нажали «вперёд» (повтор трека не держит).
 * null — очередь кончилась.
 */
export function nextPos(pos: number, length: number, repeat: Repeat, manual: boolean): number | null {
  if (length === 0) return null
  if (repeat === 'one' && !manual) return pos
  if (pos + 1 < length) return pos + 1
  return repeat === 'off' ? null : 0
}

export function prevPos(pos: number, length: number, repeat: Repeat): number {
  if (pos > 0) return pos - 1
  return repeat === 'all' && length > 0 ? length - 1 : 0
}

/** Засчитать прослушивание: дослушал хотя бы до min(30 с, половины трека) — SPEC §3.8. */
export const countsAsPlay = (listenedMs: number, durationMs: number) =>
  listenedMs >= Math.min(30_000, durationMs > 0 ? durationMs / 2 : 30_000)

export const nextRepeat = (r: Repeat): Repeat => (r === 'off' ? 'all' : r === 'all' ? 'one' : 'off')

/**
 * Вставить трек в очередь: `next` — сразу после текущего, иначе в конец.
 * Трек дописывается в конец списка треков; меняется только порядок.
 */
export function enqueue(order: number[], pos: number, newIndex: number, next: boolean): number[] {
  if (!order.length) return [newIndex]
  const out = order.slice()
  out.splice(next ? pos + 1 : out.length, 0, newIndex)
  return out
}
