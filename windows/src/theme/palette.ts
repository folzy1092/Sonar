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

/**
 * Основной цвет обложки для «Двух цветов» (`appearance.tint = duo`): самый большой цветной кластер,
 * а не самый яркий. Синяя обложка с красной надписью — фон синеватый, акцент красный. Все кластеры
 * серые — null (поверхности тогда берут оттенок акцента).
 */
export function pickBase(px: Uint8ClampedArray | number[]): RGB | null {
  let best: RGB | null = null
  let bestShare = 0
  for (const { color, share } of kmeans(px)) {
    const [, s, l] = rgbToHsl(color)
    if (l < 0.06 || l > 0.94 || s < 0.12) continue
    if (share > bestShare) {
      bestShare = share
      best = color
    }
  }
  return best
}

// ---- OKLCH (reference/design/STYLE_PROMPT.md §1) ----
// В HSL синий и розовый с одной «светлотой» выглядят разной яркости; в OKLCH светлота L — та, что
// видит глаз. Из обложки берём оттенок h и насыщенность c, дальше всё считаем по формулам поверхности.

export interface Lch {
  l: number
  c: number
  h: number
}

const toLin = (v: number) => {
  v /= 255
  return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
}
const fromLin = (v: number) => (v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055) * 255

export function rgbToOklch([r8, g8, b8]: RGB): Lch {
  const [r, g, b] = [toLin(r8), toLin(g8), toLin(b8)]
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
  const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
  const h = (Math.atan2(B, A) * 180) / Math.PI
  return { l: L, c: Math.hypot(A, B), h: h < 0 ? h + 360 : h }
}

/** OKLCH → линейные sRGB 0…1 (за пределами 0…1 — цвет вне sRGB). */
function oklchToLinear({ l: L, c, h }: Lch): [number, number, number] {
  const A = c * Math.cos((h * Math.PI) / 180)
  const B = c * Math.sin((h * Math.PI) / 180)
  const l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3
  const m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3
  const s = (L - 0.0894841775 * A - 1.291485548 * B) ** 3
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ]
}

const inGamut = (x: Lch) => oklchToLinear(x).every((v) => v >= -1e-4 && v <= 1 + 1e-4)

/** Вписать в sRGB: та же светлота и оттенок, насыщенность меньше (как гамут-маппинг CSS Color 4). */
export function fitGamut(x: Lch): Lch {
  if (inGamut(x)) return x
  let lo = 0
  let hi = x.c
  for (let i = 0; i < 18; i++) {
    const mid = (lo + hi) / 2
    if (inGamut({ ...x, c: mid })) lo = mid
    else hi = mid
  }
  return { ...x, c: lo }
}

export function oklchToRgb(x: Lch): RGB {
  return oklchToLinear(fitGamut(x)).map((v) => Math.round(Math.max(0, Math.min(255, fromLin(Math.max(0, Math.min(1, v))))))) as RGB
}

/** CSS-строка `oklch(L C h / a)`; цвет уже вписан в sRGB. */
export function oklch(x: Lch, a = 1): string {
  const f = fitGamut(x)
  return `oklch(${f.l.toFixed(3)} ${f.c.toFixed(3)} ${Math.round(f.h)}${a === 1 ? '' : ` / ${a}`})`
}

/** Формулы поверхности: значения — вкладки reference/design/sonar-directions.html (объект `CFG`). */
export interface SurfaceFormula {
  bgL: number
  bgC: number
  bgMax: number
  sL: [number, number, number]
  sC: number
  sMax: number
  bdL: number
  bdC: number
  bdMax: number
  txL: number
  t2L: number
  t3L: number
  accL: number
  accMax: number
  /** Прозрачность мягкого акцента (`--accent-soft`). */
  softA: number
  /** Текст без подкраски (Монолит: цвет обложки — только свечение и прогресс). */
  grayText?: boolean
}

export type Surface = 'classic' | 'echo' | 'signal' | 'edge' | 'tactile' | 'monolith'

export const SURFACES: Record<Surface, SurfaceFormula> = {
  // «Классика» (design/classic/HANDOFF.md): тёплый графит с лёгким оттенком обложки, без рамок у карточек
  classic: { bgL: 0.165, bgC: 0.42, bgMax: 0.035, sL: [0.205, 0.25, 0.29], sC: 0.42, sMax: 0.04, bdL: 0.27, bdC: 0.42, bdMax: 0.035, txL: 0.97, t2L: 0.76, t3L: 0.66, accL: 0.8, accMax: 0.2, softA: 0.16 },
  echo: { bgL: 0.135, bgC: 0.22, bgMax: 0.028, sL: [0.178, 0.218, 0.262], sC: 0.28, sMax: 0.034, bdL: 0.31, bdC: 0.32, bdMax: 0.05, txL: 0.97, t2L: 0.8, t3L: 0.65, accL: 0.79, accMax: 0.19, softA: 0.22 },
  signal: { bgL: 0.15, bgC: 0.4, bgMax: 0.06, sL: [0.195, 0.24, 0.285], sC: 0.45, sMax: 0.065, bdL: 0.3, bdC: 0.45, bdMax: 0.07, txL: 0.97, t2L: 0.82, t3L: 0.68, accL: 0.8, accMax: 0.2, softA: 0.18 },
  edge: { bgL: 0.12, bgC: 0.2, bgMax: 0.025, sL: [0.165, 0.205, 0.25], sC: 0.25, sMax: 0.03, bdL: 0.36, bdC: 0.35, bdMax: 0.06, txL: 0.975, t2L: 0.8, t3L: 0.65, accL: 0.8, accMax: 0.2, softA: 0.16 },
  tactile: { bgL: 0.17, bgC: 0.15, bgMax: 0.022, sL: [0.215, 0.255, 0.305], sC: 0.18, sMax: 0.026, bdL: 0.34, bdC: 0.2, bdMax: 0.03, txL: 0.965, t2L: 0.8, t3L: 0.68, accL: 0.82, accMax: 0.2, softA: 0.35 },
  monolith: { bgL: 0.1, bgC: 0, bgMax: 0, sL: [0.145, 0.185, 0.23], sC: 0, sMax: 0, bdL: 0.27, bdC: 0, bdMax: 0, txL: 0.98, t2L: 0.76, t3L: 0.62, accL: 0.78, accMax: 0.2, softA: 0.2, grayText: true },
}

/**
 * Особенности поверхности, которые не цвет: рамка карточек, блик, выпуклые кнопки и утопленные
 * дорожки, фон мини-плеера, тень обложки. Компоненты берут их переменными (по умолчанию —
 * tokens.css), поэтому смена поверхности не трогает вёрстку.
 * - Классика: у карточек нет рамки, обложка — с мягкой тенью снизу;
 * - Сигнал: у карточек и мини-плеера нет рамки, мини-плеер — поверхность 2;
 * - Грань: у каждой поверхности блик сверху;
 * - Тактиль: кнопки выпуклые (при нажатии −2 px), дорожки и выбранное утоплены;
 * - Монолит: цвет обложки — только свечение за обложкой (blur 28 px) и прогресс.
 */
export const SURFACE_DECOR: Record<Surface, Record<string, string>> = {
  classic: { '--card-line': 'transparent', '--cover-glow': '0 22px 48px -18px oklch(0 0 0 / 0.55), 0 2px 8px oklch(0 0 0 / 0.2)' },
  echo: {},
  signal: { '--card-line': 'transparent', '--mini-bg': 'var(--surface-2)' },
  edge: { '--sheen': 'inset 0 1px 0 oklch(1 0 0 / 0.07)' },
  tactile: {
    '--key': '0 2px 0 oklch(0 0 0 / 0.55), 0 3px 6px oklch(0 0 0 / 0.25), inset 0 1px 0 oklch(1 0 0 / 0.08)',
    '--key-down': 'inset 0 1px 2px oklch(0 0 0 / 0.5)',
    '--key-shift': '2px',
    '--well': 'inset 0 2px 4px oklch(0 0 0 / 0.45)',
  },
  monolith: { '--cover-glow': '0 0 28px var(--glow)', '--mono-glow': '0 0 28px var(--glow)' },
}

/** Все переменные особенностей — чтобы при смене поверхности снимать прошлые. */
export const DECOR_VARS = ['--card-line', '--mini-bg', '--sheen', '--key', '--key-down', '--key-shift', '--well', '--cover-glow', '--mono-glow']

/**
 * Светлая тема (Интерфейс → Вид → Тема): те же поверхности, светлые формулы — фон ≈ .97–.985,
 * поверхности темнее фона, текст .18 / .40 / .52, акцент темнее (≥ 3:1 к поверхности), текст на
 * акценте — светлый. Особенности поверхностей (рамки, блики, выпуклость) — те же.
 */
export const SURFACES_LIGHT: Record<Surface, SurfaceFormula> = {
  classic: { bgL: 0.985, bgC: 0.17, bgMax: 0.012, sL: [0.952, 0.915, 0.88], sC: 0.21, sMax: 0.02, bdL: 0.87, bdC: 0.2, bdMax: 0.02, txL: 0.19, t2L: 0.42, t3L: 0.5, accL: 0.5, accMax: 0.2, softA: 0.14 },
  echo: { bgL: 0.975, bgC: 0.1, bgMax: 0.012, sL: [0.955, 0.93, 0.905], sC: 0.12, sMax: 0.016, bdL: 0.86, bdC: 0.15, bdMax: 0.02, txL: 0.18, t2L: 0.4, t3L: 0.52, accL: 0.55, accMax: 0.18, softA: 0.16 },
  signal: { bgL: 0.965, bgC: 0.2, bgMax: 0.03, sL: [0.945, 0.915, 0.885], sC: 0.22, sMax: 0.032, bdL: 0.86, bdC: 0.25, bdMax: 0.035, txL: 0.18, t2L: 0.4, t3L: 0.52, accL: 0.55, accMax: 0.19, softA: 0.14 },
  edge: { bgL: 0.985, bgC: 0.08, bgMax: 0.01, sL: [0.965, 0.94, 0.91], sC: 0.1, sMax: 0.012, bdL: 0.82, bdC: 0.15, bdMax: 0.02, txL: 0.17, t2L: 0.4, t3L: 0.52, accL: 0.55, accMax: 0.19, softA: 0.14 },
  tactile: { bgL: 0.955, bgC: 0.08, bgMax: 0.01, sL: [0.935, 0.91, 0.88], sC: 0.1, sMax: 0.012, bdL: 0.84, bdC: 0.1, bdMax: 0.014, txL: 0.18, t2L: 0.4, t3L: 0.5, accL: 0.54, accMax: 0.18, softA: 0.22 },
  monolith: { bgL: 0.985, bgC: 0, bgMax: 0, sL: [0.965, 0.94, 0.91], sC: 0, sMax: 0, bdL: 0.88, bdC: 0, bdMax: 0, txL: 0.16, t2L: 0.42, t3L: 0.52, accL: 0.54, accMax: 0.19, softA: 0.14, grayText: true },
}

/** Ниже этой насыщенности обложка считается монохромной. */
export const MONO_C = 0.03

export type TokenName = 'bg' | 's0' | 's1' | 's2' | 's3' | 'border' | 'text' | 't2' | 't3' | 'accent' | 'ink' | 'track'

export interface ThemeTokens {
  /** Цвета в OKLCH (уже вписаны в sRGB) — для проверки контраста и образцов. */
  lch: Record<TokenName, Lch>
  mono: boolean
  /** CSS-переменные для `:root`. */
  vars: Record<string, string>
  /** Для образцов тем и оттенка страницы артиста: акцент, фон и текст на акценте в RGB. */
  accent: RGB
  bg: RGB
  ink: RGB
  /** Сдвиг светлоты поверхностей под обложку, который реально применён (−0.2…0.2; 0 — без сдвига). */
  shift: number
}

/**
 * Сила темы под обложку (Интерфейс → Тема, `appearance.cover_strength`): насколько поверхности
 * уходят по светлоте за обложкой (тёмная — темнее, светлая — светлее), во сколько раз сильнее
 * их подкраска и минимальная насыщенность оттенка, чтобы поверхность не стала серой.
 */
export type CoverStrength = 'weak' | 'medium' | 'strong'
export const COVER_STRENGTHS: CoverStrength[] = ['weak', 'medium', 'strong']
export const COVER_STRENGTH: Record<CoverStrength, { shift: number; chroma: number; hue: number }> = {
  weak: { shift: 0.08, chroma: 0.8, hue: 0.004 },
  medium: { shift: 0.14, chroma: 1, hue: 0.008 },
  strong: { shift: 0.2, chroma: 1.3, hue: 0.012 },
}
/**
 * Подкраска интерфейса (Интерфейс → Вид → «Подкраска», `appearance.tint`):
 * - `calm` — как было до 2026-11-25: лёгкий оттенок фона, наведение и подложки белые, заглушки серые;
 * - `full` — весь интерфейс: наведение, нажатие, подложки, вторичный текст и заглушки обложек — в оттенке;
 * - `duo` — как `full`, но фон и поверхности берут основной цвет обложки, а акцент — самый яркий
 *   (у готовой темы второго цвета нет — как `full`).
 */
export type Tint = 'calm' | 'full' | 'duo'
export const TINTS: Tint[] = ['calm', 'full', 'duo']

/** Сдвиг светлоты не больше 20 % — и при любом раскладе ниже порога контраста не опускаемся. */
export const MAX_COVER_SHIFT = 0.2

/** Обложка для сдвига: сила из настроек и средняя светлота OKLCH (0…1) её пикселей. */
export interface CoverShift {
  strength: CoverStrength
  lightness: number
}

/**
 * Средняя светлота обложки — середина и разброс шкалы: L ≤ .35 — «тёмная», L ≥ .85 — «светлая»
 * (полный сдвиг). Между ними кривая — корень: обычная обложка (L .4–.8) уже даёт заметные 10–15 %
 * на «Средне», а у самой середины (серая, L .6) сдвиг плавно сходит к нулю.
 */
export const PIVOT_L = 0.6
const SPAN_L = 0.25
const BIAS_CURVE = 0.5
/** Тёмная тема не уходит в чёрный, светлая — в белый. */
const DARK_FLOOR = 0.075
const LIGHT_CEIL = 0.992
/** Если контраст текста просел — сдвиг ослабляем шагами, пока не пройдёт. */
const GUARD_STEP = 0.7
const GUARD_TRIES = 8

/** Средняя светлота OKLCH непрозрачных пикселей (RGBA подряд); пустая картинка — середина шкалы. */
export function coverLightness(px: Uint8ClampedArray | number[]): number {
  let sum = 0
  let n = 0
  for (let i = 0; i + 3 < px.length; i += 4) {
    if (px[i + 3] < 128) continue
    sum += rgbToOklch([px[i], px[i + 1], px[i + 2]]).l
    n++
  }
  return n ? sum / n : PIVOT_L
}

/** Насколько и куда сдвигать (−shift…shift): тёмная обложка — минус, светлая — плюс. */
export function coverBias(shift: CoverShift): number {
  const k = COVER_STRENGTH[shift.strength] ?? COVER_STRENGTH.medium
  const d = Math.max(-1, Math.min(1, (shift.lightness - PIVOT_L) / SPAN_L))
  const bias = Math.sign(d) * Math.abs(d) ** BIAS_CURVE
  return Math.max(-MAX_COVER_SHIFT, Math.min(MAX_COVER_SHIFT, bias * k.shift))
}

/** Светлота поверхности со сдвигом f: в тёмной теме — от нуля, в светлой — от белого. */
export function shiftLightness(l: number, f: number, light: boolean): number {
  if (!f) return l
  return light ? Math.min(LIGHT_CEIL, 1 - (1 - l) * (1 - f)) : Math.max(DARK_FLOOR, l * (1 + f))
}

/** Пары цветов и порог контраста WCAG, которые держит тема (как в тестах палитры). */
const CONTRAST_PAIRS: readonly (readonly [TokenName, TokenName, number])[] = [
  ['text', 'bg', 12],
  ['t3', 'bg', 4.5],
  ['t3', 's1', 4.5],
  ['t2', 's3', 4.5],
  ['accent', 's1', 3],
  ['accent', 'ink', 4.5],
]
/** Погрешность округления sRGB при сравнении контраста до и после сдвига. */
const CONTRAST_EPS = 1e-6

function contrasts(t: ThemeTokens): number[] {
  return CONTRAST_PAIRS.map(([a, b]) => contrast(oklchToRgb(t.lch[a]), oklchToRgb(t.lch[b])))
}

/** Текст и акцент читаются на всех поверхностях (WCAG AA). */
export function readable(t: ThemeTokens): boolean {
  return contrasts(t).every((c, i) => c >= CONTRAST_PAIRS[i][2])
}

/**
 * Сдвиг под обложку не портит чтение: каждая пара не ниже порога AA — а где тема и без сдвига
 * ниже порога (например, акцент на светлой теме), не ниже, чем была. Иначе такая обложка
 * совсем отключала бы сдвиг из-за пары, которую он даже не трогает.
 */
export function keepsContrast(t: ThemeTokens, base: ThemeTokens): boolean {
  const before = contrasts(base)
  return contrasts(t).every((c, i) => c >= Math.min(CONTRAST_PAIRS[i][2], before[i]) - CONTRAST_EPS)
}

interface Shade {
  /** Сдвиг светлоты поверхностей. */
  f: number
  /** Множитель подкраски поверхностей. */
  chroma: number
  /** Нижняя граница насыщенности поверхностей — лёгкий оттенок обложки. */
  hue: number
}
const NO_SHADE: Shade = { f: 0, chroma: 1, hue: 0 }

/**
 * Токены темы: исходный цвет (обложка / готовая тема / null — монохром) × формулы поверхности.
 * `cover` — тема идёт за обложкой: поверхности сдвигаются по светлоте (10–15 % по умолчанию, до 20 %)
 * и чуть сильнее подкрашиваются её оттенком; текст остаётся читаемым (сдвиг ослабляется до AA).
 */
export interface TintOptions {
  tint?: Tint
  /** Основной цвет обложки (`pickBase`) — для `duo`; null — как акцент. */
  tone?: RGB | null
}

export function themeFrom(
  src: RGB | null,
  surface: Surface = 'echo',
  light = false,
  cover: CoverShift | null = null,
  opts: TintOptions = {},
): ThemeTokens {
  const paint: Paint = { tint: opts.tint ?? 'full', tone: opts.tint === 'duo' ? (opts.tone ?? null) : null }
  if (!cover) return build(src, surface, light, NO_SHADE, paint)
  const k = COVER_STRENGTH[cover.strength] ?? COVER_STRENGTH.medium
  const base = build(src, surface, light, { f: 0, chroma: k.chroma, hue: k.hue }, paint)
  let f = coverBias(cover)
  for (let i = 0; i < GUARD_TRIES && f; i++) {
    const t = build(src, surface, light, { f, chroma: k.chroma, hue: k.hue }, paint)
    if (keepsContrast(t, base)) return t
    f *= GUARD_STEP
  }
  return base
}

interface Paint {
  tint: Tint
  tone: RGB | null
}

/** Насколько у «Весь интерфейс» подкрашены наведение, нажатие и подложки (доля насыщенности акцента, потолок). */
const WASH = { m: 0.5, max: 0.07 }

function build(src: RGB | null, surface: Surface, light: boolean, shade: Shade, paint: Paint): ThemeTokens {
  const k = (light ? SURFACES_LIGHT : SURFACES)[surface]
  const base = src ? rgbToOklch(src) : { l: 0, c: 0, h: 0 }
  const mono = base.c < MONO_C
  const c = mono ? 0 : base.c
  const h = base.h
  // «Два цвета»: поверхности и текст — оттенок и насыщенность основного цвета обложки, акцент — свой
  const toneLch = !mono && paint.tone ? rgbToOklch(paint.tone) : null
  const tone = toneLch && toneLch.c >= MONO_C ? toneLch : null
  const sc0 = tone ? tone.c : c
  const sh0 = tone ? tone.h : h
  const full = paint.tint !== 'calm'
  const cc = (m: number, mx: number) => Math.min(c * m, mx)
  const ok = (l: number, ch: number): Lch => fitGamut({ l, c: ch, h })
  const okS = (l: number, ch: number): Lch => fitGamut({ l, c: ch, h: sh0 })
  const ccS = (m: number, mx: number) => Math.min(sc0 * m, mx)
  // поверхности: светлота со сдвигом, насыщенность × сила, но не ниже лёгкого оттенка обложки
  const sh = (l: number) => shiftLightness(l, shade.f, light)
  const sc = (m: number, mx: number) => (mono ? 0 : Math.max(Math.min(sc0 * m * shade.chroma, mx * shade.chroma), Math.min(sc0, shade.hue)))
  const surf = (l: number, m: number, mx: number) => okS(sh(l), sc(m, mx))
  // вторичный текст «Весь интерфейс» чуть заметнее в оттенке (как подписи артистов в списках)
  const tk = full ? 1.8 : 1
  const gray = !!k.grayText
  const lch: ThemeTokens['lch'] = {
    bg: surf(k.bgL, k.bgC, k.bgMax),
    s0: surf((k.bgL + k.sL[0]) / 2, k.sC, k.sMax),
    s1: surf(k.sL[0], k.sC, k.sMax),
    s2: surf(k.sL[1], k.sC, k.sMax),
    s3: surf(k.sL[2], k.sC, k.sMax),
    border: surf(k.bdL, k.bdC, k.bdMax),
    text: okS(k.txL, gray ? 0 : ccS(0.03, 0.008)),
    t2: okS(k.t2L, gray ? 0 : ccS(0.06 * tk, 0.014 * tk)),
    t3: okS(k.t3L, gray ? 0 : ccS(0.08 * tk, 0.018 * tk)),
    accent: mono ? ok(light ? 0.22 : 0.95, 0) : ok(k.accL, Math.min(c, k.accMax)),
    ink: light ? ok(0.985, mono || gray ? 0 : cc(0.03, 0.008)) : mono ? ok(0.16, 0) : gray ? ok(0.12, 0) : ok(0.18, cc(0.35, 0.05)),
    // дорожка прогресса: у Сигнала своя, насыщенная; у остальных — поверхность 3
    track: surface === 'signal' ? okS(sh(light ? 0.82 : 0.42), ccS(0.4, 0.06)) : surf(k.sL[2], k.sC, k.sMax),
  }
  const s = (x: Lch, a = 1) => oklch(x, a)
  const vars: Record<string, string> = {
    '--bg': s(lch.bg),
    '--surface-0': s(lch.s0),
    '--surface-1': s(lch.s1),
    '--surface-2': s(lch.s2),
    '--surface-3': s(lch.s3),
    '--border': s(lch.border),
    '--border-strong': s({ ...lch.border, l: lch.border.l + 0.07 }),
    '--text': s(lch.text),
    '--text-2': s(lch.t2),
    '--text-3': s(lch.t3),
    '--accent': s(lch.accent),
    '--accent-ink': s(lch.ink),
    '--accent-soft': mono ? (light ? 'oklch(0.2 0 0 / 0.08)' : 'oklch(0.95 0 0 / 0.12)') : s(lch.accent, k.softA),
    // подкраска верха страницы; у Монолита поверхности серые — цвет обложки только в свечении и прогрессе
    '--tint': s(okS(sh(light ? 0.93 : 0.2), gray ? sc(0, 0) : ccS(light ? 0.3 : 0.6, light ? 0.04 : 0.09))),
    '--track': s(lch.track),
    // свечение за обложкой (поверхность и смена трека «Монолит»)
    '--glow': mono ? 'oklch(0.7 0 0 / 0.25)' : s(ok(light ? 0.7 : 0.62, Math.min(c, 0.2)), light ? 0.45 : 0.55),
    ...wash(mono || !full || gray ? null : ok(light ? 0.3 : 0.9, cc(WASH.m, WASH.max)), light),
    // заглушка обложки (нет картинки): подложка и значок в оттенке акцента; «Спокойно» и монохром — серые
    '--ph-wash': mono || !full || gray ? 'transparent' : s(lch.accent, light ? 0.12 : 0.1),
    '--ph-ink': mono || !full || gray ? s(lch.t3) : s(ok(light ? 0.45 : 0.78, Math.min(c, k.accMax) * 0.8)),
    ...SURFACE_DECOR[surface],
  }
  return { lch, mono, vars, accent: oklchToRgb(lch.accent), bg: oklchToRgb(lch.bg), ink: oklchToRgb(lch.ink), shift: shade.f }
}

/** Наведение, нажатие и подложка: белые (чёрные в светлой) с прозрачностью — или в оттенке акцента. */
function wash(x: Lch | null, light: boolean): Record<string, string> {
  const a = light ? { hover: 0.055, press: 0.1, plate: 0.035 } : { hover: 0.07, press: 0.14, plate: 0.04 }
  const c = x ?? { l: light ? 0 : 1, c: 0, h: 0 }
  return {
    '--hover': oklch(c, a.hover),
    '--press': oklch(c, a.press),
    '--plate': oklch(c, a.plate),
  }
}

export const css = ([r, g, b]: RGB, a = 1) => (a === 1 ? `rgb(${r} ${g} ${b})` : `rgb(${r} ${g} ${b} / ${a})`)
