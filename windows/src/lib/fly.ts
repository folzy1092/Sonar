// Обложка «летит» частицей к кнопке плеера: копия картинки по дуге уменьшается и гаснет в кнопке,
// кнопка в ответ коротко подпрыгивает (главная, «Моя волна»). «Меньше движения» — без полёта.
import { reducedMotion } from './motion'

export function flyTo(from: Element, to: Element, src: string | null | undefined) {
  if (!src || reducedMotion()) return
  const a = from.getBoundingClientRect()
  const b = to.getBoundingClientRect()
  const img = document.createElement('img')
  img.src = src
  img.alt = ''
  Object.assign(img.style, {
    position: 'fixed',
    left: `${a.left}px`,
    top: `${a.top}px`,
    width: `${a.width}px`,
    height: `${a.height}px`,
    objectFit: 'cover',
    borderRadius: '14px',
    zIndex: '80',
    pointerEvents: 'none',
    boxShadow: '0 14px 34px rgba(0,0,0,0.5)',
  })
  document.body.appendChild(img)
  const dx = b.left + b.width / 2 - (a.left + a.width / 2)
  const dy = b.top + b.height / 2 - (a.top + a.height / 2)
  const end = Math.min(b.width, b.height) / Math.max(a.width, 1) * 0.5
  // дуга: середина пути приподнята
  const lift = -Math.max(40, Math.abs(dx) * 0.18)
  const anim = img.animate(
    [
      { transform: 'translate(0, 0) scale(1) rotate(0deg)', opacity: 1, borderRadius: '14px' },
      { transform: `translate(${dx * 0.5}px, ${dy * 0.5 + lift}px) scale(${(1 + end) / 2}) rotate(-8deg)`, opacity: 0.95, borderRadius: '30%', offset: 0.5 },
      { transform: `translate(${dx}px, ${dy}px) scale(${end}) rotate(0deg)`, opacity: 0, borderRadius: '50%' },
    ],
    { duration: 620, easing: 'cubic-bezier(0.5, 0, 0.3, 1)' },
  )
  anim.onfinish = () => {
    img.remove()
    to.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.14)' }, { transform: 'scale(1)' }], { duration: 320, easing: 'ease-out' })
  }
}
