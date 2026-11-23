// Такты, энергия по тактам и фразы для сведения (docs/BLEND.md §4.3, пп. 6–7).
//
// Фразы: границы по 8 тактов, но если на 4-м такте «новизна» (ядро Фута по сходству тактов) даёт
// явный пик — граница там. Метки считаются от медианы энергии без крайних фраз, иначе тихое интро и
// аутро тянут её вниз и «дроп» не отличить от тела трека.

import { type Frames, frameAt } from './features'
import { type Grid, beatTime } from './tempo'

export type PhraseKind = 'intro' | 'body' | 'build' | 'drop' | 'outro'
export interface Phrase {
  bar: number
  kind: PhraseKind
}
export interface Bars {
  energy: number[]
  low: number[]
  mid: number[]
  onsets: number[]
}

export const BEATS_PER_BAR = 4
const PHRASE_BARS = 8
const SHORT_PHRASE_BARS = 4
/** Полуширина ядра Фута, тактов. */
const KERNEL_BARS = 4
const QUIET_RATIO = 0.6
const DROP_RATIO = 1.6
/** Сколько тактов подряд должна расти энергия, чтобы фраза была «build». */
const BUILD_BARS = 4

/** Начала полных тактов (мс) от доли «раз». */
export function barStarts(g: Grid, downbeat: number, endMs: number): number[] {
  const out: number[] = []
  for (let b = 0; ; b++) {
    const t = beatTime(g, downbeat + BEATS_PER_BAR * b)
    if (t + BEATS_PER_BAR * g.beatMs > endMs) return out
    out.push(t)
  }
}

const round3 = (x: number) => Math.round(x * 1000) / 1000

function normalized(xs: number[]): number[] {
  const top = Math.max(0, ...xs)
  return xs.map((x) => (top > 0 ? round3(x / top) : 0))
}

/** Средние признаки кадров каждого такта + хрома такта (для новизны). */
export function barFeatures(f: Frames, starts: number[], barMs: number): { bars: Bars; chroma: Float32Array[] } {
  const raw = { energy: [] as number[], low: [] as number[], mid: [] as number[], onsets: [] as number[] }
  const chroma: Float32Array[] = []
  for (const t of starts) {
    const a = Math.max(0, Math.round(frameAt(t)))
    const b = Math.min(f.count, Math.max(a + 1, Math.round(frameAt(t + barMs))))
    let [rms, low, mid, onsets] = [0, 0, 0, 0]
    const c = new Float32Array(12)
    for (let i = a; i < b; i++) {
      rms += f.rms[i]
      low += f.low[i]
      mid += f.mid[i]
      onsets += f.fluxLow[i] + f.fluxMid[i] + f.fluxHigh[i]
      for (let k = 0; k < 12; k++) c[k] += f.chroma[i * 12 + k]
    }
    const n = b - a
    raw.energy.push(rms / n)
    raw.low.push(low / n)
    raw.mid.push(mid / n)
    raw.onsets.push(onsets / n)
    chroma.push(c)
  }
  return {
    bars: { energy: normalized(raw.energy), low: normalized(raw.low), mid: normalized(raw.mid), onsets: normalized(raw.onsets) },
    chroma,
  }
}

function barVectors(bars: Bars, chroma: Float32Array[]): number[][] {
  return chroma.map((c, i) => {
    const sum = c.reduce((s, x) => s + x, 0) || 1
    return [...Array.from(c, (x) => x / sum), bars.energy[i], bars.low[i], bars.mid[i]]
  })
}

function cosine(a: number[], b: number[]): number {
  let [ab, aa, bb] = [0, 0, 0]
  for (let i = 0; i < a.length; i++) {
    ab += a[i] * b[i]
    aa += a[i] * a[i]
    bb += b[i] * b[i]
  }
  return aa > 0 && bb > 0 ? ab / Math.sqrt(aa * bb) : 1
}

/** Новизна на границе каждого такта: ядро-шахматка по матрице косинусного сходства. */
export function novelty(vectors: number[][]): number[] {
  const n = vectors.length
  const out = new Array<number>(n).fill(0)
  for (let b = 1; b < n; b++) {
    let s = 0
    let count = 0
    for (let i = -KERNEL_BARS; i < KERNEL_BARS; i++) {
      for (let j = -KERNEL_BARS; j < KERNEL_BARS; j++) {
        const [x, y] = [b + i, b + j]
        if (x < 0 || y < 0 || x >= n || y >= n) continue
        const sign = i < 0 === j < 0 ? 1 : -1
        s += sign * cosine(vectors[x], vectors[y])
        count++
      }
    }
    out[b] = count ? Math.max(0, s / count) : 0
  }
  return out
}

/** Номера тактов, с которых начинаются фразы: по 8, раньше на 4, если там явный пик новизны. */
export function phraseBounds(nov: number[]): number[] {
  const n = nov.length
  if (n === 0) return []
  const mean = nov.reduce((s, x) => s + x, 0) / n
  const sd = Math.sqrt(nov.reduce((s, x) => s + (x - mean) ** 2, 0) / n)
  const out = [0]
  for (let b = 0; ; ) {
    const short = b + SHORT_PHRASE_BARS
    const long = b + PHRASE_BARS
    const early = short < n && nov[short] > mean + sd && nov[short] >= (nov[long] ?? 0)
    b = early ? short : long
    if (b >= n) return out
    out.push(b)
  }
}

function median(xs: number[]): number {
  if (xs.length === 0) return 0
  const s = [...xs].sort((a, b) => a - b)
  const m = s.length >> 1
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2
}

const avg = (xs: number[]) => (xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : 0)

function rises(xs: number[]): boolean {
  let run = 0
  for (let i = 1; i < xs.length; i++) {
    run = xs[i] > xs[i - 1] ? run + 1 : 0
    if (run >= BUILD_BARS) return true
  }
  return false
}

/** Метки фраз по энергии и низу тактов. */
export function phraseKinds(bars: Bars, bounds: number[]): Phrase[] {
  const n = bars.energy.length
  const spans = bounds.map((bar, i) => [bar, bounds[i + 1] ?? n] as const)
  const energy = spans.map(([a, b]) => avg(bars.energy.slice(a, b)))
  const low = spans.map(([a, b]) => avg(bars.low.slice(a, b)))
  const inner = spans.length > 2 ? spans.slice(1, -1) : spans
  const ref = median(inner.flatMap(([a, b]) => bars.energy.slice(a, b)))
  const quiet = energy.map((e) => e < QUIET_RATIO * ref)
  const kinds: PhraseKind[] = spans.map(() => 'body')
  for (let i = 0; i < spans.length && quiet[i]; i++) kinds[i] = 'intro'
  for (let i = spans.length - 1; i > 0 && quiet[i] && kinds[i] !== 'intro'; i--) kinds[i] = 'outro'
  for (let i = 0; i < spans.length; i++) {
    if (kinds[i] !== 'body') continue
    const p = i - 1
    const jump = p >= 0 && energy[i] >= DROP_RATIO * energy[p] && low[i] >= DROP_RATIO * low[p]
    if (jump && (kinds[p] === 'build' || quiet[p])) kinds[i] = 'drop'
    else if (rises(bars.energy.slice(...spans[i]))) kinds[i] = 'build'
  }
  return spans.map(([bar], i) => ({ bar, kind: kinds[i] }))
}

export function phrasesOf(bars: Bars, chroma: Float32Array[]): Phrase[] {
  return phraseKinds(bars, phraseBounds(novelty(barVectors(bars, chroma))))
}
