// Горизонтальный ряд (карточки качества, ряды обложек) листается обычным колесом мыши: вертикальная
// прокрутка превращается в плавный сдвиг вбок. Дошли до края ряда — колесо снова крутит страницу.
export function hscroll(node: HTMLElement) {
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

  const onWheel = (e: WheelEvent) => {
    if (e.ctrlKey || Math.abs(e.deltaX) > Math.abs(e.deltaY)) return
    const max = node.scrollWidth - node.clientWidth
    if (max <= 1) return
    if (!raf) target = node.scrollLeft
    const dy = e.deltaMode === 1 ? e.deltaY * 40 : e.deltaY
    const next = Math.max(0, Math.min(max, target + dy * 1.2))
    if (next === target) return // край ряда — пусть крутится страница
    e.preventDefault()
    target = next
    if (!raf) raf = requestAnimationFrame(step)
  }

  node.addEventListener('wheel', onWheel, { passive: false })
  return {
    destroy() {
      node.removeEventListener('wheel', onWheel)
      cancelAnimationFrame(raf)
    },
  }
}
