// Сгусток цвета обложки летит в кнопку волны — как у Dotify (FlyingOrb в view-CvHfwEcU.js):
// шар 60 px с радиальным градиентом цвета обложки; по X — прямо к кнопке (0.42 с, ease .16,1,.3,1),
// по Y — чуть вверх и вниз в кнопку, масштаб 0.65 → 1.15 → 0.85. «Меньше движения» — без полёта.
import { reducedMotion } from './motion'
import type { RGB } from '../theme/palette'

export function flyOrb(from: Element, to: Element, [r, g, b]: RGB): Promise<void> {
  if (reducedMotion()) return Promise.resolve()
  const a = from.getBoundingClientRect()
  const c = to.getBoundingClientRect()
  const fx = a.left + a.width / 2
  const fy = a.top + a.height / 2
  const tx = c.left + c.width / 2
  const ty = c.top + c.height / 2

  const outer = document.createElement('div')
  const orb = document.createElement('div')
  Object.assign(outer.style, { position: 'fixed', left: '0', top: '0', zIndex: '80', pointerEvents: 'none' })
  Object.assign(orb.style, {
    width: '60px',
    height: '60px',
    borderRadius: '50%',
    background: `radial-gradient(circle at center, rgba(${r},${g},${b},0.95) 0%, rgba(${r},${g},${b},0.55) 35%, rgba(${r},${g},${b},0.15) 60%, transparent 75%)`,
  })
  outer.appendChild(orb)
  document.body.appendChild(outer)

  const ms = 420
  outer.animate([{ transform: `translateX(${fx - 30}px)` }, { transform: `translateX(${tx - 30}px)` }], {
    duration: ms,
    easing: 'cubic-bezier(0.16, 1, 0.3, 1)',
    fill: 'forwards',
  })
  const y = orb.animate(
    [
      { transform: `translateY(${fy - 30}px) scale(0.65)`, opacity: 0.95 },
      { transform: `translateY(${Math.min(fy, ty) - 38}px) scale(1.15)`, opacity: 1 },
      { transform: `translateY(${ty - 30}px) scale(0.85)`, opacity: 0.85 },
    ],
    { duration: ms, easing: 'cubic-bezier(0.25, 1, 0.5, 1)', fill: 'forwards' },
  )
  return y.finished
    .catch(() => {})
    .then(() => {
      outer.remove()
      to.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.08)' }, { transform: 'scale(1)' }], { duration: 260, easing: 'ease-out' })
    })
}
