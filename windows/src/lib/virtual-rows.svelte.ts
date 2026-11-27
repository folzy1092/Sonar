// Виртуальный список строк одной высоты (lib/list-window.ts `rowWindow`): прокрутка и высота окна —
// из прокручиваемого предка (`use:rows.track`), высота строки — по первой нарисованной строке.

import { rowWindow } from './list-window'
import { scrollParent } from './near-end'

export class VirtualRows {
  private top = $state(0)
  private view = $state(900)
  /** Высота строки, px; уточняется по первой строке списка. */
  rowH = $state(0)

  constructor(
    private readonly guess: number,
    private readonly overscan = 20,
  ) {
    this.rowH = guess
  }

  /** Окно `[start, end)` для списка длины `total`. */
  range(total: number): { start: number; end: number } {
    return rowWindow(this.top, this.view, this.rowH, total, this.overscan)
  }

  /** Действие на сам список: следит за прокруткой предка и меряет строку. */
  track = (list: HTMLElement) => {
    const root = scrollParent(list)
    let raf = 0
    const read = () => {
      raf = 0
      const r = root ?? document.documentElement
      // отступ списка внутри прокрутки (шапка над ним) — вычитаем, чтобы окно стояло там, где строки
      const offset = root ? list.getBoundingClientRect().top - root.getBoundingClientRect().top + root.scrollTop : list.offsetTop
      this.top = r.scrollTop - offset
      this.view = root ? root.clientHeight : innerHeight
      const row = list.querySelector<HTMLElement>(':scope > [data-row]')
      const h = row?.offsetHeight ?? 0
      if (h > 0 && Math.abs(h - this.rowH) > 0.5) this.rowH = h
    }
    const kick = () => {
      if (!raf) raf = requestAnimationFrame(read)
    }
    const target: EventTarget = root ?? window
    target.addEventListener('scroll', kick, { passive: true })
    const ro = new ResizeObserver(kick)
    if (root) ro.observe(root)
    ro.observe(list)
    kick()
    return {
      destroy() {
        cancelAnimationFrame(raf)
        target.removeEventListener('scroll', kick)
        ro.disconnect()
      },
    }
  }
}
