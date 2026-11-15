// Повторить анимацию появления, когда меняется ключ: `use:replay={track?.ref}` — название и
// артист мягко проявляются при смене трека (класс .track-in в app.css).
export function replay(node: HTMLElement, key: unknown, cls = 'track-in') {
  let prev = key
  return {
    update(next: unknown) {
      if (next === prev) return
      prev = next
      node.classList.remove(cls)
      void node.offsetWidth
      node.classList.add(cls)
    },
  }
}
