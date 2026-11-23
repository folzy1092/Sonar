// Анализ трека для сведения (docs/BLEND.md §4.3–4.4): из моно 11 025 Гц — края без тишины, темп, сетка,
// «раз», такты, фразы, тональность, громкость. Всё чистое: считает воркер (`analysis.worker.ts`),
// тесты гоняют те же функции на синтетике. Части — features / tempo / structure / key / loudness.

import { SAMPLE_RATE, frameFeatures, silenceBounds } from './features'
import { downbeatOf, tempoGrid } from './tempo'
import { type Bars, type Phrase, barFeatures, barStarts, phrasesOf, BEATS_PER_BAR } from './structure'
import { keyOf } from './key'
import { loudnessOf } from './loudness'

/** Поменяли алгоритм — поднять: старые результаты пересчитаются при следующем проигрывании. */
export const ANALYSIS_VERSION = 1

export interface BlendAnalysis {
  version: number
  ref: string
  durationMs: number
  /** Без тишины по краям. */
  startMs: number
  endMs: number
  bpm: number
  bpmConf: number
  /** Длина доли, 60000 / bpm. */
  beatMs: number
  /** Первая доля сетки. */
  firstBeatMs: number
  /** Какая доля сетки — «раз». */
  downbeat: 0 | 1 | 2 | 3
  gridStable: boolean
  /** 0…11 мажор, 12…23 минор, null — не знаем. */
  key: number | null
  keyConf: number
  /** ~LUFS. */
  loudness: number
  /** По тактам, 0…1. */
  bars: Bars
  phrases: Phrase[]
}

/** Каналы → моно (среднее). */
export function toMono(channels: Float32Array[]): Float32Array {
  if (channels.length === 1) return channels[0]
  const n = Math.min(...channels.map((c) => c.length))
  const out = new Float32Array(n)
  for (const c of channels) for (let i = 0; i < n; i++) out[i] += c[i] / channels.length
  return out
}

const round = (x: number, digits: number) => Math.round(x * 10 ** digits) / 10 ** digits

export function analyze(mono: Float32Array, ref: string): BlendAnalysis {
  const durationMs = Math.round((mono.length / SAMPLE_RATE) * 1000)
  const frames = frameFeatures(mono)
  const { startMs, endMs } = silenceBounds(frames, durationMs)
  const grid = tempoGrid(frames, startMs, endMs)
  const downbeat = downbeatOf(frames, grid, endMs)
  const starts = barStarts(grid, downbeat, endMs)
  const { bars, chroma } = barFeatures(frames, starts, BEATS_PER_BAR * grid.beatMs)
  const { key, keyConf } = keyOf(frames, startMs, endMs)
  return {
    version: ANALYSIS_VERSION,
    ref,
    durationMs,
    startMs: Math.round(startMs),
    endMs: Math.round(endMs),
    bpm: round(grid.bpm, 2),
    bpmConf: round(grid.bpmConf, 3),
    beatMs: round(grid.beatMs, 3),
    firstBeatMs: round(grid.firstBeatMs, 1),
    downbeat,
    gridStable: grid.gridStable,
    key,
    keyConf,
    loudness: loudnessOf(mono),
    bars,
    phrases: phrasesOf(bars, chroma),
  }
}
