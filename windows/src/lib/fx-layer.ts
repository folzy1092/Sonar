// Слой эффектов поверх окна (Интерфейс → Стиль, STYLE_PROMPT §4): кольца, световая дуга, кардиограмма
// лайка рисуются в отдельном слое над интерфейсом — по прямоугольнику элемента, а не внутри него
// (у обложек `overflow: hidden`, кольцо обрезалось бы). Элемент слоя живёт `ms` и удаляется сам.
let layer: HTMLDivElement | null = null

function host(): HTMLDivElement {
  if (layer?.isConnected) return layer
  layer = document.createElement('div')
  layer.className = 'fx-layer'
  layer.setAttribute('aria-hidden', 'true')
  document.body.appendChild(layer)
  return layer
}

/** Поддерево без эффектов в слое: живые примеры в настройках (`MiniPreview.svelte`) и закрытая
 *  шторка настроек — она прозрачна, но лежит поверх окна, и кольца рисовались бы «из ниоткуда». */
export const FX_SKIP = '[data-fx-skip]'

/** Элемент внутри поддерева, помеченного `data-fx-skip`? */
export function skipped(el: Pick<Element, 'closest'>): boolean {
  return el.closest(FX_SKIP) !== null
}

/** Виден ли элемент (есть размер, попадает в окно, не в `data-fx-skip` и не закрыт полноэкранным
 *  слоем `data-fx-overlay` — иначе дуга мини-плеера рисовалась бы поверх полноэкранного плеера). */
export function visible(el: Element): DOMRect | null {
  if (skipped(el)) return null
  const overlay = document.querySelector('[data-fx-overlay]')
  if (overlay && !overlay.contains(el)) return null
  const r = el.getBoundingClientRect()
  if (r.width < 2 || r.height < 2 || r.bottom < 0 || r.right < 0 || r.top > innerHeight || r.left > innerWidth) return null
  return r
}

/** Положить эффект в слой над прямоугольником `rect` (`pad` — на сколько шире), убрать через `ms`. */
export function spawn(rect: DOMRect, html: string, cls: string, ms: number, pad = 0, style: Record<string, string> = {}): HTMLElement {
  const el = document.createElement('div')
  el.className = `fx ${cls}`
  el.innerHTML = html
  Object.assign(el.style, {
    left: `${rect.left - pad}px`,
    top: `${rect.top - pad}px`,
    width: `${rect.width + pad * 2}px`,
    height: `${rect.height + pad * 2}px`,
    ...style,
  })
  host().appendChild(el)
  setTimeout(() => el.remove(), ms)
  return el
}

/** Перезапустить CSS-анимацию элемента: снять класс, пересчитать вёрстку, поставить снова. */
export function restart(el: Element, cls: string, ms: number) {
  el.classList.remove(cls)
  void (el as HTMLElement).offsetWidth
  el.classList.add(cls)
  const prev = Number((el as HTMLElement).dataset.fxTimer)
  if (prev) clearTimeout(prev)
  ;(el as HTMLElement).dataset.fxTimer = String(setTimeout(() => el.classList.remove(cls), ms))
}
