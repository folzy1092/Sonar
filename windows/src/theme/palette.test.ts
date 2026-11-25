import { describe, expect, it } from 'vitest'
import { contrast, hslToRgb, inkFor, kmeans, oklchToRgb, pickAccent, pickBase, rgbToHsl, rgbToOklch, SURFACES, themeFrom, type Lch, type RGB, type Surface } from './palette'

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

describe('подкраска интерфейса (appearance.tint)', () => {
  const rgb = (x: Lch) => oklchToRgb(x)
  const teal: RGB = [46, 196, 182]
  const blue: RGB = [28, 60, 150]

  it('основной цвет — самый большой цветной кластер, не самый яркий', () => {
    const px = image([[70, 80, 110, 600], [240, 30, 40, 150], [5, 5, 5, 130]])
    expect(pickBase(px)![2]).toBeGreaterThan(100)
    expect(pickAccent(px)![0]).toBeGreaterThan(200)
    expect(pickBase(image([[5, 5, 5, 100], [128, 128, 128, 100]]))).toBeNull()
  })

  it('«Спокойно» — наведение белое и заглушка серая, как раньше', () => {
    const t = themeFrom(teal, 'classic', false, null, { tint: 'calm' })
    expect(t.vars['--hover']).toBe('oklch(1.000 0.000 0 / 0.07)')
    expect(t.vars['--ph-wash']).toBe('transparent')
  })

  it('«Весь интерфейс» красит наведение, подложку и заглушку в оттенок', () => {
    const t = themeFrom(teal, 'classic', false, null, { tint: 'full' })
    expect(t.vars['--hover']).toMatch(/oklch\(0\.900 0\.0[1-9]\d* \d+ \/ 0\.07\)/)
    expect(t.vars['--ph-wash']).not.toBe('transparent')
  })

  it('монохром и Монолит не подкрашивают наведение', () => {
    expect(themeFrom(null, 'classic', false, null, { tint: 'full' }).vars['--ph-wash']).toBe('transparent')
    expect(themeFrom(teal, 'monolith', false, null, { tint: 'full' }).vars['--hover']).toContain('0.000 0')
  })

  it('«Два цвета»: фон — оттенок основного цвета, акцент — свой', () => {
    const t = themeFrom([240, 30, 40], 'classic', false, null, { tint: 'duo', tone: blue })
    expect(Math.abs(t.lch.bg.h - rgbToOklch(blue).h)).toBeLessThan(2)
    expect(Math.abs(t.lch.accent.h - rgbToOklch([240, 30, 40]).h)).toBeLessThan(2)
    // без «Два цвета» тон игнорируется
    const f = themeFrom([240, 30, 40], 'classic', false, null, { tint: 'full', tone: blue })
    expect(Math.abs(f.lch.bg.h - rgbToOklch([240, 30, 40]).h)).toBeLessThan(2)
  })

  const TONES: RGB[] = [blue, [250, 222, 32], [20, 120, 40], [255, 24, 178]]
  for (const tint of ['full', 'duo'] as const) {
    for (const surface of Object.keys(SURFACES) as Surface[]) {
      for (const light of [false, true]) {
        it(`контраст держится: ${tint} × ${surface}${light ? ' (светлая)' : ''}`, () => {
          for (const src of [teal, [230, 120, 30], [120, 20, 30]] as RGB[]) {
            for (const tone of TONES) {
              const { lch } = themeFrom(src, surface, light, null, { tint, tone })
              expect(contrast(rgb(lch.t3), rgb(lch.s1))).toBeGreaterThanOrEqual(4.5)
              expect(contrast(rgb(lch.t2), rgb(lch.s3))).toBeGreaterThanOrEqual(4.5)
              expect(contrast(rgb(lch.text), rgb(lch.bg))).toBeGreaterThanOrEqual(12)
              expect(contrast(rgb(lch.accent), rgb(lch.s1))).toBeGreaterThanOrEqual(3)
            }
          }
        })
      }
    }
  }

  describe('слово-акцент Главной (--accent-word)', () => {
    const SRC: (RGB | null)[] = [null, [128, 128, 128], teal, [230, 120, 30], [120, 20, 30], [255, 24, 178]]
    for (const surface of Object.keys(SURFACES) as Surface[]) {
      for (const light of [false, true]) {
        it(`не белое и читается: ${surface}${light ? ' (светлая)' : ''}`, () => {
          for (const src of SRC) {
            for (const tint of ['calm', 'full', 'duo'] as const) {
              const { lch } = themeFrom(src, surface, light, { strength: 'strong', lightness: light ? 0.2 : 0.95 }, { tint, tone: blue })
              expect(contrast(rgb(lch.word), rgb(lch.bg))).toBeGreaterThanOrEqual(7)
              // заметно отличается от текста вокруг: цветом, а не только светлотой
              expect(lch.word.c).toBeGreaterThanOrEqual(0.04)
              expect(Math.abs(lch.word.l - lch.text.l)).toBeGreaterThanOrEqual(0.08)
            }
          }
        })
      }
    }
    it('у серой обложки — тёплый бежевый, у цветной — оттенок обложки', () => {
      const grey = themeFrom(null, 'classic')
      expect(grey.lch.word.h).toBeGreaterThan(50)
      expect(grey.lch.word.h).toBeLessThan(90)
      expect(grey.vars['--accent-word']).toMatch(/^oklch/)
      const red = themeFrom([240, 30, 40], 'classic')
      expect(Math.abs(red.lch.word.h - rgbToOklch([240, 30, 40]).h)).toBeLessThan(3)
    })
  })
})
