// Смена состояния кнопки-переключателя (повтор, перемешивание): значок коротко вырастает 0.9 → 1
// (класс .toggle-pop в app.css). При первом показе не играет. «Меньше движения» гасит анимацию
// глобально в app.css — остаётся только плавная смена цвета.

export function togglePop(node: HTMLElement, state: string) {
  let prev = state
  const end = () => node.classList.remove('toggle-pop')
  node.addEventListener('animationend', end)
  return {
    update(next: string) {
      if (next === prev) return
      prev = next
      node.classList.remove('toggle-pop')
      void node.offsetWidth
      node.classList.add('toggle-pop')
    },
    destroy() {
      node.removeEventListener('animationend', end)
    },
  }
}
