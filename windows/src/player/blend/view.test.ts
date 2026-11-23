// Карточка «Следующий переход» (docs/BLEND.md §10.1): какое состояние показать и числа плана.

import { describe, expect, it } from 'vitest'
import type { BlendAnalysis } from './analysis'
import { plan } from './planner'
import { BEATS_PER_BAR } from './structure'
import { buttonLabel, cardFor, type CardInput } from './view'

const A_MINOR = 21
const E_MINOR = 16

function track(ref: string, key: number | null, bpm = 128): BlendAnalysis {
  const nBars = 64
  const beatMs = 60000 / bpm
  const endMs = nBars * BEATS_PER_BAR * beatMs
  const fill = (x: number) => Array.from({ length: nBars }, () => x)
  return {
    version: 1,
    ref,
    durationMs: endMs + 2000,
    startMs: 0,
    endMs,
    bpm,
    bpmConf: 0.9,
    beatMs,
    firstBeatMs: 0,
    downbeat: 0,
    gridStable: true,
    key,
    keyConf: 0.8,
    loudness: -10,
    bars: { energy: fill(0.5), low: fill(0.5), mid: fill(0.3), onsets: fill(0.5) },
    phrases: [
      { bar: 0, kind: 'intro' },
      { bar: 16, kind: 'body' },
      { bar: 32, kind: 'drop' },
      { bar: 48, kind: 'outro' },
    ],
  }
}

const anA = track('a', A_MINOR)
const anB = track('b', E_MINOR)
const plans = plan(anA, anB, {
  type: 'bass',
  lengthSec: 16,
  cutSec: 16,
  tempoTolPct: 8,
  keyShift: true,
  rateA: 1,
  rateB: 1,
  linkedA: false,
  linkedB: false,
})

const input = (over: Partial<CardInput> = {}): CardInput => ({
  on: true,
  repeatOne: false,
  a: 'a',
  b: 'b',
  stateA: 'ready',
  stateB: 'ready',
  failed: false,
  next: { from: 'a', to: 'b', plan: plans[0], rank: 1, total: plans.length },
  anA,
  anB,
  rateA: 1,
  ...over,
})

function planOf(c: CardInput) {
  const card = cardFor(c)
  if (card.state !== 'plan') throw new Error(`ждали план, а тут ${card.state}`)
  return card
}

describe('cardFor', () => {
  it('план: вид, бит в бит, длина в секундах, место в топе, темп и тон', () => {
    expect(plans.length).toBeGreaterThan(0)
    const c = planOf(input())
    expect(c.kind).toBe(plans[0].kind)
    expect(c.sync).toBe(true)
    // 128 BPM: такт 1.875 с
    expect(c.sec).toBeCloseTo(plans[0].bars * 1.875, 1)
    expect([c.rank, c.total]).toEqual([1, plans.length])
    expect([c.tempoA, c.tempoB]).toEqual([128, 128])
    expect([c.keyA, c.keyB]).toEqual(['8A', '9A'])
    expect([c.outMs, c.inMs]).toEqual([plans[0].outMs, plans[0].inMs])
  })

  it('своя скорость A ×2 — переход вдвое короче в секундах', () => {
    expect(planOf(input({ rateA: 2 })).sec).toBeCloseTo(planOf(input()).sec / 2, 1)
  })

  it('тональность не найдена — прочерк', () => {
    expect(planOf(input({ anB: track('b', null) })).keyB).toBe('—')
  })

  it('порядок состояний: выкл → тишина → повтор → последний → провал → нет анализа', () => {
    expect(cardFor(input({ on: false })).state).toBe('off')
    expect(cardFor(input({ a: null, repeatOne: true })).state).toBe('idle')
    expect(cardFor(input({ repeatOne: true, b: null })).state).toBe('repeat')
    expect(cardFor(input({ b: null, failed: true })).state).toBe('last')
    expect(cardFor(input({ failed: true, stateB: 'failed' })).state).toBe('no-plan')
    expect(cardFor(input({ stateB: 'failed' })).state).toBe('no-analysis')
  })

  it('анализ ещё идёт — «считаю», готов без плана — «подбираю»', () => {
    expect(cardFor(input({ stateB: 'pending', next: null, anB: null })).state).toBe('counting')
    expect(cardFor(input({ stateA: 'none', next: null })).state).toBe('counting')
    expect(cardFor(input({ next: null })).state).toBe('waiting')
  })

  it('план чужой пары (очередь сменилась) не показывается', () => {
    const stale = input({ next: { from: 'a', to: 'c', plan: plans[0], rank: 1, total: 8 } })
    expect(cardFor(stale).state).toBe('waiting')
  })
})

describe('buttonLabel', () => {
  it('включено — короткое имя вида, выключено — пусто (значок)', () => {
    expect(buttonLabel(true, 'auto')).toBe('Авто')
    expect(buttonLabel(true, 'bass')).toBe('Бас')
    expect(buttonLabel(false, 'bass')).toBe('')
  })
})
