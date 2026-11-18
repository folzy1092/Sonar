// Экран «Дубли» (этап 7 NEXT_PROMPT): что отмечено к удалению и почему трек считается дублем.
// Сами группы и кого оставить по умолчанию решает Rust (dupes/mod.rs: правила providers/matching.rs,
// лучший звук — registry::QUALITY_ORDER). Здесь — чистая логика отметок без Svelte и сети.
import type { DupeGroup, DupeListId, ListTrack } from './api'
import { serviceOf } from './services'

/** Почему трек — дубль того, кого оставляем: тот же трек ещё раз, тот же из другого сервиса,
 *  почти одинаковое название того же исполнителя. */
export type DupeReason = 'same' | 'service' | 'similar'

/** Отмеченные к удалению `item_id`. Набор не меняется — каждая правка возвращает новый. */
export type Marks = ReadonlySet<string>

/** Параметр страницы → список, где ищутся дубли; чужое — `null`. */
export function dupeListOf(param: string | null | undefined): DupeListId | null {
  if (param === 'favorites') return 'favorites'
  return param && param.startsWith('pl_') && param.length > 3 ? (param as DupeListId) : null
}

export function reasonOf(item: ListTrack, keeper: ListTrack): DupeReason {
  if (item.ref === keeper.ref) return 'same'
  return serviceOf(item.ref) !== serviceOf(keeper.ref) ? 'service' : 'similar'
}

/** По умолчанию отмечены все, кроме того, кого Rust советует оставить. */
export function initialMarks(groups: readonly DupeGroup[]): Marks {
  return new Set(groups.flatMap((g) => g.items.filter((i) => i.item_id !== g.keep).map((i) => i.item_id)))
}

/** Сколько треков группы остаётся. */
export function keptIn(group: DupeGroup, marks: Marks): number {
  return group.items.filter((i) => !marks.has(i.item_id)).length
}

/** Переключить отметку. Последний оставленный трек группы отметить нельзя — набор не меняется. */
export function toggleMark(marks: Marks, group: DupeGroup, itemId: string): Marks {
  if (!group.items.some((i) => i.item_id === itemId)) return marks
  const next = new Set(marks)
  if (next.has(itemId)) {
    next.delete(itemId)
    return next
  }
  if (keptIn(group, marks) <= 1) return marks
  next.add(itemId)
  return next
}

/** Оставить в группе только этот трек, остальные — к удалению. */
export function keepOnly(marks: Marks, group: DupeGroup, itemId: string): Marks {
  if (!group.items.some((i) => i.item_id === itemId)) return marks
  const next = new Set(marks)
  for (const i of group.items) {
    if (i.item_id === itemId) next.delete(i.item_id)
    else next.add(i.item_id)
  }
  return next
}

/** Что убрать: отмеченные `item_id` по порядку групп, без повторов и без того, чего в группах нет.
 *  Один и тот же `item_id` в Любимых — это ref, поэтому повторы схлопываются. */
export function removalIds(groups: readonly DupeGroup[], marks: Marks): string[] {
  const ids = groups.flatMap((g) => g.items.map((i) => i.item_id)).filter((id) => marks.has(id))
  return [...new Set(ids)]
}

/** Сколько треков лишние во всех группах (для подписи «Найдено…»). */
export function extraCount(groups: readonly DupeGroup[]): number {
  return groups.reduce((n, g) => n + g.items.length - 1, 0)
}
