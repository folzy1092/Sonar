import { describe, expect, it } from 'vitest'
import { OVERLAY_ANCHORS, anchorAlign, autoStep, nearestAnchor, overlayLayout, type AutoState } from './overlay'

describe('оверлей: размер окна', () => {
  it('карточка — ширина и высота с масштабом', () => {
    expect(overlayLayout('card', 340, 58, 100, 'tc')).toEqual({ width: 340, height: 58, anchor: 'tc', fullscreen: false, monitor: 'primary' })
    expect(overlayLayout('card', 340, 58, 150, 'br')).toEqual({ width: 510, height: 87, anchor: 'br', fullscreen: false, monitor: 'primary' })
  })

  it('монитор уходит в Rust как есть', () => {
    expect(overlayLayout('card', 340, 58, 100, 'tc', 'path-b').monitor).toBe('path-b')
    expect(overlayLayout('island', 340, 58, 100, 'tc', 'path-b').monitor).toBe('path-b')
  })

  it('остров меньше карточки, но не ниже 34 px', () => {
    const island = overlayLayout('island', 340, 58, 100, 'tc')
    expect(island.width).toBeLessThan(340)
    expect(island.height).toBeLessThan(58)
    expect(overlayLayout('island', 340, 44, 100, 'tc').height).toBe(34)
  })

  it('полноэкранный помечен, масштаб зажат в пределы', () => {
    expect(overlayLayout('fullscreen', 340, 58, 100, 'mc').fullscreen).toBe(true)
    expect(overlayLayout('card', 300, 50, 1000, 'tc').width).toBe(600)
    expect(overlayLayout('card', 300, 50, 1, 'tc').width).toBe(150)
  })
})

describe('оверлей: сетка 3×3', () => {
  it('девять разных клеток', () => {
    expect(new Set(OVERLAY_ANCHORS).size).toBe(9)
  })

  it('выравнивание клетки', () => {
    expect(anchorAlign('tl')).toEqual({ x: 0, y: 0 })
    expect(anchorAlign('mc')).toEqual({ x: 0.5, y: 0.5 })
    expect(anchorAlign('br')).toEqual({ x: 1, y: 1 })
  })

  it('отпущенная плашка прилипает к ближайшей клетке', () => {
    expect(nearestAnchor(0.1, 0.1)).toBe('tl')
    expect(nearestAnchor(0.5, 0.5)).toBe('mc')
    expect(nearestAnchor(0.9, 0.95)).toBe('br')
    expect(nearestAnchor(0.5, 0.05)).toBe('tc')
  })

  it('клетка и её выравнивание сходятся', () => {
    for (const a of OVERLAY_ANCHORS) {
      const { x, y } = anchorAlign(a)
      expect(nearestAnchor(x, y)).toBe(a)
    }
  })
})

describe('оверлей: появляться само', () => {
  const base: AutoState = { auto: true, mode: 'card', mainShown: false, miniOpen: false, overlayOpen: false, openedByAuto: false }

  it('Sonar свернули — открыть', () => {
    expect(autoStep(base)).toBe('open')
  })

  it('выключено, режим «Отключен» или открыто мини-окно — молчим', () => {
    expect(autoStep({ ...base, auto: false })).toBeNull()
    expect(autoStep({ ...base, mode: 'off' })).toBeNull()
    expect(autoStep({ ...base, miniOpen: true })).toBeNull()
    expect(autoStep({ ...base, mainShown: true })).toBeNull()
  })

  it('Sonar вернулся — закрыть только открытый «само»', () => {
    expect(autoStep({ ...base, mainShown: true, overlayOpen: true, openedByAuto: true })).toBe('close')
    expect(autoStep({ ...base, mainShown: true, overlayOpen: true, openedByAuto: false })).toBeNull()
  })

  it('«само» выключили, пока оверлей висит, — закрыть', () => {
    expect(autoStep({ ...base, auto: false, overlayOpen: true, openedByAuto: true })).toBe('close')
  })
})
