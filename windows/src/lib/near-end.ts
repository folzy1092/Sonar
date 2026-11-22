// Сторож конца длинного списка (очередь в плеере и в правой панели): строка в самом низу; прокрутка
// подошла к ней ближе чем на `margin` — зовёт `onreach`. Следит в ближайшем прокручиваемом предке, а не в
// окне, чтобы запас работал и внутри панели со своей прокруткой. `key` меняется (окно выросло) —
// сторож перепроверяется: если он всё ещё на виду, `onreach` позовётся снова.

export interface NearEndOptions {
  onreach: () => void
  /** Меняется, когда список вырос, — повод проверить снова. */
  key?: unknown
  /** Запас до конца, px. */
  margin?: number
}

const DEFAULT_MARGIN = 800

/** Ближайший предок с прокруткой по вертикали; нет — окно (`null` для IntersectionObserver). */
export function scrollParent(node: Element): Element | null {
  for (let el = node.parentElement; el; el = el.parentElement) {
    const oy = getComputedStyle(el).overflowY
    if (oy === 'auto' || oy === 'scroll') return el
  }
  return null
}

export function nearEnd(node: HTMLElement, options: NearEndOptions) {
  let opts = options
  let io: IntersectionObserver | null = null
  const watch = () => {
    io?.disconnect()
    const margin = opts.margin ?? DEFAULT_MARGIN
    io = new IntersectionObserver((entries) => entries.some((e) => e.isIntersecting) && opts.onreach(), {
      root: scrollParent(node),
      rootMargin: `0px 0px ${margin}px 0px`,
    })
    io.observe(node)
  }
  watch()
  return {
    update(next: NearEndOptions) {
      const changed = next.key !== opts.key
      opts = next
      if (changed) watch()
    },
    destroy() {
      io?.disconnect()
    },
  }
}
