// Отладочная карточка (docs/BLEND.md §10.3): строка анализа и баллы плана.

import { describe, expect, it } from 'vitest'
import type { BlendAnalysis } from './analysis'
import { camelotName } from './camelot'
import { analysisLine, minus, scoreParts } from './debug-view'

describe('отладка сведения', () => {
  it('строка анализа: темп, уверенность, Camelot, громкость с настоящим минусом', () => {
    const a = { bpm: 128, bpmConf: 0.912, key: 21, keyConf: 0.34, loudness: -9.84 } as BlendAnalysis
    expect(analysisLine(a)).toBe(`128.0 BPM · 0.91 · ${camelotName(21)} · 0.34 · −9.8 LUFS`)
    expect(analysisLine({ ...a, key: null })).toBe('128.0 BPM · 0.91 · — · −9.8 LUFS')
  })

  it('минус без «−0»', () => {
    expect(minus(-0.01, 1)).toBe('0.0')
    expect(minus(6)).toBe('6')
    expect(minus(-12)).toBe('−12')
  })

  it('баллы — с весами, крупные первыми, нулевые скрыты', () => {
    const parts = { tempo: 0.9, key: 0.8, energy: 0.7, phrases: 1, cut: 0, vocal: 0.5, fit: 1, rating: -1 }
    const got = scoreParts(parts)
    expect(got[0]).toEqual({ part: 'tempo', value: '2.7' })
    expect(got.map((p) => p.part)).not.toContain('cut')
    expect(got.at(-1)).toEqual({ part: 'rating', value: '−0.5' })
  })
})
