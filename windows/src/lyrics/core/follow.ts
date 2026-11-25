// Что делает кадр синхронного текста: считать ли строку и подсветку слов, крутить ли к ней прокрутку.
// Открытая аннотация Genius держит только прокрутку — текст не уезжает из-под курсора, — а строка и
// слова идут дальше. Раньше кадр замирал целиком, и караоке вставало, пока курсор на аннотации (баг 2026-11-20).

export interface FrameState {
  synced: boolean
  lineCount: number
  /** Окно свёрнуто или вкладка скрыта. */
  hidden: boolean
}

/** Считать ли в этом кадре текущую строку и подсветку слов. Аннотация сюда не входит намеренно. */
export function shouldPaint(s: FrameState): boolean {
  return s.synced && s.lineCount > 0 && !s.hidden
}

export interface ScrollState {
  synced: boolean
  /** Сколько мс прошло с прокрутки колесом. */
  sinceUserScroll: number
  /** Строка с развёрнутой аннотацией или null. */
  noteOpen: number | null
}

/** Пауза автопрокрутки после колеса пользователя. */
export const USER_SCROLL_PAUSE = 2500

/** Подтягивать ли прокрутку к текущей строке. */
export function shouldAutoScroll(s: ScrollState): boolean {
  return s.synced && s.sinceUserScroll >= USER_SCROLL_PAUSE && s.noteOpen === null
}

/** Дальше стольких строк от прошлой текущей — не «следующая строка», а переход: открыли плеер на середине
 *  трека, пришёл текст, перемотали. Плавно такой путь не едем — иначе текст долго ползёт с самого верха. */
export const SMOOTH_LINES = 3

/** Ехать ли к новой текущей строке плавно. `prev` — прошлая текущая (-1 — до первой строки или текст только
 *  что открылся), `next` — новая. Строка за строкой в песне — плавно, остальное — сразу на место. */
export function scrollsSmoothly(prev: number, next: number): boolean {
  return Math.abs(next - prev) <= SMOOTH_LINES
}
