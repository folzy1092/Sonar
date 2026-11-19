// Название в полноэкранном плеере (docs/POLISH_PROMPT.md п. 6): до 4 строк, шрифт уменьшается ступенями,
// многоточие — только если не влезло и при самой мелкой ступени. С открытым текстом — 2 строки, как было.
// Узлу ставятся CSS-переменные `--title-lines` и `--title-scale`; обрезку делает `line-clamp` в стилях.

/** Ступени размера шрифта: 22 px → ~19 px → ~16 px. */
export const TITLE_STEPS = [1, 0.86, 0.74] as const
export const FULL_LINES = 4
export const COMPACT_LINES = 2

/** Первая ступень, на которой текст влез; не влез нигде — самая мелкая (дальше — многоточие). */
export function pickStep(fits: (scale: number) => boolean, steps: readonly number[] = TITLE_STEPS): number {
  return steps.find(fits) ?? steps[steps.length - 1]
}

export interface FitTitleOptions {
  /** Сколько строк можно: `FULL_LINES` или `COMPACT_LINES`. */
  lines: number
  /** Сам текст — чтобы пересчитать при смене трека. */
  text: string
}

export function fitTitle(node: HTMLElement, initial: FitTitleOptions) {
  let opts = initial
  let frame = 0

  const apply = (scale: number) => node.style.setProperty('--title-scale', String(scale))
  const overflows = () => node.scrollHeight > node.clientHeight + 1

  function measure() {
    frame = 0
    node.style.setProperty('--title-lines', String(opts.lines))
    if (opts.lines <= COMPACT_LINES) {
      apply(1)
      return
    }
    const scale = pickStep((s) => {
      apply(s)
      return !overflows()
    })
    apply(scale)
  }

  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(measure)
  }

  // ширина колонки меняется с окном и при открытии текста; следим за родителем, не за собой —
  // иначе смена шрифта снова будит наблюдателя
  let lastWidth = -1
  const observer = new ResizeObserver((entries) => {
    const width = entries[0]?.contentRect.width ?? 0
    if (width === lastWidth) return
    lastWidth = width
    schedule()
  })
  if (node.parentElement) observer.observe(node.parentElement)
  document.fonts?.ready.then(schedule).catch(() => {})
  measure()

  return {
    update(next: FitTitleOptions) {
      if (next.lines === opts.lines && next.text === opts.text) return
      opts = next
      schedule()
    },
    destroy() {
      observer.disconnect()
      if (frame) cancelAnimationFrame(frame)
    },
  }
}
