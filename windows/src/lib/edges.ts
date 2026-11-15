// Подсказка «там ещё есть» у горизонтального ряда (как у Dotify): край, за которым есть пункты,
// мягко затухает. Класс `.edges` + `data-l` / `data-r` — стили в app.css. Следит за прокруткой и размером
// (и за новыми карточками). `onchange` — узнать, есть ли что-то слева / справа (стрелки у полок).
export function edges(node: HTMLElement, onchange?: (left: boolean, right: boolean) => void) {
  node.classList.add('edges')
  let cb = onchange
  const update = () => {
    const max = node.scrollWidth - node.clientWidth
    const l = node.scrollLeft > 2
    const r = max - node.scrollLeft > 2
    node.toggleAttribute('data-l', l)
    node.toggleAttribute('data-r', r)
    cb?.(l, r)
  }
  const ro = new ResizeObserver(update)
  const watch = () => {
    ro.disconnect()
    ro.observe(node)
    for (const c of Array.from(node.children)) ro.observe(c)
  }
  watch()
  // карточки догружаются позже (главная, поиск) — следим и за ними
  const mo = new MutationObserver(() => {
    watch()
    update()
  })
  mo.observe(node, { childList: true })
  node.addEventListener('scroll', update, { passive: true })
  requestAnimationFrame(update)
  return {
    update(next?: (left: boolean, right: boolean) => void) {
      cb = next
    },
    destroy() {
      ro.disconnect()
      mo.disconnect()
      node.removeEventListener('scroll', update)
    },
  }
}
