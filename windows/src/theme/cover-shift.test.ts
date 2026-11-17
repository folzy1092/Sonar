import { describe, expect, it } from 'vitest'
import {
  contrast,
  COVER_STRENGTHS,
  coverBias,
  coverLightness,
  keepsContrast,
  MAX_COVER_SHIFT,
  oklchToRgb,
  PIVOT_L,
  readable,
  rgbToOklch,
  shiftLightness,
  SURFACES,
  themeFrom,
  type CoverStrength,
  type Lch,
  type RGB,
  type Surface,
} from './palette'

// Тема под обложку, этап 0 п. 11: поверхности уходят по светлоте за обложкой, текст читается.
const COVERS: Record<string, RGB> = {
  'тёмно-синяя': [28, 36, 104],
  'кислотно-розовая': [255, 24, 178],
  'почти чёрная': [26, 22, 20],
  жёлтая: [250, 222, 32],
  белая: [246, 246, 244],
  серая: [128, 128, 128],
}
const SURFACE_LIST = Object.keys(SURFACES) as Surface[]
const rgb = (x: Lch) => oklchToRgb(x)
const DARK_COVER = 0.15
const LIGHT_COVER = 0.95
const MID_COVER = rgbToOklch([128, 128, 128]).l

/** Относительный сдвиг: в тёмной теме — от нуля, в светлой — от белого. */
function relative(before: number, after: number, light: boolean): number {
  return light ? (1 - after - (1 - before)) / (1 - before) : (after - before) / before
}

function pixels(color: RGB, n = 64): number[] {
  return Array.from({ length: n }, () => [...color, 255]).flat()
}

describe('cover lightness', () => {
  it('measures mean oklch lightness of opaque pixels', () => {
    expect(coverLightness(pixels([0, 0, 0]))).toBeCloseTo(0, 3)
    expect(coverLightness(pixels([255, 255, 255]))).toBeCloseTo(1, 3)
    const half = [...pixels([0, 0, 0], 10), ...pixels([255, 255, 255], 10)]
    expect(coverLightness(half)).toBeCloseTo(0.5, 2)
  })

  it('ignores transparent pixels and falls back to the middle for empty images', () => {
    const px = [...pixels([255, 255, 255], 4), 0, 0, 0, 0, 0, 0, 0, 0]
    expect(coverLightness(px)).toBeCloseTo(1, 3)
    expect(coverLightness([])).toBeCloseTo(MID_COVER, 1)
  })
})

describe('cover bias', () => {
  it('dark cover is negative, light cover positive, mid grey about zero', () => {
    expect(coverBias({ strength: 'medium', lightness: DARK_COVER })).toBeLessThan(0)
    expect(coverBias({ strength: 'medium', lightness: LIGHT_COVER })).toBeGreaterThan(0)
    expect(Math.abs(coverBias({ strength: 'medium', lightness: MID_COVER }))).toBeLessThan(0.005)
  })

  it('grows with strength and never exceeds 20 %', () => {
    const at = (s: CoverStrength) => Math.abs(coverBias({ strength: s, lightness: 0 }))
    expect(at('weak')).toBeLessThan(at('medium'))
    expect(at('medium')).toBeLessThan(at('strong'))
    expect(at('strong')).toBeLessThanOrEqual(MAX_COVER_SHIFT)
    expect(at('medium')).toBeGreaterThanOrEqual(0.1)
    expect(at('medium')).toBeLessThanOrEqual(0.15)
  })

  it('unknown strength falls back to medium', () => {
    const odd = coverBias({ strength: 'loud' as CoverStrength, lightness: 0 })
    expect(odd).toBe(coverBias({ strength: 'medium', lightness: 0 }))
  })
})

describe('shift lightness', () => {
  it('moves dark theme from zero and light theme from white', () => {
    expect(shiftLightness(0.2, -0.1, false)).toBeCloseTo(0.18, 5)
    expect(shiftLightness(0.2, 0.1, false)).toBeCloseTo(0.22, 5)
    expect(shiftLightness(0.9, 0.1, true)).toBeCloseTo(0.91, 5)
    expect(shiftLightness(0.9, -0.1, true)).toBeCloseTo(0.89, 5)
    expect(shiftLightness(0.5, 0, true)).toBe(0.5)
  })

  it('never reaches black or white', () => {
    expect(shiftLightness(0.05, -0.2, false)).toBeGreaterThan(0.07)
    expect(shiftLightness(0.999, 0.2, true)).toBeLessThan(0.995)
  })
})

describe('theme follows the cover', () => {
  it('without a cover shift the theme is unchanged', () => {
    for (const surface of SURFACE_LIST) {
      const a = themeFrom([28, 36, 104], surface)
      expect(a.shift).toBe(0)
      expect(themeFrom([28, 36, 104], surface, false, null).vars).toEqual(a.vars)
    }
  })

  for (const light of [false, true]) {
    const mode = light ? 'светлая' : 'тёмная'
    it(`dark cover makes surfaces darker, light cover lighter (${mode})`, () => {
      for (const surface of SURFACE_LIST) {
        const base = themeFrom([28, 36, 104], surface, light).lch
        const dark = themeFrom([28, 36, 104], surface, light, { strength: 'medium', lightness: DARK_COVER }).lch
        const bright = themeFrom([28, 36, 104], surface, light, { strength: 'medium', lightness: LIGHT_COVER }).lch
        for (const key of ['bg', 's1', 's2', 's3'] as const) {
          expect(dark[key].l).toBeLessThan(base[key].l)
          expect(bright[key].l).toBeGreaterThan(base[key].l)
        }
      }
    })

    it(`shift stays within 20 % and medium is 10–15 % (${mode})`, () => {
      for (const surface of SURFACE_LIST) {
        for (const strength of COVER_STRENGTHS) {
          for (const lightness of [0, DARK_COVER, LIGHT_COVER, 1]) {
            const base = themeFrom([255, 24, 178], surface, light).lch
            const t = themeFrom([255, 24, 178], surface, light, { strength, lightness })
            expect(Math.abs(t.shift)).toBeLessThanOrEqual(MAX_COVER_SHIFT)
            const r = Math.abs(relative(base.s2.l, t.lch.s2.l, light))
            expect(r).toBeLessThanOrEqual(MAX_COVER_SHIFT + 1e-6)
          }
        }
        const base = themeFrom([28, 36, 104], surface, light).lch.s2.l
        const med = themeFrom([28, 36, 104], surface, light, { strength: 'medium', lightness: 0 }).lch.s2.l
        const r = Math.abs(relative(base, med, light))
        expect(r).toBeGreaterThanOrEqual(0.1 - 1e-6)
        expect(r).toBeLessThanOrEqual(0.15 + 1e-6)
      }
    })

    it(`surfaces keep a slight cover hue, never plain grey (${mode})`, () => {
      for (const surface of SURFACE_LIST) {
        const t = themeFrom([28, 36, 104], surface, light, { strength: 'medium', lightness: DARK_COVER })
        for (const key of ['bg', 's1', 's2', 's3'] as const) expect(t.lch[key].c).toBeGreaterThan(0.003)
        expect(t.lch.bg.l).toBeGreaterThan(0.07)
      }
      // серая обложка остаётся серой — оттенка у неё нет
      const grey = themeFrom([128, 128, 128], 'echo', light, { strength: 'strong', lightness: DARK_COVER })
      expect(grey.lch.s1.c).toBe(0)
    })

    it(`stronger setting tints surfaces more (${mode})`, () => {
      const at = (strength: CoverStrength) => themeFrom([28, 36, 104], 'echo', light, { strength, lightness: MID_COVER }).lch.s1.c
      expect(at('weak')).toBeLessThan(at('medium'))
      expect(at('medium')).toBeLessThanOrEqual(at('strong'))
    })

    for (const surface of SURFACE_LIST) {
      for (const [name, cover] of Object.entries(COVERS)) {
        it(`AA contrast with every strength (${mode}): ${surface} × ${name}`, () => {
          for (const strength of COVER_STRENGTHS) {
            for (const lightness of [0, DARK_COVER, 0.5, LIGHT_COVER, 1]) {
              const t = themeFrom(cover, surface, light, { strength, lightness })
              const { lch } = t
              expect(readable(t)).toBe(true)
              expect(contrast(rgb(lch.t3), rgb(lch.s1))).toBeGreaterThanOrEqual(4.5)
              expect(contrast(rgb(lch.t2), rgb(lch.s3))).toBeGreaterThanOrEqual(4.5)
              expect(contrast(rgb(lch.text), rgb(lch.bg))).toBeGreaterThanOrEqual(12)
              expect(contrast(rgb(lch.accent), rgb(lch.s1))).toBeGreaterThanOrEqual(3)
              expect(contrast(rgb(lch.accent), rgb(lch.ink))).toBeGreaterThanOrEqual(4.5)
            }
          }
        })
      }
    }
  }

  it('contrast guard weakens the shift instead of breaking AA', () => {
    // самая светлая обложка × сильно: где без защиты текст просел бы — сдвиг меньше заданного
    for (const surface of SURFACE_LIST) {
      for (const light of [false, true]) {
        const t = themeFrom([255, 24, 178], surface, light, { strength: 'strong', lightness: 1 })
        expect(readable(t)).toBe(true)
        expect(t.shift).toBeGreaterThanOrEqual(0)
        expect(t.shift).toBeLessThanOrEqual(MAX_COVER_SHIFT)
      }
    }
  })

  // обложки, где сама тема без сдвига не держит пару «акцент / текст на акценте» (светлые темы)
  const WIDE_COVERS: RGB[] = [[40, 180, 90], [30, 120, 220], [220, 30, 40], [250, 190, 0], [200, 60, 200]]

  it('shift never makes any contrast pair worse than AA or than the theme without shift', () => {
    for (const surface of SURFACE_LIST) {
      for (const light of [false, true]) {
        for (const cover of WIDE_COVERS) {
          for (const strength of COVER_STRENGTHS) {
            const base = themeFrom(cover, surface, light, { strength, lightness: PIVOT_L })
            expect(base.shift).toBe(0)
            for (const lightness of [0, DARK_COVER, 0.5, 0.8, LIGHT_COVER, 1]) {
              const t = themeFrom(cover, surface, light, { strength, lightness })
              expect(keepsContrast(t, base)).toBe(true)
              expect(Math.abs(t.shift)).toBeLessThanOrEqual(MAX_COVER_SHIFT)
            }
          }
        }
      }
    }
  })

  it('a pair the shift does not touch does not switch the shift off', () => {
    // зелёная обложка, светлая «Грань»: акцент / ink ниже 4.5 и без сдвига — поверхности всё равно идут за обложкой
    const base = themeFrom([40, 180, 90], 'edge', true, { strength: 'medium', lightness: PIVOT_L })
    expect(readable(base)).toBe(false)
    expect(themeFrom([40, 180, 90], 'edge', true, { strength: 'medium', lightness: DARK_COVER }).shift).toBeLessThan(0)
  })
})
