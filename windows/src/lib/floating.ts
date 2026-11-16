// Плавающие элементы над контентом — их можно перетащить в любое место окна:
// - мини-плеер (Плеер → Мини плеер → Позиция «Плавающий»): тянется за свободное место, не за кнопки
//   и ползунки; позиция — mini.float_x / _y;
// - панель вкладок (Интерфейс → Вкладки → Стиль «Плавающий», решение владельца 2026-11-17): тянется за
//   что угодно, даже за иконку — сдвиг больше 5 px считается перетаскиванием, и клик гасится;
//   позиция — tabs.float_x / _y.
// Позиция — доли окна (центр элемента), чтобы не уезжала за край при смене размера окна.
import { settings } from './settings.svelte'

const clamp = (v: number, a: number, b: number) => Math.min(b, Math.max(a, v))

export interface FloatOpts {
  on: boolean
  /** Чья позиция: мини-плеер или панель вкладок. */
  key?: 'mini' | 'tabs'
  /** Тянуть можно и за кнопки (с порогом 5 px). */
  grabButtons?: boolean
}

export function floating(node: HTMLElement, arg: boolean | FloatOpts) {
  let o: FloatOpts = typeof arg === 'boolean' ? { on: arg } : arg
  const kx = () => (o.key === 'tabs' ? 'tabs.float_x' : 'mini.float_x') as 'mini.float_x'
  const ky = () => (o.key === 'tabs' ? 'tabs.float_y' : 'mini.float_y') as 'mini.float_y'

  const place = () => {
    if (!o.on) {
      node.style.removeProperty('left')
      node.style.removeProperty('top')
      return
    }
    const w = node.offsetWidth
    const h = node.offsetHeight
    const x = clamp(settings.get(kx()) * innerWidth - w / 2, 8, innerWidth - w - 8)
    const y = clamp(settings.get(ky()) * innerHeight - h / 2, 8, innerHeight - h - 8)
    node.style.left = `${x}px`
    node.style.top = `${y}px`
  }
  let start: { x: number; y: number; left: number; top: number; id: number } | null = null
  let dragging = false
  let dragged = false
  const down = (e: PointerEvent) => {
    if (!o.on || e.button !== 0) return
    const onControl = (e.target as Element).closest('button, input, a, [role="slider"], .seek')
    if (onControl && !o.grabButtons) return
    const r = node.getBoundingClientRect()
    start = { x: e.clientX, y: e.clientY, left: r.left, top: r.top, id: e.pointerId }
    dragging = false
    dragged = false
    // до захвата указателя движение слушаем по всему окну — мышь могла резко уйти с иконки
    addEventListener('pointermove', move)
    addEventListener('pointerup', up)
    addEventListener('pointercancel', up)
    if (!onControl) begin()
  }
  const begin = () => {
    if (!start) return
    dragging = true
    node.setPointerCapture(start.id)
    node.classList.add('dragging')
  }
  const move = (e: PointerEvent) => {
    if (!start || e.pointerId !== start.id) return
    if (!dragging) {
      if (Math.hypot(e.clientX - start.x, e.clientY - start.y) < 5) return
      begin()
    }
    dragged = true
    const w = node.offsetWidth
    const h = node.offsetHeight
    node.style.left = `${clamp(start.left + e.clientX - start.x, 8, innerWidth - w - 8)}px`
    node.style.top = `${clamp(start.top + e.clientY - start.y, 8, innerHeight - h - 8)}px`
  }
  const up = () => {
    removeEventListener('pointermove', move)
    removeEventListener('pointerup', up)
    removeEventListener('pointercancel', up)
    if (!start) return
    start = null
    if (!dragging) return
    dragging = false
    node.classList.remove('dragging')
    const r = node.getBoundingClientRect()
    settings.set(kx(), (r.left + r.width / 2) / innerWidth)
    settings.set(ky(), (r.top + r.height / 2) / innerHeight)
  }
  // протащили за иконку — её клик не срабатывает
  const click = (e: MouseEvent) => {
    if (!dragged) return
    dragged = false
    e.preventDefault()
    e.stopPropagation()
  }
  node.addEventListener('pointerdown', down)
  node.addEventListener('click', click, true)
  addEventListener('resize', place)
  requestAnimationFrame(place)
  return {
    update(next: boolean | FloatOpts) {
      o = typeof next === 'boolean' ? { on: next } : next
      requestAnimationFrame(place)
    },
    destroy() {
      node.removeEventListener('pointerdown', down)
      node.removeEventListener('click', click, true)
      up()
      removeEventListener('resize', place)
    },
  }
}
