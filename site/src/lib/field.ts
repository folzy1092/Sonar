// Поле точек героя — порт `ios/Sonar/Features/Home/SonarField.swift` (та же математика, те же числа):
// сетка кружков, размер — яркость фигуры в этом месте; фигуры по кругу перетекают друг в друга:
// знак Sonar → шар со светом → две волны. Здесь только чистые функции, рисует `scripts/sonar-field.ts`.

export interface Grid {
  readonly width: number
  readonly height: number
  readonly step: number
  readonly cols: number
  readonly rows: number
  readonly originX: number
  readonly originY: number
}

export interface Poke {
  readonly x: number
  readonly y: number
  readonly time: number
  /** 0 — разлёт кольцом, 1 — вихрь, 2 — подскок. */
  readonly kind: number
}

export interface Offset {
  readonly dx: number
  readonly dy: number
  readonly scale: number
}

/** Сколько шевелятся точки после касания, с. */
export const POKE_LIFE = 1.3
const POKE_SPEED = 420
const HOLD = 6.5
const MORPH = 2.5
const SHAPES = 3
const BREATH = 0.05

export function makeGrid(width: number, height: number, step: number): Grid {
  const cols = Math.max(0, Math.floor(width / step))
  const rows = Math.max(0, Math.floor(height / step))
  return {
    width,
    height,
    step,
    cols,
    rows,
    originX: (width - cols * step) / 2,
    originY: (height - rows * step) / 2,
  }
}

export function cellCenter(grid: Grid, col: number, row: number): { x: number; y: number } {
  return { x: grid.originX + (col + 0.5) * grid.step, y: grid.originY + (row + 0.5) * grid.step }
}

export function smooth(v: number): number {
  const x = Math.min(1, Math.max(0, v))
  return x * x * (3 - 2 * x)
}

/** Течение без касаний: точка плавает на ~1.5 px по своей синусоиде и чуть меняет размер. */
export function drift(col: number, row: number, t: number): Offset {
  return {
    dx: 1.5 * Math.sin(t * 0.9 + row * 0.32 + col * 0.07),
    dy: 1.5 * Math.cos(t * 0.75 + col * 0.28 - row * 0.05),
    scale: 0.9 + 0.1 * Math.sin(t * 1.1 + col * 0.45 + row * 0.6),
  }
}

const NO_OFFSET: Offset = { dx: 0, dy: 0, scale: 1 }

/** Волна от касания идёт через всю фигуру: разлёт кольцом, вихрь или подскок. */
export function play(poke: Poke, x: number, y: number, t: number): Offset {
  const age = t - poke.time
  if (age < 0 || age >= POKE_LIFE) return NO_OFFSET
  const vx = x - poke.x
  const vy = y - poke.y
  const d = Math.max(1, Math.hypot(vx, vy))
  const local = age - d / POKE_SPEED
  if (local <= 0) return NO_OFFSET
  const env = Math.exp(-local * 4.5) * Math.exp(-d / 520)
  if (poke.kind === 1) {
    const angle = 0.5 * Math.sin(local * 9) * env * Math.min(1, 60 / d + 0.25)
    const ca = Math.cos(angle)
    const sa = Math.sin(angle)
    return {
      dx: vx * ca - vy * sa - vx,
      dy: vx * sa + vy * ca - vy,
      scale: 1 + 0.25 * Math.abs(Math.sin(local * 9)) * env,
    }
  }
  if (poke.kind === 2) {
    const hop = Math.abs(Math.sin(local * 10)) * env
    return { dx: 0, dy: -10 * hop, scale: 1 + 0.45 * hop }
  }
  const push = 14 * Math.sin(local * 12) * env
  return { dx: (vx / d) * push, dy: (vy / d) * push, scale: 1 + 0.35 * Math.max(0, Math.sin(local * 12)) * env }
}

/** Шар со светом, который ходит по кругу. */
export function orb(x: number, y: number, t: number): number {
  const cx = 0.12 * Math.sin(t * 0.35)
  const cy = 0.05 * Math.cos(t * 0.5)
  const radius = 0.82
  const dx = (x - cx) / radius
  const dy = (y - cy) / radius
  const d2 = dx * dx + dy * dy
  if (d2 >= 1) return 0
  const nz = Math.sqrt(1 - d2)
  const lx = Math.cos(t * 0.6) * 0.6
  const ly = Math.sin(t * 0.6) * 0.45 - 0.35
  const lz = 0.7
  const len = Math.hypot(lx, ly, lz)
  const light = Math.max(0, (dx * lx + dy * ly + nz * lz) / len)
  const rim = smooth(Math.min(1, (1 - d2) * 6))
  return (0.18 + 0.82 * light) * rim
}

function band(x: number, y: number, t: number, taper: number, amp: number, freq: number, speed: number, shift: number, width: number): number {
  const center = amp * Math.sin(x * freq + t * speed + shift) + 0.18 * Math.sin(x * freq * 2.3 - t * speed * 0.7)
  const thick = width * (0.7 + 0.3 * Math.sin(x * 1.3 - t * 0.9 + shift)) * Math.sqrt(taper)
  if (thick <= 0.01) return 0
  const d = Math.abs(y - center) / thick
  return d < 1 ? Math.sqrt(smooth(1 - d)) : 0
}

/** Две волны-ленты, тоньше к краям. */
export function waves(x: number, y: number, halfW: number, t: number): number {
  const taper = Math.max(0, Math.cos(((x / halfW) * Math.PI) / 2))
  const a = band(x, y, t, taper, 0.26, 1.5, 1.1, 0, 0.5)
  const b = band(x, y, t, taper, 0.2, 2.0, -0.8, 1.9, 0.34) * 0.8
  return Math.max(a, b)
}

/** Яркость точки 0…1: смесь текущей и следующей фигуры, дыхание, растворение к краям. */
export function value(col: number, row: number, grid: Grid, logo: Float32Array, t: number): number {
  const period = HOLD + MORPH
  const phase = t % (period * SHAPES)
  const index = Math.floor(phase / period)
  const local = phase - index * period
  const k = local < HOLD ? 0 : smooth((local - HOLD) / MORPH)

  const x = (col + 0.5 - grid.cols / 2) / (grid.rows / 2)
  const y = (row + 0.5 - grid.rows / 2) / (grid.rows / 2)
  const halfW = grid.cols / grid.rows

  const shape = (i: number): number => {
    switch (i % SHAPES) {
      case 0: {
        const m = logo[row * grid.cols + col] ?? 0
        return m * (0.8 + 0.2 * Math.sin(x * 2.2 + y * 1.4 - t * 1.6))
      }
      case 1:
        return orb(x, y, t)
      default:
        return waves(x, y, halfW, t)
    }
  }
  let v = k === 0 ? shape(index) : shape(index) * (1 - k) + shape(index + 1) * k
  v *= 1 + BREATH * Math.sin(t * 1.4)
  const ex = Math.max(0, 1 - Math.pow(Math.abs(x) / halfW, 6))
  const ey = Math.max(0, 1 - Math.pow(Math.abs(y), 6))
  return Math.min(1, Math.max(0, v * ex * ey))
}

/**
 * Маска знака по сетке: `hits` — доля закрашенных проб в каждой клетке (0…1), дальше мягкий край
 * размытием 3×3 (центр весит 4) с усилением 1.25, как на iPhone.
 */
export function blurMask(hits: Float32Array, cols: number, rows: number): Float32Array {
  const out = new Float32Array(cols * rows)
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      let sum = 0
      let n = 0
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const r = row + dy
          const c = col + dx
          if (r < 0 || r >= rows || c < 0 || c >= cols) continue
          const w = dx === 0 && dy === 0 ? 4 : 1
          sum += hits[r * cols + c] * w
          n += w
        }
      }
      out[row * cols + col] = Math.min(1, (sum / n) * 1.25)
    }
  }
  return out
}
