import { describe, expect, it } from 'vitest'
import { between, clampZoom, fit, onScreen, panBy, toScreen, toWorld, wheelFactor, zoomAt, ZOOM_MAX, ZOOM_MIN, type Camera } from './camera'

const vp = { w: 800, h: 600 }
const cam: Camera = { x: 120, y: -40, zoom: 1.5 }

describe('камера', () => {
  it('экран ↔ мир — туда и обратно', () => {
    const p = { x: 33, y: 71 }
    const back = toWorld(cam, vp, toScreen(cam, vp, p))
    expect(back.x).toBeCloseTo(p.x, 9)
    expect(back.y).toBeCloseTo(p.y, 9)
    expect(toScreen(cam, vp, { x: cam.x, y: cam.y })).toEqual({ x: 400, y: 300 })
  })

  it('колесо приближает к курсору: точка под ним не уезжает', () => {
    const cursor = { x: 610, y: 145 }
    const before = toWorld(cam, vp, cursor)
    const next = zoomAt(cam, vp, cursor, wheelFactor(-100))
    expect(next.zoom).toBeGreaterThan(cam.zoom)
    const after = toWorld(next, vp, cursor)
    expect(after.x).toBeCloseTo(before.x, 9)
    expect(after.y).toBeCloseTo(before.y, 9)
  })

  it('масштаб не выходит за пределы', () => {
    expect(clampZoom(100)).toBe(ZOOM_MAX)
    expect(clampZoom(0)).toBe(ZOOM_MIN)
    expect(zoomAt(cam, vp, { x: 0, y: 0 }, 1000).zoom).toBe(ZOOM_MAX)
    expect(wheelFactor(100)).toBeLessThan(1)
    expect(wheelFactor(0)).toBe(1)
  })

  it('перетаскивание двигает мир за курсором', () => {
    const p = { x: 10, y: 20 }
    const s = toScreen(cam, vp, p)
    const moved = panBy(cam, 50, -30)
    const s2 = toScreen(moved, vp, p)
    expect(s2.x - s.x).toBeCloseTo(50, 9)
    expect(s2.y - s.y).toBeCloseTo(-30, 9)
  })

  it('«показать всё» помещает рамку целиком', () => {
    const b = { minX: -900, minY: -200, maxX: 1500, maxY: 700 }
    const c = fit(b, vp)
    const tl = toScreen(c, vp, { x: b.minX, y: b.minY })
    const br = toScreen(c, vp, { x: b.maxX, y: b.maxY })
    expect(tl.x).toBeGreaterThanOrEqual(0)
    expect(tl.y).toBeGreaterThanOrEqual(0)
    expect(br.x).toBeLessThanOrEqual(vp.w)
    expect(br.y).toBeLessThanOrEqual(vp.h)
  })

  it('перелёт начинается и кончается в нужных камерах', () => {
    const to: Camera = { x: -300, y: 500, zoom: 0.4 }
    expect(between(cam, to, 0)).toEqual(cam)
    const end = between(cam, to, 1)
    expect(end.x).toBeCloseTo(to.x, 9)
    expect(end.y).toBeCloseTo(to.y, 9)
    expect(end.zoom).toBeCloseTo(to.zoom, 9)
    const mid = between(cam, to, 0.5)
    expect(mid.zoom).toBeCloseTo(Math.sqrt(cam.zoom * to.zoom), 9)
  })

  it('видимость круга — хотя бы краем', () => {
    const c: Camera = { x: 0, y: 0, zoom: 1 }
    expect(onScreen(c, vp, { x: 0, y: 0 }, 10)).toBe(true)
    expect(onScreen(c, vp, { x: 405, y: 0 }, 10)).toBe(true)
    expect(onScreen(c, vp, { x: 420, y: 0 }, 10)).toBe(false)
  })
})
