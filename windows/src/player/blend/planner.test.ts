// Планировщик сведения (docs/BLEND.md §7, §14) на синтетическом анализе: детерминизм, откат на «Эхо» вне
// допуска темпа и без устойчивой сетки, срез не больше настройки, топ-8 без повторов.

import { describe, expect, it } from 'vitest'
import type { BlendAnalysis } from './analysis'
import { BEATS_PER_BAR, type Phrase } from './structure'
import { BLEND_KINDS, ECHO_DRY_FADE_BARS, kindsFor, lengthBars, plan, type PlanOpts, shapeOf, TOP_PLANS } from './planner'
import { BLEND_LENGTHS } from './settings'

interface TrackSpec {
  bpm?: number
  nBars?: number
  key?: number | null
  loudness?: number
  gridStable?: boolean
  energy?: number
  tailMs?: number
}

const PHRASES: Phrase[] = [
  { bar: 0, kind: 'intro' },
  { bar: 16, kind: 'body' },
  { bar: 32, kind: 'drop' },
  { bar: 48, kind: 'outro' },
]

function track(ref: string, s: TrackSpec = {}): BlendAnalysis {
  const bpm = s.bpm ?? 128
  const nBars = s.nBars ?? 64
  const beatMs = 60000 / bpm
  const endMs = nBars * BEATS_PER_BAR * beatMs
  const fill = (x: number) => Array.from({ length: nBars }, () => x)
  return {
    version: 1,
    ref,
    durationMs: endMs + (s.tailMs ?? 2000),
    startMs: 0,
    endMs,
    bpm,
    bpmConf: 0.9,
    beatMs,
    firstBeatMs: 0,
    downbeat: 0,
    gridStable: s.gridStable ?? true,
    key: s.key === undefined ? 0 : s.key,
    keyConf: 0.8,
    loudness: s.loudness ?? -10,
    bars: { energy: fill(s.energy ?? 0.5), low: fill(0.5), mid: fill(0.3), onsets: fill(0.5) },
    phrases: PHRASES.filter((p) => p.bar < nBars),
  }
}

const OPTS: PlanOpts = {
  type: 'auto',
  lengthSec: 16,
  cutSec: 8,
  tempoTolPct: 6,
  keyShift: true,
  rateA: 1,
  rateB: 1,
  linkedA: false,
  linkedB: false,
}

const idOf = (p: { kind: string; outMs: number; inMs: number }) => `${p.kind}:${p.outMs}:${p.inMs}`

describe('lengthBars', () => {
  it('секунды при темпе A → целые такты, 2…32', () => {
    expect(lengthBars(15, 128)).toBe(8)
    expect(lengthBars(30, 128)).toBe(16)
    expect(lengthBars(1, 128)).toBe(2)
    expect(lengthBars(120, 128)).toBe(32)
  })

  it('«Коротко · Норм · Длинно» дают разную длину при любом темпе', () => {
    for (const bpm of [60, 70, 93, 128, 145, 174]) {
      const [s, n, l] = BLEND_LENGTHS.map((sec) => lengthBars(sec, bpm))
      expect(s).toBeLessThan(n)
      expect(n).toBeLessThan(l)
    }
  })

  it('длина меняет каждый вид', () => {
    for (const kind of BLEND_KINDS) {
      const bars = BLEND_LENGTHS.map((sec) => shapeOf(kind, lengthBars(sec, 145)).bars)
      expect(bars[0]).toBeLessThan(bars[2])
    }
  })
})

describe('kindsFor', () => {
  it('«Авто» без синка — фильтр, эхо и плавный (бас-свап и дроп на двух сетках — каша)', () => {
    expect(kindsFor('auto', true)).toEqual(['bass', 'filter', 'echo', 'smooth', 'drop'])
    expect(kindsFor('auto', false)).toEqual(['filter', 'echo', 'smooth'])
  })

  it('ручной вид — всегда он, и без синка тоже', () => {
    for (const kind of BLEND_KINDS) {
      expect(kindsFor(kind, false)).toEqual([kind])
      expect(kindsFor(kind, true)).toEqual([kind])
    }
  })
})

describe('plan', () => {
  it('детерминирован: те же входы — тот же план', () => {
    const a = track('sc:a')
    const b = track('ym:b', { key: 7 })
    expect(plan(a, b, OPTS)).toEqual(plan(a, b, OPTS))
  })

  it('не больше восьми вариантов, без повторов, лучший первым', () => {
    const plans = plan(track('sc:a'), track('ym:b'), OPTS)
    expect(plans.length).toBeGreaterThan(0)
    expect(plans.length).toBeLessThanOrEqual(TOP_PLANS)
    expect(new Set(plans.map(idOf)).size).toBe(plans.length)
    for (let i = 1; i < plans.length; i++) expect(plans[i - 1].score).toBeGreaterThanOrEqual(plans[i].score)
    for (const p of plans) {
      expect(p.score).toBeGreaterThanOrEqual(0)
      expect(p.score).toBeLessThanOrEqual(1)
    }
  })

  it('тот же темп и тональность — синк, без сдвига тона', () => {
    const [best] = plan(track('sc:a'), track('ym:b'), OPTS)
    expect(best.sync).toBe(true)
    expect(best.shift).toBe(0)
    expect(best.parts.tempo).toBe(1)
    expect(best.beatRatio).toBe(1)
  })

  it('темп вне допуска: выбранный вид остаётся, но без синка; «Авто» берёт фильтр', () => {
    const a = track('sc:a', { bpm: 145 })
    const b = track('ym:b', { bpm: 93 })
    for (const type of ['bass', 'filter', 'drop', 'echo'] as const) {
      const manual = plan(a, b, { ...OPTS, type })
      expect(manual.length).toBeGreaterThan(0)
      expect(manual.every((p) => p.kind === type && !p.sync)).toBe(true)
    }
    const auto = plan(a, b, OPTS)
    expect(auto[0].kind).toBe('filter')
    expect(auto.every((p) => !p.sync)).toBe(true)
  })

  it('A доигрывает свою часть перехода до конца файла: `ended` не оборвёт переход', () => {
    // музыка до самого конца файла — такт «за концом музыки» вышел бы за файл
    const a = track('sc:a', { tailMs: 0 })
    for (const type of ['auto', 'echo', 'bass', 'filter', 'smooth', 'drop'] as const) {
      for (const p of plan(a, track('ym:b'), { ...OPTS, type, cutSec: 20 })) {
        const silentMs = p.endAMs + (p.kind === 'echo' ? ECHO_DRY_FADE_BARS * 1875 : 0)
        expect(silentMs).toBeLessThanOrEqual(a.durationMs - 300)
      }
    }
  })

  it('шире «Можно срезать» — можно уйти до аутро A', () => {
    const a = track('sc:a', { nBars: 64 })
    const b = track('ym:b')
    const outro = 48 * 1875
    const narrow = plan(a, b, { ...OPTS, type: 'filter', cutSec: 8 })
    const wide = plan(a, b, { ...OPTS, type: 'filter', cutSec: 45 })
    expect(narrow.some((p) => p.endAMs === outro)).toBe(false)
    expect(wide.some((p) => p.endAMs === outro)).toBe(true)
  })

  it('неустойчивая сетка — ни одного плана с синком', () => {
    const plans = plan(track('sc:a'), track('ym:b', { gridStable: false }), OPTS)
    expect(plans.length).toBeGreaterThan(0)
    expect(plans.some((p) => p.sync)).toBe(false)
    const filter = plan(track('sc:a', { gridStable: false }), track('ym:b'), { ...OPTS, type: 'filter' })[0]
    expect(filter.kind).toBe('filter')
    expect(filter.sync).toBe(false)
  })

  it('половинный темп B сводится в двойной сетке', () => {
    const [best] = plan(track('sc:a', { bpm: 128 }), track('ym:b', { bpm: 64 }), OPTS)
    expect(best.beatRatio).toBe(0.5)
    expect(best.sync).toBe(true)
  })

  it('срез с конца A и начала B не больше настройки, при 0 — ничего не режем', () => {
    for (const cutSec of [0, 4, 8, 20]) {
      const plans = plan(track('sc:a'), track('ym:b'), { ...OPTS, cutSec })
      expect(plans.length).toBeGreaterThan(0)
      for (const p of plans) {
        expect(p.cutOutMs).toBeLessThanOrEqual(cutSec * 1000)
        expect(p.cutInMs).toBeLessThanOrEqual(cutSec * 1000)
      }
    }
  })

  it('«Эхо» набирается 2 такта (на коротком — 1), B входит после них, без синка', () => {
    expect(shapeOf('echo', 4).inAtBar).toBe(1)
    const plans = plan(track('sc:a'), track('ym:b'), { ...OPTS, type: 'echo' })
    expect(plans.length).toBeGreaterThan(0)
    for (const p of plans) {
      expect(p.kind).toBe('echo')
      expect(p.inAtBar).toBe(2)
      expect(p.sync).toBe(false)
      expect(p.endAMs).toBeGreaterThan(p.outMs)
    }
  })

  it('громкость B подгоняется под A, но не больше ±9 дБ', () => {
    expect(plan(track('sc:a', { loudness: -8 }), track('ym:b', { loudness: -14 }), OPTS)[0].gainDb).toBe(6)
    expect(plan(track('sc:a', { loudness: -4 }), track('ym:b', { loudness: -30 }), OPTS)[0].gainDb).toBe(9)
    expect(plan(track('sc:a', { loudness: -80 }), track('ym:b'), OPTS)[0].gainDb).toBe(0)
  })

  it('несовместимая тональность без права сдвига — бас-свап проигрывает', () => {
    const a = track('sc:a', { key: 0 })
    const b = track('ym:b', { key: 1 })
    const free = plan(a, b, { ...OPTS, type: 'bass' })[0]
    const locked = plan(a, b, { ...OPTS, type: 'bass', keyShift: false })[0]
    expect(free.shift).toBe(-1)
    expect(locked.shift).toBe(0)
    expect(locked.score).toBeLessThan(free.score)
  })

  it('👎 вида снижает его оценку', () => {
    const a = track('sc:a')
    const b = track('ym:b')
    const plain = plan(a, b, { ...OPTS, type: 'echo' })[0]
    const disliked = plan(a, b, { ...OPTS, type: 'echo', ratings: { echo: -1 } })[0]
    expect(disliked.score).toBeLessThan(plain.score)
    expect(disliked.parts.rating).toBe(0)
  })

  it('битый темп или скорость — пусто', () => {
    expect(plan(track('sc:a', { bpm: 0 }), track('ym:b'), OPTS)).toEqual([])
    expect(plan(track('sc:a'), track('ym:b'), { ...OPTS, rateB: 0 })).toEqual([])
  })
})
