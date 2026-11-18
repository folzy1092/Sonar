// Поле точек героя Главной (порт iPhone `Features/Home/SonarField.swift`, решение владельца 2026-11-18):
// сетка кружков, размер каждого — «яркость» фигуры в этом месте. Фигуры по кругу перетекают друг в
// друга: живая «слизь» из капель (метаболы) → знак Sonar с бликом → снова слизь → две волны-ленты.
// Точки сами чуть плывут и дышат, когда играет музыка — сильнее и с рябью от центра. Чистая математика
// без DOM — рисует `components/SonarField.svelte`.

export interface Grid {
  cols: number
  rows: number
  step: number
  ox: number
  oy: number
}

export function makeGrid(width: number, height: number, step: number): Grid {
  const cols = Math.max(0, Math.floor(width / step))
  const rows = Math.max(0, Math.floor(height / step))
  return { cols, rows, step, ox: (width - cols * step) / 2, oy: (height - rows * step) / 2 }
}

export const smooth = (v: number): number => {
  const x = Math.min(1, Math.max(0, v))
  return x * x * (3 - 2 * x)
}

/** Сколько секунд фигура держится и сколько перетекает в следующую. */
export const HOLD = 7
export const MORPH = 2.8
/** Порядок фигур: слизь чаще всего, знак — время от времени. */
export const SHAPES = ['slime', 'logo', 'slime', 'waves'] as const
export type Shape = (typeof SHAPES)[number]

/** Какая фигура сейчас и насколько она перетекла в следующую (k: 0…1). */
export function phaseAt(t: number): { index: number; k: number } {
  const period = HOLD + MORPH
  const total = period * SHAPES.length
  const phase = ((t % total) + total) % total
  const index = Math.floor(phase / period)
  const local = phase - index * period
  return { index, k: local < HOLD ? 0 : smooth((local - HOLD) / MORPH) }
}

/** «Слизь»: четыре капли плавают по своим орбитам и сливаются, когда сходятся (метаболы). */
export function slime(x: number, y: number, t: number, halfW: number): number {
  let f = 0
  const blobs = 4
  for (let i = 0; i < blobs; i++) {
    const a = t * (0.21 + i * 0.07) + i * 1.7
    const cx = Math.sin(a) * halfW * 0.42 + Math.sin(a * 0.53 + i) * 0.18
    const cy = Math.cos(a * 0.83 + i * 2.1) * 0.38
    const r = 0.34 + 0.08 * Math.sin(t * 0.6 + i * 1.3)
    const dx = x - cx
    const dy = y - cy
    f += (r * r) / (dx * dx + dy * dy + 1e-4)
  }
  // порог поверхности ~1: внутри — полная яркость, край мягкий
  return smooth((f - 0.75) / 0.6)
}

/** Две волны-ленты, тоньше к краям. */
export function waves(x: number, y: number, halfW: number, t: number): number {
  const taper = Math.max(0, Math.cos(((x / halfW) * Math.PI) / 2))
  const band = (amp: number, freq: number, speed: number, shift: number, width: number) => {
    const center = amp * Math.sin(x * freq + t * speed + shift) + 0.18 * Math.sin(x * freq * 2.3 - t * speed * 0.7)
    const thick = width * (0.7 + 0.3 * Math.sin(x * 1.3 - t * 0.9 + shift)) * Math.sqrt(taper)
    if (thick <= 0.01) return 0
    const d = Math.abs(y - center) / thick
    return d < 1 ? Math.sqrt(smooth(1 - d)) : 0
  }
  return Math.max(band(0.26, 1.5, 1.1, 0, 0.5), band(0.2, 2.0, -0.8, 1.9, 0.34) * 0.8)
}

/** Значение точки (col, row): 0 — точки нет, 1 — полный кружок. `logo` — маска знака на эту сетку. */
export function fieldValue(col: number, row: number, g: Grid, logo: Float32Array | null, t: number, playing: boolean): number {
  const x = (col + 0.5 - g.cols / 2) / (g.rows / 2)
  const y = (row + 0.5 - g.rows / 2) / (g.rows / 2)
  const halfW = g.cols / g.rows
  const shape = (i: number): number => {
    switch (SHAPES[i % SHAPES.length]) {
      case 'logo': {
        const m = logo?.[row * g.cols + col] ?? 0
        return m * (0.8 + 0.2 * Math.sin(x * 2.2 + y * 1.4 - t * 1.6))
      }
      case 'waves':
        return waves(x, y, halfW, t)
      default:
        return slime(x, y, t, halfW)
    }
  }
  const { index, k } = phaseAt(t)
  let v = k === 0 ? shape(index) : shape(index) * (1 - k) + shape(index + 1) * k
  const breath = playing ? 0.12 : 0.05
  v *= 1 + breath * Math.sin(t * (playing ? 3.2 : 1.4))
  if (playing) v *= 0.86 + 0.14 * Math.sin(Math.hypot(x, y) * 7 - t * 4.5)
  // края поля растворяются
  const ex = Math.max(0, 1 - Math.pow(Math.abs(x) / halfW, 6))
  const ey = Math.max(0, 1 - Math.pow(Math.abs(y), 6))
  return Math.min(1, Math.max(0, v * ex * ey))
}

/** Течение без музыки: точка плавает на ~1.5 px и чуть меняет размер. */
export function drift(col: number, row: number, t: number): { dx: number; dy: number; scale: number } {
  return {
    dx: 1.5 * Math.sin(t * 0.9 + row * 0.32 + col * 0.07),
    dy: 1.5 * Math.cos(t * 0.75 + col * 0.28 - row * 0.05),
    scale: 0.9 + 0.1 * Math.sin(t * 1.1 + col * 0.45 + row * 0.6),
  }
}
