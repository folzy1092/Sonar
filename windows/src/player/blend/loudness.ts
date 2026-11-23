// Громкость трека, грубый LUFS (docs/BLEND.md §4.3, п. 9): K-фильтр (полка +4 дБ и срез низа, как в
// BS.1770, коэффициенты по RBJ под 11 025 Гц), блоки 400 мс с шагом 100 мс, отсечка −70 LUFS и −10 LU
// от среднего. Точность ±1 LU не нужна — нужна разница громкостей двух треков.

import { SAMPLE_RATE } from './features'

const SHELF_HZ = 1681.97
const SHELF_DB = 4
const SHELF_Q = 0.7071
const HPF_HZ = 38.13
const HPF_Q = 0.5003
const BLOCK_MS = 400
const STEP_MS = 100
const ABS_GATE = -70
const REL_GATE = -10
/** Ниже — тишина: громкости нет. */
export const SILENT_LUFS = -70

type Biquad = [b0: number, b1: number, b2: number, a1: number, a2: number]

function highShelf(f0: number, db: number, q: number): Biquad {
  const a = 10 ** (db / 40)
  const w = (2 * Math.PI * f0) / SAMPLE_RATE
  const alpha = Math.sin(w) / (2 * q)
  const c = Math.cos(w)
  const s = 2 * Math.sqrt(a) * alpha
  const a0 = a + 1 - (a - 1) * c + s
  return [
    (a * (a + 1 + (a - 1) * c + s)) / a0,
    (-2 * a * (a - 1 + (a + 1) * c)) / a0,
    (a * (a + 1 + (a - 1) * c - s)) / a0,
    (2 * (a - 1 - (a + 1) * c)) / a0,
    (a + 1 - (a - 1) * c - s) / a0,
  ]
}

function highPass(f0: number, q: number): Biquad {
  const w = (2 * Math.PI * f0) / SAMPLE_RATE
  const alpha = Math.sin(w) / (2 * q)
  const c = Math.cos(w)
  const a0 = 1 + alpha
  return [(1 + c) / 2 / a0, -(1 + c) / a0, (1 + c) / 2 / a0, (-2 * c) / a0, (1 - alpha) / a0]
}

function filter(x: Float32Array, [b0, b1, b2, a1, a2]: Biquad): Float32Array {
  const y = new Float32Array(x.length)
  let [x1, x2, y1, y2] = [0, 0, 0, 0]
  for (let i = 0; i < x.length; i++) {
    const v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
    x2 = x1
    x1 = x[i]
    y2 = y1
    y1 = v
    y[i] = v
  }
  return y
}

const lufs = (meanSquare: number) => -0.691 + 10 * Math.log10(meanSquare)

export function loudnessOf(mono: Float32Array): number {
  const k = filter(filter(mono, highShelf(SHELF_HZ, SHELF_DB, SHELF_Q)), highPass(HPF_HZ, HPF_Q))
  const block = Math.round((BLOCK_MS / 1000) * SAMPLE_RATE)
  const step = Math.round((STEP_MS / 1000) * SAMPLE_RATE)
  const blocks: number[] = []
  for (let start = 0; start + block <= k.length; start += step) {
    let s = 0
    for (let i = start; i < start + block; i++) s += k[i] * k[i]
    const ms = s / block
    if (ms > 0 && lufs(ms) > ABS_GATE) blocks.push(ms)
  }
  if (blocks.length === 0) return SILENT_LUFS
  const gate = lufs(blocks.reduce((s, x) => s + x, 0) / blocks.length) + REL_GATE
  const kept = blocks.filter((ms) => lufs(ms) > gate)
  return Math.round(lufs(kept.reduce((s, x) => s + x, 0) / kept.length) * 10) / 10
}
