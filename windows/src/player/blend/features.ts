// Покадровые признаки для анализа сведения (docs/BLEND.md §4.3): STFT 1024 / шаг 256 на 11 025 Гц,
// окно Ханна. Один проход по треку считает всё, что нужно дальше: громкость кадра, энергию низа и
// середины, спектральный поток по трём полосам (огибающая атак) и хрому. Спектры не храним — 4 минуты
// трека это ~10 тысяч кадров, признаки занимают сотни килобайт.

import { Fft, hann } from './fft'

export const SAMPLE_RATE = 11025
export const FRAME = 1024
export const HOP = 256
/** Шаг кадра, мс (~23.2). */
export const FRAME_MS = (HOP / SAMPLE_RATE) * 1000
const BIN_HZ = SAMPLE_RATE / FRAME
const LOW_MAX_HZ = 200
const MID_MIN_HZ = 300
const MID_MAX_HZ = 3000
const FLUX_HIGH_HZ = 3000
const CHROMA_MIN_HZ = 55
const CHROMA_MAX_HZ = 2000
/** Тишина по краям — ниже стольких дБ от пика. */
export const SILENCE_DB = -50
/** Поток атак опережает сам удар: кадр «видит» его раньше середины окна. Сдвиг подобран по щелчкам
 *  (без него сетка встаёт на 12–15 мс раньше удара; тест сетки, `firstBeatMs` ±10 мс). */
const ONSET_SHIFT_MS = 13

export interface Frames {
  count: number
  /** RMS кадра во времени. */
  rms: Float32Array
  /** Энергия спектра ниже 200 Гц. */
  low: Float32Array
  /** Энергия 300 Гц – 3 кГц (грубый признак вокала). */
  mid: Float32Array
  /** Спектральный поток (рост модулей в логарифме) по полосам. */
  fluxLow: Float32Array
  fluxMid: Float32Array
  fluxHigh: Float32Array
  /** Хрома: `count × 12`, класс 0 — до. Энергия класса — средняя по его бинам. */
  chroma: Float32Array
}

/** Время кадра `i` (может быть дробным) в мс: середина окна. */
export function frameTimeMs(i: number): number {
  return ((i * HOP + FRAME / 2) / SAMPLE_RATE) * 1000 + ONSET_SHIFT_MS
}

/** Кадр, на который приходится время `ms` (дробный). */
export function frameAt(ms: number): number {
  return (((ms - ONSET_SHIFT_MS) / 1000) * SAMPLE_RATE - FRAME / 2) / HOP
}

export function frameCount(samples: number): number {
  return Math.max(1, Math.ceil(samples / HOP))
}

/** Класс высоты бина: 0…11 (до = 0) или −1, если бин вне 55 Гц – 2 кГц. */
function pitchClasses(): { pc: Int8Array; perClass: Float32Array } {
  const pc = new Int8Array(FRAME / 2 + 1).fill(-1)
  const perClass = new Float32Array(12)
  for (let k = 1; k <= FRAME / 2; k++) {
    const hz = k * BIN_HZ
    if (hz < CHROMA_MIN_HZ || hz > CHROMA_MAX_HZ) continue
    const c = (((Math.round(12 * Math.log2(hz / 440)) + 9) % 12) + 12) % 12
    pc[k] = c
    perClass[c] += 1
  }
  return { pc, perClass }
}

export function frameFeatures(x: Float32Array): Frames {
  const count = frameCount(x.length)
  const out: Frames = {
    count,
    rms: new Float32Array(count),
    low: new Float32Array(count),
    mid: new Float32Array(count),
    fluxLow: new Float32Array(count),
    fluxMid: new Float32Array(count),
    fluxHigh: new Float32Array(count),
    chroma: new Float32Array(count * 12),
  }
  const fft = new Fft(FRAME)
  const win = hann(FRAME)
  const re = new Float32Array(FRAME)
  const im = new Float32Array(FRAME)
  const bins = FRAME / 2 + 1
  let prev = new Float32Array(bins)
  let cur = new Float32Array(bins)
  const { pc, perClass } = pitchClasses()
  const lowTop = Math.floor(LOW_MAX_HZ / BIN_HZ)
  const midLo = Math.ceil(MID_MIN_HZ / BIN_HZ)
  const midHi = Math.floor(MID_MAX_HZ / BIN_HZ)
  const highLo = Math.ceil(FLUX_HIGH_HZ / BIN_HZ)

  for (let f = 0; f < count; f++) {
    const start = f * HOP
    let sq = 0
    for (let i = 0; i < FRAME; i++) {
      const s = start + i < x.length ? x[start + i] : 0
      sq += s * s
      re[i] = s * win[i]
      im[i] = 0
    }
    out.rms[f] = Math.sqrt(sq / FRAME)
    fft.transform(re, im)
    let low = 0
    let mid = 0
    let fl = 0
    let fm = 0
    let fh = 0
    const chroma = out.chroma.subarray(f * 12, f * 12 + 12)
    for (let k = 1; k < bins; k++) {
      const e = re[k] * re[k] + im[k] * im[k]
      const m = Math.log1p(Math.sqrt(e))
      cur[k] = m
      const rise = f > 0 && m > prev[k] ? m - prev[k] : 0
      if (k <= lowTop) {
        low += e
        fl += rise
      } else if (k < highLo) fm += rise
      else fh += rise
      if (k >= midLo && k <= midHi) mid += e
      if (pc[k] >= 0) chroma[pc[k]] += e
    }
    for (let c = 0; c < 12; c++) chroma[c] /= perClass[c] || 1
    out.low[f] = low
    out.mid[f] = mid
    out.fluxLow[f] = fl
    out.fluxMid[f] = fm
    out.fluxHigh[f] = fh
    const t = prev
    prev = cur
    cur = t
  }
  return out
}

/** Тишина по краям: первый и последний кадр громче −50 дБ от пика. */
export function silenceBounds(f: Frames, durationMs: number): { startMs: number; endMs: number } {
  let peak = 0
  for (let i = 0; i < f.count; i++) peak = Math.max(peak, f.rms[i])
  if (peak <= 0) return { startMs: 0, endMs: durationMs }
  const floor = peak * 10 ** (SILENCE_DB / 20)
  let first = 0
  while (first < f.count - 1 && f.rms[first] < floor) first++
  let last = f.count - 1
  while (last > first && f.rms[last] < floor) last--
  const startMs = ((first * HOP) / SAMPLE_RATE) * 1000
  const endMs = Math.min(durationMs, ((last * HOP + FRAME) / SAMPLE_RATE) * 1000)
  return { startMs, endMs }
}
