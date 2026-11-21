// Кэш сцены карты: паутина линий и круги рисуются один раз в запасной холст с полями вокруг экрана,
// а пока карту двигают или крутят колесо — на экран кладётся готовая картинка со сдвигом и масштабом.
// Перерисовка — только когда уехали за поля, масштаб ушёл далеко, сменились подсветка, данные или тема;
// после остановки — одна чёткая перерисовка. Тысячи линий на каждый пиксель движения больше не рисуем.
import type { Camera, Viewport } from './camera'

/** Поля вокруг экрана, доля большей стороны: столько можно утащить карту без перерисовки. */
export const LAYER_MARGIN = 0.35
/** Во сколько раз масштаб может уйти от снятого, пока показываем растянутую картинку. */
export const LAYER_MAX_SCALE = 1.8

export interface LayerShot {
  /** Камера, с которой сцена нарисована. */
  cam: Camera
  /** Экран в момент съёмки и поле вокруг него, CSS px. */
  vp: Viewport
  margin: number
}

export interface Blit {
  x: number
  y: number
  w: number
  h: number
  /** Масштаб относительно снятого: 1 — картинка чёткая. */
  scale: number
}

export const layerMargin = (vp: Viewport): number => Math.ceil(Math.max(vp.w, vp.h) * LAYER_MARGIN)

/** Размер запасного холста, CSS px. */
export const layerSize = (vp: Viewport, margin: number): Viewport => ({ w: vp.w + 2 * margin, h: vp.h + 2 * margin })

/** Куда положить снятую сцену, чтобы она совпала с камерой `cam`; `null` — не покрывает экран
 *  или масштаб ушёл слишком далеко (пора перерисовать). */
export function blitFor(shot: LayerShot, cam: Camera, vp: Viewport): Blit | null {
  if (vp.w !== shot.vp.w || vp.h !== shot.vp.h) return null
  const scale = cam.zoom / shot.cam.zoom
  if (!(scale > 0) || scale > LAYER_MAX_SCALE || scale < 1 / LAYER_MAX_SCALE) return null
  const size = layerSize(shot.vp, shot.margin)
  // точка слоя Lx → экран: Sx = scale·Lx − scale·(w/2 + M) + (Lcx − cx)·zoom + w/2
  const x = -scale * (vp.w / 2 + shot.margin) + (shot.cam.x - cam.x) * cam.zoom + vp.w / 2
  const y = -scale * (vp.h / 2 + shot.margin) + (shot.cam.y - cam.y) * cam.zoom + vp.h / 2
  const w = size.w * scale
  const h = size.h * scale
  // полпикселя запаса на округление
  if (x > 0.5 || y > 0.5 || x + w < vp.w - 0.5 || y + h < vp.h - 0.5) return null
  return { x, y, w, h, scale }
}

/** Картинка совпадает с камерой пиксель в пиксель — перерисовывать незачем. */
export const isSharp = (b: Blit): boolean => Math.abs(b.scale - 1) < 1e-6
