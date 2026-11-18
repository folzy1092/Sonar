// Подсказка «там ещё есть» у горизонтального ряда (как у Dotify): край, за которым есть пункты,
// мягко затухает. Класс `.edges` + `data-l` / `data-r` — стили в app.css. Когда есть что-то слева /
// справа, решает общая логика стрелок `lib/hscroll.ts` (`arrowsFor` + `watchOverflow`: размер ряда и
// карточек, новые карточки, прокрутка). `onchange` — то же для стрелок у полок.
import { watchOverflow } from './hscroll'

export function edges(node: HTMLElement, onchange?: (left: boolean, right: boolean) => void) {
  node.classList.add('edges')
  let cb = onchange
  let state: [boolean, boolean] = [false, false]
  const stop = watchOverflow(node, (l, r) => {
    state = [l, r]
    node.toggleAttribute('data-l', l)
    node.toggleAttribute('data-r', r)
    cb?.(l, r)
  })
  return {
    update(next?: (left: boolean, right: boolean) => void) {
      cb = next
      cb?.(...state)
    },
    destroy: stop,
  }
}
