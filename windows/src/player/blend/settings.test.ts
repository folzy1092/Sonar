import { describe, expect, it } from 'vitest'
import { applyMode, blendSettings, transitionMode } from './settings'

const keys = (over: Partial<Record<'type' | 'length' | 'cut' | 'tempo' | 'key', unknown>> = {}) => ({
  type: 'auto',
  length: 10,
  cut: 16,
  tempo: 8,
  key: true,
  ...over,
})

describe('blendSettings', () => {
  it('значения по умолчанию совпадают с §7.3', () => {
    expect(blendSettings(keys())).toEqual({ type: 'auto', lengthSec: 10, cutSec: 16, tempoTolPct: 8, keyShift: true })
  })

  it('битые и старые значения не ломают планировщик', () => {
    const s = blendSettings(keys({ type: 'wobble', length: 12, cut: 99, tempo: -3, key: 'да' }))
    expect(s).toEqual({ type: 'auto', lengthSec: 10, cutSec: 45, tempoTolPct: 0, keyShift: true })
  })

  it('длина — ближайшая из трёх', () => {
    expect(blendSettings(keys({ length: 7 })).lengthSec).toBe(6)
    expect(blendSettings(keys({ length: 20 })).lengthSec).toBe(16)
    expect(blendSettings(keys({ length: NaN })).lengthSec).toBe(10)
  })

  it('тональность выключается только явным false', () => {
    expect(blendSettings(keys({ key: false })).keyShift).toBe(false)
    expect(blendSettings(keys({ key: undefined })).keyShift).toBe(true)
  })
})

describe('переход между треками', () => {
  it('режим читается из сведения и длины кроссфейда', () => {
    expect(transitionMode(false, 0)).toBe('normal')
    expect(transitionMode(false, 6)).toBe('crossfade')
    expect(transitionMode(true, 0)).toBe('blend')
    expect(transitionMode(true, 4)).toBe('blend')
  })

  it('сведение не обнуляет длину кроссфейда-подстраховки', () => {
    expect(applyMode('blend', 4)).toEqual({ blend: true, crossfade: 4 })
    expect(applyMode('blend', 0)).toEqual({ blend: true, crossfade: 0 })
  })

  it('кроссфейд без длины берёт 6 с, с длиной — оставляет её', () => {
    expect(applyMode('crossfade', 0)).toEqual({ blend: false, crossfade: 6 })
    expect(applyMode('crossfade', 9)).toEqual({ blend: false, crossfade: 9 })
  })

  it('обычный выключает и сведение, и кроссфейд', () => {
    expect(applyMode('normal', 9)).toEqual({ blend: false, crossfade: 0 })
  })

  it('выбор и чтение режима сходятся', () => {
    for (const mode of ['normal', 'crossfade', 'blend'] as const) {
      const r = applyMode(mode, 0)
      expect(transitionMode(r.blend, r.crossfade)).toBe(mode)
    }
  })
})
