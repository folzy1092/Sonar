import { describe, expect, it } from 'vitest'
import { blitFor, isSharp, layerMargin, layerSize, LAYER_MAX_SCALE } from './scene-cache'
import { toScreen, type Camera } from './camera'

const vp = { w: 1000, h: 600 }
const margin = layerMargin(vp)
const shotCam: Camera = { x: 100, y: 50, zoom: 1.2 }
const shot = { cam: shotCam, vp, margin }

/** Где точка мира окажется на экране, если положить слой по `blitFor`. */
function viaLayer(cam: Camera, p: { x: number; y: number }) {
  const b = blitFor(shot, cam, vp)!
  const big = layerSize(vp, margin)
  const onLayer = toScreen(shotCam, big, p) // слой — тот же кадр на увеличенном «экране»
  return { x: b.x + onLayer.x * b.scale, y: b.y + onLayer.y * b.scale }
}

describe('кэш сцены карты', () => {
  it('без движения — слой ровно на месте и чёткий', () => {
    const b = blitFor(shot, shotCam, vp)!
    expect(b.x).toBeCloseTo(-margin)
    expect(b.y).toBeCloseTo(-margin)
    expect(isSharp(b)).toBe(true)
  })

  it('сдвиг и масштаб: точка мира попадает туда же, куда нарисовала бы камера', () => {
    for (const cam of [
      { x: 160, y: 20, zoom: 1.2 },
      { x: 90, y: 70, zoom: 1.5 },
      { x: 110, y: 40, zoom: 0.9 },
    ]) {
      for (const p of [{ x: 100, y: 50 }, { x: 300, y: -80 }, { x: -50, y: 200 }]) {
        const want = toScreen(cam, vp, p)
        const got = viaLayer(cam, p)
        expect(got.x).toBeCloseTo(want.x, 6)
        expect(got.y).toBeCloseTo(want.y, 6)
      }
    }
  })

  it('утащили за поля или масштаб ушёл далеко — перерисовать', () => {
    expect(blitFor(shot, { ...shotCam, x: shotCam.x + (margin + 10) / shotCam.zoom }, vp)).toBeNull()
    expect(blitFor(shot, { ...shotCam, zoom: shotCam.zoom * (LAYER_MAX_SCALE + 0.1) }, vp)).toBeNull()
    // отдалились — слой меньше экрана, краёв не хватает
    expect(blitFor(shot, { ...shotCam, zoom: shotCam.zoom / 1.75 }, vp)).toBeNull()
    expect(blitFor(shot, shotCam, { w: 1001, h: 600 })).toBeNull()
  })
})
