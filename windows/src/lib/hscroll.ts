// Горизонтальный ряд (карточки качества и стиля, ряды обложек). Обычное колесо всегда крутит
// страницу (решение владельца 2026-11-16: курсор над рядом не должен «залипать»). Вбок ряд листается
// Shift+колесом, тачпадом (горизонтальная прокрутка) или перетаскиванием мышью — плавно.
// `{ wheel: true }` — ряд вкладок и ряды плиток в настройках (качество, устройство вывода): там колесо
// листает сам ряд, а дойдя до края — страницу.
// `{ wheel: true, trap: true }` — плитки настроек: пока курсор над рядом, страница не едет вовсе, даже
// когда ряд долистан до края (решение владельца 2026-11-17).
// `trap: 'scrollable'` — то же, но только если ряду есть куда листать (полки главной: короткий ряд
// страницу не держит, решение владельца 2026-11-17).
export function hscroll(node: HTMLElement, opts: { wheel?: boolean; trap?: boolean | 'scrollable' } = {}) {
  let target = node.scrollLeft
  let raf = 0

  const step = () => {
    const d = target - node.scrollLeft
    if (Math.abs(d) < 0.5) {
      node.scrollLeft = target
      raf = 0
      return
    }
    node.scrollLeft += d * 0.22
    raf = requestAnimationFrame(step)
  }
  const max = () => node.scrollWidth - node.clientWidth

  const onWheel = (e: WheelEvent) => {
    if (e.ctrlKey || (!e.shiftKey && !opts.wheel) || Math.abs(e.deltaX) > Math.abs(e.deltaY)) return
    if (opts.trap === true || (opts.trap === 'scrollable' && max() > 1)) e.preventDefault()
    if (max() <= 1) return
    if (!raf) target = node.scrollLeft
    const dy = e.deltaMode === 1 ? e.deltaY * 40 : e.deltaY
    const next = Math.max(0, Math.min(max(), target + dy * 1.2))
    if (next === target) return
    e.preventDefault()
    target = next
    if (!raf) raf = requestAnimationFrame(step)
  }

  // перетаскивание мышью: сдвинули больше 5 px — это прокрутка, клик по карточке гасим
  let down: { x: number; left: number; id: number } | null = null
  let dragged = false
  const onDown = (e: PointerEvent) => {
    if (e.button !== 0 || e.pointerType !== 'mouse' || max() <= 1) return
    cancelAnimationFrame(raf)
    raf = 0
    down = { x: e.clientX, left: node.scrollLeft, id: e.pointerId }
    dragged = false
  }
  const onMove = (e: PointerEvent) => {
    if (!down || e.pointerId !== down.id) return
    const dx = e.clientX - down.x
    if (!dragged && Math.abs(dx) < 5) return
    if (!dragged) {
      dragged = true
      node.setPointerCapture(down.id)
      node.classList.add('dragging')
    }
    node.scrollLeft = down.left - dx
    target = node.scrollLeft
  }
  const onUp = () => {
    down = null
    node.classList.remove('dragging')
  }
  const onClick = (e: MouseEvent) => {
    if (dragged) {
      e.preventDefault()
      e.stopPropagation()
      dragged = false
    }
  }

  node.addEventListener('wheel', onWheel, { passive: false })
  node.addEventListener('pointerdown', onDown)
  node.addEventListener('pointermove', onMove)
  node.addEventListener('pointerup', onUp)
  node.addEventListener('pointercancel', onUp)
  node.addEventListener('click', onClick, true)
  return {
    destroy() {
      node.removeEventListener('wheel', onWheel)
      node.removeEventListener('pointerdown', onDown)
      node.removeEventListener('pointermove', onMove)
      node.removeEventListener('pointerup', onUp)
      node.removeEventListener('pointercancel', onUp)
      node.removeEventListener('click', onClick, true)
      cancelAnimationFrame(raf)
    },
  }
}
