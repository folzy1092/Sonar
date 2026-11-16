// Цвет темы из обложки (SPEC §4.4): 64×64 пикселя → k-means (k = 5) → кластер с лучшим
// `насыщенность × √доля`, почти чёрные и белые не берём. Фон — тот же оттенок, затемнённый.
// Текст на акценте — чёрный или белый, что контрастнее.

export type RGB = [number, number, number]

export function rgbToHsl([r, g, b]: RGB): [number, number, number] {
  r /= 255
  g /= 255
  b /= 255
  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  const l = (max + min) / 2
  if (max === min) return [0, 0, l]
  const d = max - min
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
  let h: number
  if (max === r) h = (g - b) / d + (g < b ? 6 : 0)
  else if (max === g) h = (b - r) / d + 2
  else h = (r - g) / d + 4
  return [h / 6, s, l]
}

export function hslToRgb([h, s, l]: [number, number, number]): RGB {
  if (s === 0) {
    const v = Math.round(l * 255)
    return [v, v, v]
  }
  const hue = (p: number, q: number, t: number) => {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s
  const p = 2 * l - q
  return [hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3)].map((v) => Math.round(v * 255)) as RGB
}

function luminance([r, g, b]: RGB): number {
  const c = [r, g, b].map((v) => {
    v /= 255
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
  })
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}

export function contrast(a: RGB, b: RGB): number {
  const [x, y] = [luminance(a), luminance(b)].sort((p, q) => q - p)
  return (x + 0.05) / (y + 0.05)
}

/** Текст на цвете: чёрный или белый — что контрастнее. */
export function inkFor(c: RGB): RGB {
  return contrast(c, [10, 10, 11]) >= contrast(c, [255, 255, 255]) ? [10, 10, 11] : [255, 255, 255]
}

/** k-means по пикселям RGBA; возвращает центры и доли. Детерминирован (центры — по равным шагам). */
export function kmeans(px: Uint8ClampedArray | number[], k = 5, iters = 8): { color: RGB; share: number }[] {
  const pts: RGB[] = []
  for (let i = 0; i + 3 < px.length; i += 4) if (px[i + 3] > 128) pts.push([px[i], px[i + 1], px[i + 2]])
  if (!pts.length) return []
  const step = Math.max(1, Math.floor(pts.length / k))
  let centers: RGB[] = Array.from({ length: Math.min(k, pts.length) }, (_, i) => [...pts[Math.min(pts.length - 1, i * step)]] as RGB)
  let assign = new Array<number>(pts.length).fill(0)
  for (let it = 0; it < iters; it++) {
    assign = pts.map((p) => {
      let best = 0
      let bd = Infinity
      centers.forEach((c, j) => {
        const d = (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 + (p[2] - c[2]) ** 2
        if (d < bd) {
          bd = d
          best = j
        }
      })
      return best
    })
    centers = centers.map((c, j) => {
      let n = 0
      const sum = [0, 0, 0]
      pts.forEach((p, i) => {
        if (assign[i] !== j) return
        n++
        sum[0] += p[0]
        sum[1] += p[1]
        sum[2] += p[2]
      })
      return n ? (sum.map((v) => Math.round(v / n)) as RGB) : c
    })
  }
  const counts = centers.map((_, j) => assign.filter((a) => a === j).length)
  return centers.map((color, j) => ({ color, share: counts[j] / pts.length })).filter((c) => c.share > 0)
}

/** Акцент обложки или null (картинка почти серая / чёрно-белая). */
export function pickAccent(px: Uint8ClampedArray | number[]): RGB | null {
  let best: RGB | null = null
  let bestScore = 0
  for (const { color, share } of kmeans(px)) {
    const [, s, l] = rgbToHsl(color)
    if (l < 0.1 || l > 0.92 || s < 0.15) continue
    const score = s * Math.sqrt(share)
    if (score > bestScore) {
      bestScore = score
      best = color
    }
  }
  return best
}

/** Цвета темы из акцента: акцент поярче для тёмной темы, фон (L≈12 %), текст на акценте. */
export function themeFrom(c: RGB): { accent: RGB; ink: RGB; bg: RGB; base: RGB; surfaces: [RGB, RGB, RGB, RGB] } {
  const [h, s, l] = rgbToHsl(c)
  const accent = hslToRgb([h, Math.min(1, Math.max(s, 0.45)), Math.min(0.72, Math.max(l, 0.55))])
  const bg = hslToRgb([h, Math.min(s, 0.55), 0.12])
  // фон окна — тот же оттенок, матовый и темнее обложки (решение владельца 2026-11-16); поверхности —
  // ступенями светлее в том же оттенке, чтобы края карточек и всплывашек читались чётко
  const sat = Math.min(s, 0.38)
  const base = hslToRgb([h, sat, 0.05])
  const surfaces = [0.07, 0.095, 0.125, 0.155].map((li) => hslToRgb([h, Math.min(sat, 0.3), li])) as [RGB, RGB, RGB, RGB]
  return { accent, ink: inkFor(accent), bg, base, surfaces }
}

export const css = ([r, g, b]: RGB, a = 1) => (a === 1 ? `rgb(${r} ${g} ${b})` : `rgb(${r} ${g} ${b} / ${a})`)
