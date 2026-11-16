// Плавающий мини-плеер (Плеер → Мини плеер → Позиция «Плавающий»): капсула над контентом, её можно
// перетащить за свободное место (не за кнопки и ползунки). Позиция — доли окна (mini.float_x / _y,
// центр капсулы), чтобы не уезжала за край при смене размера окна.
import { settings } from './settings.svelte'

const clamp = (v: number, a: number, b: number) => Math.min(b, Math.max(a, v))

export function floating(node: HTMLElement, on: boolean) {
  let active = on
  const place = () => {
    if (!active) {
      node.style.removeProperty('left')
      node.style.removeProperty('top')
      return
    }
    const w = node.offsetWidth
    const h = node.offsetHeight
    const x = clamp(settings.get('mini.float_x') * innerWidth - w / 2, 8, innerWidth - w - 8)
    const y = clamp(settings.get('mini.float_y') * innerHeight - h / 2, 8, innerHeight - h - 8)
    node.style.left = `${x}px`
    node.style.top = `${y}px`
  }
  let start: { x: number; y: number; left: number; top: number } | null = null
  const down = (e: PointerEvent) => {
    if (!active || e.button !== 0) return
    if ((e.target as Element).closest('button, input, a, [role="slider"], .seek')) return
    const r = node.getBoundingClientRect()
    start = { x: e.clientX, y: e.clientY, left: r.left, top: r.top }
    node.setPointerCapture(e.pointerId)
    node.classList.add('dragging')
  }
  const move = (e: PointerEvent) => {
    if (!start) return
    const w = node.offsetWidth
    const h = node.offsetHeight
    node.style.left = `${clamp(start.left + e.clientX - start.x, 8, innerWidth - w - 8)}px`
    node.style.top = `${clamp(start.top + e.clientY - start.y, 8, innerHeight - h - 8)}px`
  }
  const up = () => {
    if (!start) return
    start = null
    node.classList.remove('dragging')
    const r = node.getBoundingClientRect()
    settings.set('mini.float_x', (r.left + r.width / 2) / innerWidth)
    settings.set('mini.float_y', (r.top + r.height / 2) / innerHeight)
  }
  node.addEventListener('pointerdown', down)
  node.addEventListener('pointermove', move)
  node.addEventListener('pointerup', up)
  node.addEventListener('pointercancel', up)
  addEventListener('resize', place)
  requestAnimationFrame(place)
  return {
    update(next: boolean) {
      active = next
      requestAnimationFrame(place)
    },
    destroy() {
      node.removeEventListener('pointerdown', down)
      node.removeEventListener('pointermove', move)
      node.removeEventListener('pointerup', up)
      node.removeEventListener('pointercancel', up)
      removeEventListener('resize', place)
    },
  }
}
