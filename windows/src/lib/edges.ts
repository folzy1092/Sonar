// Подсказка «там ещё есть» у горизонтального ряда (как у Dotify): край, за которым есть пункты,
// мягко затухает. Класс `.edges` + `data-l` / `data-r` — стили в app.css. Следит за прокруткой и размером.
export function edges(node: HTMLElement) {
  node.classList.add('edges')
  const update = () => {
    const max = node.scrollWidth - node.clientWidth
    node.toggleAttribute('data-l', node.scrollLeft > 2)
    node.toggleAttribute('data-r', max - node.scrollLeft > 2)
  }
  const ro = new ResizeObserver(update)
  ro.observe(node)
  for (const c of Array.from(node.children)) ro.observe(c)
  node.addEventListener('scroll', update, { passive: true })
  requestAnimationFrame(update)
  return {
    destroy() {
      ro.disconnect()
      node.removeEventListener('scroll', update)
    },
  }
}
