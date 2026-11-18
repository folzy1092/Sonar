// Локальные файлы (Система → Хранилище → «Папки с музыкой», local/ в Rust): чистые помощники для
// строк треков — без Tauri, чтобы проверялись тестами.
import { isLocalRef } from './services'

interface TrackLike {
  ref: string
  title: string
  artist: string
  available: boolean
}

/** Файл с этого компьютера пропал с диска (флешка вынута, удалён) — строка серая «Файл не найден». */
export function isMissingLocal(track: TrackLike): boolean {
  return !track.available && isLocalRef(track.ref)
}

/** Запрос для «Найти в сервисах»: «исполнитель название» без лишних пробелов. */
export function servicesQuery(track: Pick<TrackLike, 'title' | 'artist'>): string {
  return `${track.artist} ${track.title}`.replace(/\s+/g, ' ').trim()
}

/** Исполнитель в строке: у файла без тегов он пустой — тогда пусто, а подпись даёт вызывающий. */
export function hasArtist(track: Pick<TrackLike, 'artist'>): boolean {
  return track.artist.trim().length > 0
}

/** Путь папки для сравнения: без хвостового разделителя, на Windows — без учёта регистра. */
function folderKey(dir: string): string {
  const trimmed = dir.trim().replace(/[\\/]+$/, '')
  return /^[a-z]:/i.test(trimmed) || trimmed.includes('\\') ? trimmed.toLowerCase() : trimmed
}

/** «+» в «Папках с музыкой»: новый список с папкой; пустой путь или папка уже есть — null. */
export function addFolder(folders: readonly string[], dir: string): string[] | null {
  const clean = dir.trim()
  if (!clean || folders.some((f) => folderKey(f) === folderKey(clean))) return null
  return [...folders, clean]
}

/** «−»: новый список без папки. */
export function removeFolder(folders: readonly string[], dir: string): string[] {
  return folders.filter((f) => f !== dir)
}
