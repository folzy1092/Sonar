// Камера карты исполнителей: какая точка мира в центре экрана и масштаб. Чистые функции —
// перетаскивание, колесо к курсору, «показать всё», перелёт к исполнителю.
import type { Bounds, Point } from './layout'

export interface Camera {
  /** Точка мира в центре видимой области. */
  x: number
  y: number
  zoom: number
}

export interface Viewport {
  w: number
  h: number
}

/** Ниже — круги в пиксель (самый мелкий R_MIN = 14 → ~4 px); владелец 2026-11-18: «не пихать по 10 на пиксель». */
export const ZOOM_MIN = 0.3
export const ZOOM_MAX = 4
/** Во сколько раз меняет масштаб один шаг колеса (deltaY = 100). */
const WHEEL_STEP = 1.18
const WHEEL_UNIT = 100
/** Отступ при «показать всё» — доля от меньшей стороны. */
const FIT_PAD = 0.08
/** Масштаб, на котором перелетаем к найденному исполнителю. */
export const FOCUS_ZOOM = 1.6

export const clampZoom = (z: number) => Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, z))

export function toScreen(cam: Camera, vp: Viewport, p: Point): Point {
  return { x: (p.x - cam.x) * cam.zoom + vp.w / 2, y: (p.y - cam.y) * cam.zoom + vp.h / 2 }
}

export function toWorld(cam: Camera, vp: Viewport, s: Point): Point {
  return { x: (s.x - vp.w / 2) / cam.zoom + cam.x, y: (s.y - vp.h / 2) / cam.zoom + cam.y }
}

/** Сдвиг на `dx, dy` пикселей экрана (перетаскивание). */
export function panBy(cam: Camera, dx: number, dy: number): Camera {
  return { ...cam, x: cam.x - dx / cam.zoom, y: cam.y - dy / cam.zoom }
}

/** Масштаб с неподвижной точкой под курсором `s`. */
export function zoomAt(cam: Camera, vp: Viewport, s: Point, factor: number): Camera {
  const zoom = clampZoom(cam.zoom * factor)
  const before = toWorld(cam, vp, s)
  const next = { ...cam, zoom }
  const after = toWorld(next, vp, s)
  return { zoom, x: next.x + (before.x - after.x), y: next.y + (before.y - after.y) }
}

/** Множитель масштаба для колеса: вверх — ближе. */
export function wheelFactor(deltaY: number): number {
  return Math.pow(WHEEL_STEP, -deltaY / WHEEL_UNIT)
}

/** Вся карта в видимой области. Не влезает даже на самом мелком масштабе — в центре `anchor`
 *  (главная кучка), остальное — прокруткой, а не точками в пиксель. */
export function fit(b: Bounds, vp: Viewport, anchor?: Point): Camera {
  const pad = Math.min(vp.w, vp.h) * FIT_PAD
  const w = Math.max(1, b.maxX - b.minX)
  const h = Math.max(1, b.maxY - b.minY)
  const want = Math.min(1.4, (vp.w - 2 * pad) / w, (vp.h - 2 * pad) / h)
  const zoom = clampZoom(want)
  if (want < ZOOM_MIN && anchor) return { x: anchor.x, y: anchor.y, zoom }
  return { x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2, zoom }
}

/** Промежуточная камера перелёта, `t` — уже сглаженный 0..1. Масштаб — геометрически, чтобы
 *  приближение не «рывком в конце». */
export function between(a: Camera, b: Camera, t: number): Camera {
  const k = Math.min(1, Math.max(0, t))
  return {
    x: a.x + (b.x - a.x) * k,
    y: a.y + (b.y - a.y) * k,
    zoom: a.zoom * Math.pow(b.zoom / a.zoom, k),
  }
}

/** Круг хотя бы краем на экране. */
export function onScreen(cam: Camera, vp: Viewport, p: Point, r: number): boolean {
  const s = toScreen(cam, vp, p)
  const rr = r * cam.zoom
  return s.x + rr >= 0 && s.y + rr >= 0 && s.x - rr <= vp.w && s.y - rr <= vp.h
}
