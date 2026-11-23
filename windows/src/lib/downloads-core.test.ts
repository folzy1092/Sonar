import { describe, expect, it } from 'vitest'
import { batchBytes, bytesText, needsConfirm, progress, toDownload, trackBytes } from './downloads-core'

describe('trackBytes', () => {
  it('Яндекс считает по качеству, остальные — средним битрейтом', () => {
    // 60 с × 320 кбит/с = 2 400 000 байт
    expect(trackBytes({ ref: 'ym:1', duration_ms: 60_000 }, 'high')).toBe(2_400_000)
    expect(trackBytes({ ref: 'ym:1', duration_ms: 60_000 }, 'max')).toBe(7_500_000)
    expect(trackBytes({ ref: 'sc:1', duration_ms: 60_000 }, 'max')).toBe(1_200_000)
  })

  it('без длительности берёт среднюю песню', () => {
    expect(trackBytes({ ref: 'sc:1', duration_ms: 0 }, 'high')).toBe(trackBytes({ ref: 'sc:1', duration_ms: 210_000 }, 'high'))
  })
})

describe('needsConfirm', () => {
  it('спрашивает при больше 50 треков или больше 1 ГБ', () => {
    expect(needsConfirm(50, 100)).toBe(false)
    expect(needsConfirm(51, 100)).toBe(true)
    expect(needsConfirm(3, 1024 ** 3)).toBe(false)
    expect(needsConfirm(3, 1024 ** 3 + 1)).toBe(true)
  })

  it('пачка из 124 треков по 4 минуты во FLAC — спрашивает', () => {
    const tracks = Array.from({ length: 124 }, (_, i) => ({ ref: `ym:${i}`, duration_ms: 240_000 }))
    expect(needsConfirm(tracks.length, batchBytes(tracks, 'max'))).toBe(true)
  })
})

describe('toDownload', () => {
  it('выкидывает локальные, скачанные и повторы, порядок сохраняет', () => {
    const list = [{ ref: 'sc:1' }, { ref: 'local:a' }, { ref: 'ym:2' }, { ref: 'sc:1' }, { ref: 'ym:3' }]
    expect(toDownload(list, new Set(['ym:2'])).map((t) => t.ref)).toEqual(['sc:1', 'ym:3'])
  })
})

describe('progress', () => {
  it('доля готового, пусто — ноль', () => {
    expect(progress(0, 0)).toBe(0)
    expect(progress(3, 1)).toBe(0.75)
  })
})

describe('bytesText', () => {
  it('мегабайты до гигабайта, дальше гигабайты', () => {
    expect(bytesText(340 * 1024 ** 2)).toBe('340 МБ')
    expect(bytesText(100)).toBe('1 МБ')
    expect(bytesText(1.25 * 1024 ** 3)).toBe('1.3 ГБ')
  })
})
