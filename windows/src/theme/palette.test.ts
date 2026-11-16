import { describe, expect, it } from 'vitest'
import { contrast, hslToRgb, inkFor, kmeans, oklchToRgb, pickAccent, rgbToHsl, rgbToOklch, SURFACES, themeFrom, type Lch, type RGB, type Surface } from './palette'

function image(colors: [number, number, number, number][]): number[] {
  return colors.flatMap(([r, g, b, n]) => Array.from({ length: n }, () => [r, g, b, 255]).flat())
}

describe('palette', () => {
  it('hsl round trip', () => {
    for (const c of [[255, 0, 0], [12, 200, 90], [30, 30, 30]] as [number, number, number][]) {
      expect(hslToRgb(rgbToHsl(c))).toEqual(c)
    }
  })

  it('k-means finds dominant clusters', () => {
    const res = kmeans(image([[250, 20, 20, 300], [20, 20, 250, 100]]), 2)
    const top = res.sort((a, b) => b.share - a.share)[0]
    expect(top.color[0]).toBeGreaterThan(200)
    expect(top.share).toBeCloseTo(0.75, 1)
  })

  it('skips near black and white, picks saturated', () => {
    const px = image([[5, 5, 5, 500], [250, 250, 250, 300], [200, 40, 60, 80]])
    const c = pickAccent(px)
    expect(c).not.toBeNull()
    expect(c![0]).toBeGreaterThan(150)
    expect(pickAccent(image([[5, 5, 5, 100], [128, 128, 128, 100]]))).toBeNull()
  })

  it('ink is readable', () => {
    expect(inkFor([255, 230, 0])).toEqual([10, 10, 11])
    expect(inkFor([40, 20, 120])).toEqual([255, 255, 255])
    const t = themeFrom([120, 20, 30])
    expect(contrast(t.accent, t.ink)).toBeGreaterThanOrEqual(4)
  })
})

describe('oklch palette', () => {
  const COVERS: Record<string, [number, number, number]> = {
    'тёмно-синяя': [28, 36, 104],
    'кислотно-розовая': [255, 24, 178],
    'почти чёрная': [26, 22, 20],
    жёлтая: [250, 222, 32],
    белая: [246, 246, 244],
    серая: [128, 128, 128],
  }
  const rgb = (x: Lch) => oklchToRgb(x)

  it('round trip rgb ↔ oklch', () => {
    for (const c of [[255, 0, 0], [12, 200, 90], [30, 30, 30], [250, 222, 32]] as RGB[]) {
      const back = oklchToRgb(rgbToOklch(c))
      back.forEach((v, i) => expect(Math.abs(v - c[i])).toBeLessThanOrEqual(1))
    }
  })

  it('grey cover is monochrome', () => {
    expect(themeFrom([128, 128, 128]).mono).toBe(true)
    expect(themeFrom(null).mono).toBe(true)
    expect(themeFrom([255, 24, 178]).mono).toBe(false)
  })

  for (const surface of Object.keys(SURFACES) as Surface[]) {
    for (const [name, cover] of Object.entries(COVERS)) {
      it(`contrast (светлая): ${surface} × ${name}`, () => {
        const { lch } = themeFrom(cover, surface, true)
        expect(contrast(rgb(lch.t3), rgb(lch.s1))).toBeGreaterThanOrEqual(4.5)
        expect(contrast(rgb(lch.text), rgb(lch.bg))).toBeGreaterThanOrEqual(12)
        expect(contrast(rgb(lch.accent), rgb(lch.s1))).toBeGreaterThanOrEqual(3)
        expect(contrast(rgb(lch.accent), rgb(lch.ink))).toBeGreaterThanOrEqual(4.5)
      })
      it(`contrast: ${surface} × ${name}`, () => {
        const { lch } = themeFrom(cover, surface)
        expect(contrast(rgb(lch.t3), rgb(lch.s1))).toBeGreaterThanOrEqual(4.5)
        expect(contrast(rgb(lch.text), rgb(lch.bg))).toBeGreaterThanOrEqual(12)
        expect(contrast(rgb(lch.accent), rgb(lch.s1))).toBeGreaterThanOrEqual(3)
        expect(contrast(rgb(lch.accent), rgb(lch.ink))).toBeGreaterThanOrEqual(4.5)
      })
    }
  }
})
