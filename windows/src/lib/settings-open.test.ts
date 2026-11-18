import { describe, expect, it } from 'vitest'
import { SHUTTER_MS, isShutter, openMode, springEasing, veilClip } from './settings-open'

describe('как открываются настройки', () => {
  it('вкладки сверху и снизу — шторка с той же стороны', () => {
    expect(openMode('top', 'default')).toBe('top')
    expect(openMode('bottom', 'compact')).toBe('bottom')
    expect(isShutter('top')).toBe(true)
    expect(isShutter('bottom')).toBe(true)
  })

  it('вкладки сбоку — прежний выезд с 3D-наклоном', () => {
    expect(openMode('left', 'default')).toBe('left')
    expect(openMode('right', 'round')).toBe('right')
    expect(isShutter('left')).toBe(false)
    expect(isShutter('right')).toBe(false)
  })

  it('плавающая панель живёт как левая', () => {
    expect(openMode('top', 'floating')).toBe('left')
    expect(openMode('right', 'floating')).toBe('left')
  })
})

describe('пружина шторки', () => {
  const values = (s: string) =>
    s
      .replace(/^linear\(|\)$/g, '')
      .split(',')
      .map(Number)

  it('около 350 мс', () => {
    expect(SHUTTER_MS).toBeGreaterThanOrEqual(300)
    expect(SHUTTER_MS).toBeLessThanOrEqual(400)
  })

  it('CSS linear() от 0 до 1 с лёгким перелётом', () => {
    const css = springEasing()
    expect(css.startsWith('linear(0,')).toBe(true)
    const v = values(css)
    expect(v.every((x) => Number.isFinite(x))).toBe(true)
    expect(v[v.length - 1]).toBe(1)
    const peak = Math.max(...v)
    expect(peak).toBeGreaterThan(1)
    expect(peak).toBeLessThan(1.08)
  })

  it('сначала только растёт', () => {
    const v = values(springEasing())
    const top = v.indexOf(Math.max(...v))
    for (let i = 1; i <= top; i++) expect(v[i]).toBeGreaterThanOrEqual(v[i - 1])
  })
})

describe('вуаль под шторкой', () => {
  it('вырезает дырку под панель вкладок, чтобы шестерёнка нажималась', () => {
    const clip = veilClip({ left: 10, top: 4, right: 210, bottom: 50 })
    expect(clip).toBe('polygon(evenodd, 0 0, 100% 0, 100% 100%, 0 100%, 0 0, 10px 4px, 210px 4px, 210px 50px, 10px 50px, 10px 4px)')
  })

  it('без панели — вуаль целиком', () => {
    expect(veilClip(null)).toBe('none')
  })
})
