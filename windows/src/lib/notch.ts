// «Чёлка» с кнопками окна, как у Dotify (chrome-notch): из правого верхнего угла карточки маской
// вырезается островок размером с блок кнопок, в вырезе виден фон окна. Внутренний угол выреза
// скруглён, нижний край переходит в правый край карточки выпуклым углом — радиусы как у Dotify.
// Сам островок лежит вне карточки (иначе маска срежет и его), карточка только освобождает место.

/** Путь выреза для угла w×h (Dotify: радиусы не больше 14 px). Экспорт — для тестов. */
export function notchPath(notchW: number, notchH: number, cardRadius: number) {
  const s = Math.min(14, notchW / 2, notchH / 2)
  const r = Math.min(Math.max(cardRadius, s), 14)
  const w = notchW + s
  const h = notchH + r
  const f = (n: number) => n.toFixed(1)
  const arc = (rad: number, sweep: 0 | 1, x: number, y: number) => `A${f(rad)},${f(rad)} 0 0 ${sweep} ${f(x)},${f(y)}`
  const d = [
    'M0,0',
    arc(s, 1, s, s),
    `V${f(notchH - s)}`,
    arc(s, 0, 2 * s, notchH),
    `H${f(w - r)}`,
    arc(r, 1, w, notchH + r),
    `V${f(h)}`,
    'H0',
    'Z',
  ].join(' ')
  return { w, h, d }
}

/** Маска карточки: угол — SVG с вырезом, остальное — две сплошные полосы (слева и снизу). */
function apply(card: HTMLElement, island: HTMLElement) {
  const n = Math.ceil(island.offsetWidth)
  const a = Math.ceil(island.offsetHeight)
  if (!n || !a) return clear(card)
  const radius = parseFloat(getComputedStyle(card).borderTopRightRadius) || 0
  const { w, h, d } = notchPath(n, a, radius)
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='${w}' height='${h}' viewBox='0 0 ${w} ${h}'><path d='${d}' fill='white'/></svg>`
  const image = `url("data:image/svg+xml,${encodeURIComponent(svg)}"), linear-gradient(#000, #000), linear-gradient(#000, #000)`
  const size = `${w}px ${h}px, calc(100% - ${w}px) 100%, 100% calc(100% - ${h}px)`
  const st = card.style
  st.maskImage = st.webkitMaskImage = image
  st.maskSize = st.webkitMaskSize = size
  st.maskPosition = st.webkitMaskPosition = 'right top, left top, left bottom'
  st.maskRepeat = st.webkitMaskRepeat = 'no-repeat'
  st.setProperty('--notch-w', `${n}px`)
  st.setProperty('--notch-h', `${a}px`)
}

function clear(card: HTMLElement) {
  const st = card.style
  for (const p of ['mask-image', '-webkit-mask-image', 'mask-size', '-webkit-mask-size', 'mask-position', '-webkit-mask-position', 'mask-repeat', '-webkit-mask-repeat', '--notch-w', '--notch-h'])
    st.removeProperty(p)
}

/** `use:notch={island}` на карточке: вырез следует за размером островка (кнопка «Назад»
 *  выезжает — чёлка растёт вместе с ней, каждый кадр). */
export function notch(card: HTMLElement, island: HTMLElement | undefined) {
  let raf = 0
  let target = island
  const ro = new ResizeObserver(() => {
    if (raf) return
    raf = requestAnimationFrame(() => {
      raf = 0
      if (target) apply(card, target)
    })
  })
  const watch = (el: HTMLElement | undefined) => {
    ro.disconnect()
    target = el
    if (!el) return clear(card)
    ro.observe(el)
    ro.observe(card)
    apply(card, el)
  }
  watch(island)
  return {
    update: watch,
    destroy() {
      ro.disconnect()
      cancelAnimationFrame(raf)
      clear(card)
    },
  }
}
