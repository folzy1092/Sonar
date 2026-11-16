// «Пульс» лайка: когда значение становится true (лайкнули), элемент коротко подпрыгивает.
// `use:pulse={liked}` — на кнопке или значке ❤ (стиль .like-pop в app.css). У сердца играет анимация
// лайка выбранного стиля (lib/like-fx.ts, appearance.anim_like); у прочих значков и в стиле `pop` —
// прежний подскок.
import { likeFx } from './like-fx'

export function pulse(node: HTMLElement, on: boolean | undefined) {
  let prev = !!on
  const end = () => node.classList.remove('like-pop')
  node.addEventListener('animationend', end)
  return {
    update(next: boolean | undefined) {
      if (next && !prev && node.querySelector('svg.i-heart') && likeFx(node)) {
        prev = true
        return
      }
      if (next && !prev) {
        node.classList.remove('like-pop')
        void node.offsetWidth
        node.classList.add('like-pop')
      }
      prev = !!next
    },
    destroy() {
      node.removeEventListener('animationend', end)
    },
  }
}
