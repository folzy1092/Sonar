// Выбор треков в плейлисте / Любимых (режим «Выбрать»): чистые функции — ключ строки, отметки,
// диапазон по Shift и текст для «Поделиться». Состояние живёт на странице (pages/PlaylistPage.svelte).
import type { Track } from './api'

/** Строка списка: у своего плейлиста — `item_id` (один трек может стоять дважды), иначе — `ref`. */
export const selKey = (t: Pick<Track, 'ref'> & { item_id?: string }): string => t.item_id ?? t.ref

/** Отметка вкл/выкл — новый набор (реактивность Svelte следит за ссылкой). */
export function toggleKey(sel: ReadonlySet<string>, key: string): Set<string> {
  const next = new Set(sel)
  if (!next.delete(key)) next.add(key)
  return next
}

/** Shift+клик: все ключи между двумя строками включительно, в любом порядке концов. */
export function rangeKeys(keys: readonly string[], a: number, b: number): string[] {
  const from = Math.max(0, Math.min(a, b))
  const to = Math.min(keys.length - 1, Math.max(a, b))
  return keys.slice(from, to + 1)
}

/** Отмеченное в порядке списка на экране; отметки, которых в списке уже нет, отбрасываются. */
export function pickSelected<T extends Pick<Track, 'ref'> & { item_id?: string }>(list: readonly T[], sel: ReadonlySet<string>): T[] {
  return sel.size ? list.filter((x) => sel.has(selKey(x))) : []
}

/** Текст для «Поделиться» своим списком, у которого пока нет публичной ссылки: название и строки «Артист — Название». */
export function shareText(title: string, tracks: readonly Pick<Track, 'artist' | 'title'>[]): string {
  const lines = tracks.map((x) => (x.artist.trim() ? `${x.artist.trim()} — ${x.title}` : x.title))
  return [title, '', ...lines].join('\n')
}
