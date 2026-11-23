// Темп, сетка долей и «раз» такта для сведения (docs/BLEND.md §4.3, пп. 2–5).
//
// Огибающая атак — сумма потоков полос (каждая к своему среднему, верх вполовину), сглаженная и без
// скользящего среднего. Темп: автокорреляция в 60–200 BPM с гауссом вокруг 120 по октавам, затем
// уточнение перебором темпа и фазы по самой огибающей (точнее, чем лаг в кадр ~23 мс). Против ошибки
// «вдвое медленнее»: если между долями атак почти столько же, сколько на долях, — темп удваиваем.

import { type Frames, FRAME_MS, frameAt } from './features'

export const BPM_MIN = 60
export const BPM_MAX = 200
/** Итоговый темп приводится сюда (§4.3). */
export const BPM_NORM_MIN = 70
export const BPM_NORM_MAX = 180
const PRIOR_BPM = 120
/** Ширина гаусса по октавам. */
const PRIOR_OCTAVES = 1
/** Перебор фазы с таким шагом, мс. */
const PHASE_STEP_MS = 5
/** Сетки третей расходятся больше — сетка «плывёт». */
export const DRIFT_MAX_MS = 40
/** Атаки между долями не слабее этой доли атак на долях — темп вдвое быстрее. */
const DOUBLE_RATIO = 0.8
/** Треть с атаками слабее этой доли лучшей в сверке дрейфа не участвует (пауза, тишина). */
const DRIFT_MIN_SCORE = 0.3
const HIGH_WEIGHT = 0.5
/** Окно скользящего среднего огибающей, кадров в каждую сторону (~0.4 с). */
const MEAN_RADIUS = 9
/** Уточнение темпа: грубо ±3 % шагом 0.1, затем ±0.15 шагом 0.01. */
const COARSE_SPAN = 0.03
const FINE_SPAN = 0.15

export interface Grid {
  bpm: number
  bpmConf: number
  beatMs: number
  firstBeatMs: number
  gridStable: boolean
}

function meanOf(a: Float32Array): number {
  let s = 0
  for (let i = 0; i < a.length; i++) s += a[i]
  return a.length ? s / a.length : 0
}

/** Сумма полос (каждая к своему среднему) → сглаживание → минус скользящее среднее, не ниже нуля. */
function envelopeOf(bands: [Float32Array, number][]): Float32Array {
  const n = bands[0][0].length
  const raw = new Float32Array(n)
  for (const [band, weight] of bands) {
    const m = meanOf(band) || 1
    for (let i = 0; i < n; i++) raw[i] += (weight * band[i]) / m
  }
  const smooth = new Float32Array(n)
  for (let i = 0; i < n; i++) smooth[i] = 0.25 * (raw[i - 1] ?? raw[i]) + 0.5 * raw[i] + 0.25 * (raw[i + 1] ?? raw[i])
  const out = new Float32Array(n)
  let acc = 0
  let lo = 0
  let hi = -1
  for (let i = 0; i < n; i++) {
    while (hi < Math.min(n - 1, i + MEAN_RADIUS)) acc += smooth[++hi]
    while (lo < i - MEAN_RADIUS) acc -= smooth[lo++]
    out[i] = Math.max(0, smooth[i] - acc / (hi - lo + 1))
  }
  return out
}

export function onsetEnvelope(f: Frames): Float32Array {
  return envelopeOf([
    [f.fluxLow, 1],
    [f.fluxMid, 1],
    [f.fluxHigh, HIGH_WEIGHT],
  ])
}

/** Без верха: тарелки и хэты между долями не должны удваивать темп. */
export function bodyEnvelope(f: Frames): Float32Array {
  return envelopeOf([
    [f.fluxLow, 1],
    [f.fluxMid, 1],
  ])
}

/** Значение огибающей в момент `ms` (линейно между кадрами). */
export function envAt(env: Float32Array, ms: number): number {
  const p = frameAt(ms)
  if (p < 0 || p > env.length - 1) return 0
  const i = Math.floor(p)
  const frac = p - i
  return i + 1 < env.length ? env[i] * (1 - frac) + env[i + 1] * frac : env[i]
}

/** Средняя огибающая в точках сетки `phase + k·beat` внутри [from, to). */
function gridScore(env: Float32Array, beat: number, phase: number, from: number, to: number): number {
  let k = Math.ceil((from - phase) / beat)
  let s = 0
  let n = 0
  for (let t = phase + k * beat; t < to; t = phase + ++k * beat) {
    s += envAt(env, t)
    n++
  }
  return n ? s / n : 0
}

/** Лучшая фаза (0…beat) для длины доли на отрезке. */
export function bestPhase(env: Float32Array, beat: number, from: number, to: number): { phase: number; score: number } {
  let best = { phase: 0, score: -1 }
  for (let phase = 0; phase < beat; phase += PHASE_STEP_MS) {
    const score = gridScore(env, beat, phase, from, to)
    if (score > best.score) best = { phase, score }
  }
  return best
}

/** Грубый темп по автокорреляции с гауссом вокруг 120 BPM. */
function roughTempo(env: Float32Array): { bpm: number; conf: number } {
  const lagMin = Math.floor(60000 / BPM_MAX / FRAME_MS)
  const lagMax = Math.ceil(60000 / BPM_MIN / FRAME_MS)
  const acf = new Float32Array(lagMax + 2)
  for (let lag = lagMin - 1; lag <= lagMax + 1; lag++) {
    let s = 0
    for (let i = 0; i + lag < env.length; i++) s += env[i] * env[i + lag]
    acf[lag] = s / Math.max(1, env.length - lag)
  }
  const weighted = (lag: number) => {
    const octaves = Math.log2(60000 / (lag * FRAME_MS) / PRIOR_BPM) / PRIOR_OCTAVES
    return acf[lag] * Math.exp(-0.5 * octaves * octaves)
  }
  let best = lagMin
  let sum = 0
  for (let lag = lagMin; lag <= lagMax; lag++) {
    sum += acf[lag]
    if (weighted(lag) > weighted(best)) best = lag
  }
  const [a, b, c] = [weighted(best - 1), weighted(best), weighted(best + 1)]
  const bend = a - 2 * b + c
  const shift = bend < 0 ? Math.max(-0.5, Math.min(0.5, (0.5 * (a - c)) / bend)) : 0
  const mean = sum / (lagMax - lagMin + 1)
  const conf = acf[best] > 0 ? Math.max(0, Math.min(1, (acf[best] - mean) / acf[best])) : 0
  return { bpm: 60000 / ((best + shift) * FRAME_MS), conf }
}

/** Уточнение темпа перебором темпа и фазы по огибающей. */
function refineTempo(env: Float32Array, rough: number, from: number, to: number): { bpm: number; phase: number; score: number } {
  const search = (lo: number, hi: number, step: number) => {
    let best = { bpm: rough, phase: 0, score: -1 }
    for (let i = 0; lo + i * step <= hi + 1e-9; i++) {
      const bpm = lo + i * step
      const { phase, score } = bestPhase(env, 60000 / bpm, from, to)
      if (score > best.score) best = { bpm, phase, score }
    }
    return best
  }
  const coarse = search(rough * (1 - COARSE_SPAN), rough * (1 + COARSE_SPAN), 0.1)
  return search(coarse.bpm - FINE_SPAN, coarse.bpm + FINE_SPAN, 0.01)
}

/** Расстояние от `t` до ближайшей доли сетки (`phase`, `beat`), мс. */
function offGrid(t: number, phase: number, beat: number): number {
  const d = (((t - phase) % beat) + beat) % beat
  return Math.min(d, beat - d)
}

/** Своя сетка каждой трети (темп и фаза подобраны заново) на краях трети расходится с общей больше
 *  40 мс — темп не постоянный. Трети без атак (пауза, тишина) не в счёт. */
function driftOk(env: Float32Array, bpm: number, phase: number, from: number, to: number): boolean {
  const beat = 60000 / bpm
  const third = (to - from) / 3
  const parts = [0, 1, 2].map((i) => {
    const [a, b] = [from + i * third, from + (i + 1) * third]
    return { a, b, ...refineTempo(env, bpm, a, b) }
  })
  const top = Math.max(...parts.map((p) => p.score))
  for (const p of parts) {
    if (p.score < DRIFT_MIN_SCORE * top) continue
    const local = 60000 / p.bpm
    for (const t of [p.a, p.b]) {
      const nearest = p.phase + Math.round((t - p.phase) / local) * local
      if (offGrid(nearest, phase, beat) > DRIFT_MAX_MS) return false
    }
  }
  return true
}

export function tempoGrid(f: Frames, startMs: number, endMs: number): Grid {
  const env = onsetEnvelope(f)
  const rough = roughTempo(env)
  let { bpm, phase } = refineTempo(env, rough.bpm, startMs, endMs)
  const body = bodyEnvelope(f)
  const beat0 = 60000 / bpm
  const on = gridScore(body, beat0, phase, startMs, endMs)
  const off = gridScore(body, beat0, phase + beat0 / 2, startMs, endMs)
  if (bpm * 2 <= BPM_NORM_MAX && on > 0 && off >= DOUBLE_RATIO * on) bpm *= 2
  while (bpm < BPM_NORM_MIN) bpm *= 2
  while (bpm > BPM_NORM_MAX) bpm /= 2
  const beatMs = 60000 / bpm
  phase %= beatMs
  const k = Math.ceil((startMs - beatMs / 2 - phase) / beatMs)
  return {
    bpm,
    bpmConf: rough.conf,
    beatMs,
    firstBeatMs: phase + k * beatMs,
    gridStable: driftOk(env, bpm, phase, startMs, endMs),
  }
}

/** Время доли `k` сетки. */
export const beatTime = (g: Grid, k: number) => g.firstBeatMs + k * g.beatMs

export function cosineDistance(a: ArrayLike<number>, b: ArrayLike<number>): number {
  let ab = 0
  let aa = 0
  let bb = 0
  for (let i = 0; i < a.length; i++) {
    ab += a[i] * b[i]
    aa += a[i] * a[i]
    bb += b[i] * b[i]
  }
  return aa > 0 && bb > 0 ? 1 - ab / Math.sqrt(aa * bb) : 0
}

/** Сумма хромы кадров в [from, to) мс. */
export function chromaBetween(f: Frames, from: number, to: number): Float32Array {
  const out = new Float32Array(12)
  const a = Math.max(0, Math.round(frameAt(from)))
  const b = Math.min(f.count, Math.round(frameAt(to)))
  for (let i = a; i < b; i++) for (let c = 0; c < 12; c++) out[c] += f.chroma[i * 12 + c]
  return out
}

/** Какая доля сетки (0…3) — «раз»: максимум атак низа и смены гармонии. */
export function downbeatOf(f: Frames, g: Grid, endMs: number): 0 | 1 | 2 | 3 {
  const lows: number[] = []
  const changes: number[] = []
  // До первой доли — обычно тишина: сравнение с ней дало бы выброс «смены гармонии» на доле 0.
  let prev: Float32Array | null = null
  for (let k = 0; beatTime(g, k) < endMs; k++) {
    const t = beatTime(g, k)
    const p = Math.round(frameAt(t))
    let peak = 0
    for (let i = Math.max(0, p - 1); i <= Math.min(f.count - 1, p + 1); i++) peak = Math.max(peak, f.fluxLow[i])
    lows.push(peak)
    const cur = chromaBetween(f, t, t + g.beatMs)
    changes.push(prev ? cosineDistance(prev, cur) : 0)
    prev = cur
  }
  const norm = (xs: number[]) => {
    const m = xs.reduce((s, x) => s + x, 0) / (xs.length || 1)
    return m > 0 ? xs.map((x) => x / m) : xs.map(() => 0)
  }
  const [l, c] = [norm(lows), norm(changes)]
  const score = [0, 0, 0, 0]
  const count = [0, 0, 0, 0]
  for (let k = 0; k < l.length; k++) {
    score[k % 4] += l[k] + 0.5 * c[k]
    count[k % 4]++
  }
  let best = 0
  for (let d = 1; d < 4; d++) if (score[d] / (count[d] || 1) > score[best] / (count[best] || 1)) best = d
  return best as 0 | 1 | 2 | 3
}
