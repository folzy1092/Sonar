// Что показывает очередь на странице плеера (pages/Player.svelte): «Ранее» (последние сыгранные),
// «Сейчас играет», «Далее» (своя очередь) и похожие автоплея. Без побочных эффектов — проверяется
// тестами (queue-view.test.ts). У каждой строки — стабильный id элемента очереди (`Player.entryIds`),
// а не `ref + индекс`: при «вперёд / назад» строка сохраняет ключ и переезжает (animate:flip), а не
// появляется заново.
import type { Track } from '../lib/api'

/** Сколько сыгранных показывать в «Ранее». */
export const EARLIER_SIZE = 5

export interface QueueEntry {
  /** Стабильный id элемента очереди (живёт, пока трек в очереди). */
  id: number
  track: Track
  /** Позиция в порядке воспроизведения (`player.order`). */
  pos: number
}

export interface QueueView {
  earlier: QueueEntry[]
  current: QueueEntry | null
  /** Своя очередь после текущего. */
  own: QueueEntry[]
  /** Похожие автоплея (идут после своей очереди). */
  auto: QueueEntry[]
}

export interface QueueSource {
  tracks: Track[]
  order: number[]
  pos: number
  /** id элементов очереди, параллельно `tracks`; длина не совпала — id по индексу трека. */
  ids: number[]
  autoRefs: Set<string>
  earlierSize?: number
}

/** Разложить очередь по разделам. Похожие автоплея начинаются с первого такого трека после текущего. */
export function queueView({ tracks, order, pos, ids, autoRefs, earlierSize = EARLIER_SIZE }: QueueSource): QueueView {
  const idOf = (i: number) => (ids.length === tracks.length ? ids[i] : i)
  const entry = (p: number): QueueEntry | null => {
    const i = order[p]
    const track = i === undefined ? undefined : tracks[i]
    return track ? { id: idOf(i), track, pos: p } : null
  }
  const range = (from: number, to: number) => {
    const out: QueueEntry[] = []
    for (let p = Math.max(0, from); p < Math.min(to, order.length); p++) {
      const e = entry(p)
      if (e) out.push(e)
    }
    return out
  }
  const next = range(pos + 1, order.length)
  const autoAt = next.findIndex((e) => autoRefs.has(e.track.ref))
  return {
    earlier: earlierSize > 0 ? range(pos - earlierSize, pos) : [],
    current: entry(pos),
    own: autoAt < 0 ? next : next.slice(0, autoAt),
    auto: autoAt < 0 ? [] : next.slice(autoAt),
  }
}

/** Строка списка очереди: заголовок раздела, трек, тумблер «Авто похожие» или «пусто». Все — в одном
 *  `{#each}`, чтобы трек переезжал из раздела в раздел (FLIP), а заголовки сдвигались вместе с ним. */
export type QueueItem =
  | { kind: 'head'; key: string; section: 'earlier' | 'now' | 'next' }
  | { kind: 'track'; key: string; section: 'earlier' | 'now' | 'next' | 'auto'; entry: QueueEntry }
  | { kind: 'switch'; key: string }
  | { kind: 'empty'; key: string }

export interface ItemsOptions {
  /** Показывать тумблер «Авто похожие» и похожие (не в «Моей волне»). */
  autoSection: boolean
  /** Автоплей включён (пустая очередь без похожих — без надписи «пусто»). */
  autoOn: boolean
}

const trackItems = (list: QueueEntry[], section: 'earlier' | 'now' | 'next' | 'auto'): QueueItem[] =>
  list.map((entry) => ({ kind: 'track', key: `e${entry.id}`, section, entry }))

/** Плоский список строк очереди по разделам. Ключи стабильны: `e<id>` у треков, имена у остальных. */
export function queueItems(view: QueueView, { autoSection, autoOn }: ItemsOptions): QueueItem[] {
  const out: QueueItem[] = []
  if (view.earlier.length) {
    out.push({ kind: 'head', key: 'h-earlier', section: 'earlier' })
    out.push(...trackItems(view.earlier, 'earlier'))
  }
  if (view.current) {
    out.push({ kind: 'head', key: 'h-now', section: 'now' })
    out.push(...trackItems([view.current], 'now'))
  }
  out.push({ kind: 'head', key: 'h-next', section: 'next' })
  out.push(...trackItems(view.own, 'next'))
  if (!view.own.length && !view.auto.length && !autoOn) out.push({ kind: 'empty', key: 'empty' })
  if (autoSection) {
    out.push({ kind: 'switch', key: 'auto-switch' })
    out.push(...trackItems(view.auto, 'auto'))
  }
  return out
}
