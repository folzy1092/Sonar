// Анализ сведения на синтетике (docs/BLEND.md §14): щелчки, аккорды синусами, шум. Файлов в репо нет —
// сигнал собирается здесь же, шум с фиксированным зерном, поэтому тесты не плавают.

import { describe, expect, it } from 'vitest'
import { ANALYSIS_VERSION, analyze, toMono } from './analysis'
import { SAMPLE_RATE } from './features'
import { loudnessOf } from './loudness'

const SR = SAMPLE_RATE

function rng(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function addNoise(x: Float32Array, amp: number, seed = 1): Float32Array {
  const r = rng(seed)
  for (let i = 0; i < x.length; i++) x[i] += amp * (r() * 2 - 1)
  return x
}

/** Удар: «бочка» 55 Гц с затуханием + короткий щелчок шума сверху. */
function hit(x: Float32Array, atMs: number, low: number, click: number, r: () => number): void {
  const start = Math.round((atMs / 1000) * SR)
  const len = Math.round(0.15 * SR)
  for (let i = 0; i < len && start + i < x.length; i++) {
    if (start + i < 0) continue
    const t = i / SR
    x[start + i] += low * Math.sin(2 * Math.PI * 55 * t) * Math.exp(-t / 0.05)
    if (t < 0.03) x[start + i] += click * (r() * 2 - 1) * Math.exp(-t / 0.008)
  }
}

interface Clicks {
  seconds: number
  /** Темп в момент `t` (с). */
  bpm: number | ((t: number) => number)
  offsetMs?: number
  /** Громкость удара `k`. */
  gain?: (k: number, ms: number) => { low: number; click: number }
  /** Удары в этом окне не звучат. */
  mute?: (ms: number) => boolean
  noise?: number
}

function clicks(o: Clicks): Float32Array {
  const x = new Float32Array(Math.round(o.seconds * SR))
  const r = rng(7)
  const tempo = typeof o.bpm === 'number' ? () => o.bpm as number : o.bpm
  let ms = o.offsetMs ?? 100
  for (let k = 0; ms < o.seconds * 1000; k++) {
    const g = o.gain ? o.gain(k, ms) : { low: 0.6, click: 0.4 }
    if (!o.mute?.(ms)) hit(x, ms, g.low, g.click, r)
    ms += 60000 / tempo(ms / 1000)
  }
  return addNoise(x, o.noise ?? 0.01)
}

function tones(chords: number[][], secondsEach: number, repeat: number): Float32Array {
  const n = Math.round(secondsEach * SR)
  const x = new Float32Array(n * chords.length * repeat)
  for (let r = 0; r < repeat; r++) {
    chords.forEach((midi, c) => {
      const base = (r * chords.length + c) * n
      for (const m of midi) {
        const hz = 440 * 2 ** ((m - 69) / 12)
        for (let i = 0; i < n; i++) x[base + i] += (0.15 * Math.sin((2 * Math.PI * hz * i) / SR) * Math.min(1, i / 200, (n - i) / 200))
      }
    })
  }
  return x
}

function sine(seconds: number, hz: number, dbfs: number): Float32Array {
  const amp = 10 ** (dbfs / 20)
  return Float32Array.from({ length: Math.round(seconds * SR) }, (_, i) => amp * Math.sin((2 * Math.PI * hz * i) / SR))
}

describe('темп', () => {
  it.each([128, 90, 174])('щелчки %i BPM с шумом → темп ±0.5, не вдвое', (bpm) => {
    const a = analyze(clicks({ seconds: 40, bpm }), 'sc:t')
    expect(Math.abs(a.bpm - bpm)).toBeLessThanOrEqual(0.5)
    expect(a.bpmConf).toBeGreaterThan(0)
  })

  it('пауза посередине не сбивает темп', () => {
    const x = clicks({ seconds: 40, bpm: 128, mute: (ms) => ms > 15000 && ms < 25000 })
    expect(Math.abs(analyze(x, 'sc:t').bpm - 128)).toBeLessThanOrEqual(0.5)
  })
})

describe('сетка', () => {
  it('сдвиг 137 мс → первая доля ±10 мс', () => {
    const a = analyze(clicks({ seconds: 30, bpm: 128, offsetMs: 137 }), 'sc:t')
    expect(Math.abs(a.firstBeatMs - 137)).toBeLessThanOrEqual(10)
    expect(a.gridStable).toBe(true)
  })

  it('ровный темп — сетка стабильна, разгон 120 → 126 — нет', () => {
    expect(analyze(clicks({ seconds: 60, bpm: 120 }), 'sc:t').gridStable).toBe(true)
    const ramp = clicks({ seconds: 60, bpm: (t) => 120 + (6 * t) / 60 })
    expect(analyze(ramp, 'sc:t').gridStable).toBe(false)
  })
})

describe('такт', () => {
  it.each([0, 1, 2, 3])('акцент низа на каждой 4-й доле (с %i-й) → downbeat', (d) => {
    const gain = (k: number) => (k % 4 === d ? { low: 0.9, click: 0.4 } : { low: 0.25, click: 0.4 })
    expect(analyze(clicks({ seconds: 40, bpm: 124, gain }), 'sc:t').downbeat).toBe(d)
  })
})

describe('фразы', () => {
  it('8 тактов тихо + 8 громко + 8 тихо → границы 8 и 16, intro / drop / outro', () => {
    const barMs = (4 * 60000) / 120
    const gain = (k: number, ms: number) => {
      const loud = ms >= 8 * barMs && ms < 16 * barMs
      const accent = k % 4 === 0 ? 1.5 : 1
      return loud ? { low: 0.8 * accent, click: 0.6 } : { low: 0.12 * accent, click: 0.08 }
    }
    const a = analyze(clicks({ seconds: 24 * (barMs / 1000) + 0.5, bpm: 120, offsetMs: 0, gain, noise: 0.002 }), 'sc:t')
    expect(a.downbeat).toBe(0)
    expect(a.phrases).toEqual([
      { bar: 0, kind: 'intro' },
      { bar: 8, kind: 'drop' },
      { bar: 16, kind: 'outro' },
    ])
    expect(a.bars.energy).toHaveLength(24)
    expect(Math.max(...a.bars.energy)).toBe(1)
  })
})

describe('тональность', () => {
  it('C – F – G – C синусами → до мажор', () => {
    const a = analyze(tones([[60, 64, 67], [65, 69, 72], [67, 71, 74], [60, 64, 67]], 2, 3), 'sc:t')
    expect(a.key).toBe(0)
  })

  it('Am – Dm – E – Am → ля минор', () => {
    const a = analyze(tones([[69, 72, 76], [62, 65, 69], [64, 68, 71], [69, 72, 76]], 2, 3), 'sc:t')
    expect(a.key).toBe(21)
  })

  it('шум → тональность не знаем', () => {
    const a = analyze(addNoise(new Float32Array(20 * SR), 0.3, 3), 'sc:t')
    expect(a.keyConf).toBeLessThan(0.15)
    expect(a.key).toBeNull()
  })
})

describe('громкость', () => {
  it('синус −20 и −10 dBFS → разница 10 ± 0.5', () => {
    const diff = loudnessOf(sine(10, 1000, -10)) - loudnessOf(sine(10, 1000, -20))
    expect(Math.abs(diff - 10)).toBeLessThanOrEqual(0.5)
  })
})

describe('края и результат', () => {
  it('тишина по краям отрезается', () => {
    const x = new Float32Array(30 * SR)
    x.set(clicks({ seconds: 20, bpm: 128, noise: 0 }), 5 * SR)
    const a = analyze(x, 'sc:t')
    expect(a.startMs).toBeGreaterThan(4900)
    expect(a.startMs).toBeLessThan(5200)
    expect(a.endMs).toBeGreaterThan(24800)
    expect(a.endMs).toBeLessThan(25500)
    expect(a.firstBeatMs).toBeGreaterThan(5000)
  })

  it('сплошная тишина не падает', () => {
    const a = analyze(new Float32Array(5 * SR), 'sc:t')
    expect(a.key).toBeNull()
    expect(a.loudness).toBe(-70)
    expect(a.phrases.length).toBeLessThanOrEqual(1)
  })

  it('результат по форме §4.4 и в JSON без потерь', () => {
    const a = analyze(clicks({ seconds: 20, bpm: 128 }), 'ym:42')
    expect(a.version).toBe(ANALYSIS_VERSION)
    expect(a.ref).toBe('ym:42')
    expect(a.durationMs).toBe(20000)
    expect(a.beatMs).toBeCloseTo(60000 / a.bpm, 1)
    expect(JSON.parse(JSON.stringify(a))).toEqual(a)
    for (const arr of Object.values(a.bars)) for (const v of arr) expect(v).toBeGreaterThanOrEqual(0)
  })

  it('стерео сводится в моно средним', () => {
    expect(Array.from(toMono([Float32Array.of(1, 0), Float32Array.of(0, 1)]))).toEqual([0.5, 0.5])
  })
})
