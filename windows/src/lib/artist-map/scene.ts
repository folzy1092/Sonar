// Кадр карты между двумя раскладками: граф обновился (подтянулись подписки) — круги плавно
// переезжают на новые места, новые проявляются. Чистые функции.
import type { MapNode } from './api'
import type { Disc, Layout } from './layout'
import type { DrawNode } from './render'

export type Positions = ReadonlyMap<string, Disc>

/** Переезд и проявление; при «меньше движения» — только проявление. */
export const MORPH_MS = 620
export const FADE_MS = 320

/** Круги кадра: `move` — доля переезда 0..1 (уже сглаженная), `fade` — доля проявления новых. */
export function frameNodes(
  layout: Layout,
  nodes: ReadonlyMap<string, MapNode>,
  prev: Positions,
  move: number,
  fade: number,
): DrawNode[] {
  return layout.nodes.flatMap((p) => {
    const n = nodes.get(p.key)
    if (!n) return []
    const from = prev.get(p.key)
    const k = from ? move : 1
    return [
      {
        key: p.key,
        name: n.name,
        x: from ? from.x + (p.x - from.x) * k : p.x,
        y: from ? from.y + (p.y - from.y) * k : p.y,
        r: from ? from.r + (p.r - from.r) * k : p.r,
        discovered: n.discovered,
        cluster: p.cluster,
        avatar: n.avatar_url,
        shown: from ? 1 : fade,
      },
    ]
  })
}

/** Где круги стоят сейчас — отправная точка следующего переезда. */
export function positionsOf(list: readonly DrawNode[]): Map<string, Disc> {
  return new Map(list.map((n) => [n.key, { x: n.x, y: n.y, r: n.r }]))
}

/** Доля 0..1 прошедшего времени анимации; длительность 0 — сразу конец. */
export function progress(started: number, now: number, ms: number): number {
  if (ms <= 0) return 1
  return Math.min(1, Math.max(0, (now - started) / ms))
}
