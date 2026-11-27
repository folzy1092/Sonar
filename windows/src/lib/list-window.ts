// Окно длинного списка: сразу рисуется LIST_WINDOW строк, дальше — по LIST_STEP, когда прокрутка дошла до
// сторожа (`use:nearEnd`). Тысячи строк разом — тысячи узлов и анимаций: прокрутка и скрытие элементов
// лагали (очередь, «Любимые», большие плейлисты; владелец 2026-11-22).

/** Сколько строк рисовать сразу. */
export const LIST_WINDOW = 60
/** На сколько окно растёт, когда прокрутка дошла до конца. */
export const LIST_STEP = 60

/** Новый размер окна: плюс шаг, но не больше длины списка (и не меньше прежнего). */
export function growLimit(limit: number, total: number): number {
  return Math.max(limit, Math.min(limit + LIST_STEP, total))
}

/**
 * Окно строк по прокрутке (память WebView2, 2026-11-27): растущее окно (`growLimit`) только добавляло строки —
 * долистал «Любимые» до конца, и в DOM навсегда 1500 строк × ~90 узлов с картинками (+300 МБ). Теперь рисуются
 * строки у экрана плюс запас, остальное — отступы сверху и снизу. Границы кратны `chunk`, чтобы список
 * перерисовывался раз в несколько строк прокрутки, а не на каждый пиксель.
 */
export function rowWindow(scrollTop: number, viewH: number, rowH: number, total: number, overscan = 20, chunk = 10): { start: number; end: number } {
  if (!(rowH > 0)) return { start: 0, end: Math.min(total, LIST_WINDOW) }
  const first = Math.floor(Math.max(0, scrollTop) / rowH) - overscan
  const last = Math.ceil((Math.max(0, scrollTop) + Math.max(0, viewH)) / rowH) + overscan
  const start = Math.min(Math.max(0, Math.floor(first / chunk) * chunk), Math.max(0, total - 1))
  const end = Math.min(total, Math.max(start, Math.ceil(last / chunk) * chunk))
  return { start: Math.max(0, Math.min(start, end)), end }
}
