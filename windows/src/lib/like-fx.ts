// Анимация лайка — «подпись» стиля (appearance.anim_like, STYLE_PROMPT §4). Зовётся из `use:pulse`, когда
// лайк ставится; элемент — обёртка значка ❤.
//   echo     — кольцо от сердца .7→2.1, сердце .84→1.1→1;
//   signal   — от сердца бежит импульс-кардиограмма + сердце как у echo;
//   edge     — сердце обводится по контуру, потом заливается;
//   tactile  — над сердцем вспыхивает светодиод с послесвечением;
//   monolith — кольцо .7→1.9;
//   pop      — прежний подскок (.like-pop).
// «Меньше движения» — только прозрачность: заливка сердца проявляется, без колец и подскоков.
import { settings } from './settings.svelte'
import { reducedMotion } from './motion'
import { restart, spawn, visible } from './fx-layer'

const HEART = 'M12 19.6s-7.3-4.4-8.9-8.9C1.9 7.4 4 4.4 7.2 4.4c2 0 3.5 1.1 4.8 2.9 1.3-1.8 2.8-2.9 4.8-2.9 3.2 0 5.3 3 4.1 6.3-1.6 4.5-8.9 8.9-8.9 8.9Z'

/** Сыграть анимацию лайка на значке. Вернёт false, если анимация — прежний `pop` (его играет pulse). */
export function likeFx(node: HTMLElement): boolean {
  const kind = settings.get('appearance.anim_like')
  if (kind === 'pop') return false
  if (reducedMotion()) return true
  const r = visible(node)
  if (!r) return true
  if (kind === 'echo' || kind === 'signal') restart(node, 'fx-heart-bounce', 400)
  if (kind === 'echo') spawn(r, '', 'fx-like-ring echo', 520)
  if (kind === 'monolith') spawn(r, '', 'fx-like-ring mono', 500)
  if (kind === 'signal') {
    spawn(r, '<svg viewBox="0 0 34 14"><path d="M0 7h9l3-6 5 12 3-6h14" pathLength="60"/></svg>', 'fx-ecg', 560, 0, {
      left: `${r.right + 2}px`,
      width: `${Math.max(28, r.width * 1.6)}px`,
      top: `${r.top + r.height / 2 - 7}px`,
      height: '14px',
    })
  }
  if (kind === 'edge') {
    // сердце обводится по контуру и заливается — поверх самого значка
    restart(node, 'fx-heart-hidden', 500)
    spawn(r, `<svg viewBox="0 0 24 24"><path d="${HEART}" pathLength="60"/></svg>`, 'fx-heart-draw', 520)
  }
  if (kind === 'tactile') spawn(r, '<i></i>', 'fx-led', 640)
  return true
}
