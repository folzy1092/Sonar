import { describe, expect, it } from 'vitest'
import { batchBytes, bytesText, fitToLimit, likedPlan, needsConfirm, progress, toDownload, trackBytes } from './downloads-core'

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

describe('fitToLimit', () => {
  // трек SoundCloud на 60 с — 1 200 000 байт
  const tr = (ref: string) => ({ ref, duration_ms: 60_000 })

  it('берёт по порядку, пока занятое плюс новое не больше лимита', () => {
    const got = fitToLimit([tr('sc:1'), tr('sc:2'), tr('sc:3')], 1_000_000, 3_500_000, 'max')
    expect(got.map((t) => t.ref)).toEqual(['sc:1', 'sc:2'])
  })

  it('лимит уже выбран — ничего, всё влезает — всё', () => {
    expect(fitToLimit([tr('sc:1')], 5_000_000, 5_000_000, 'max')).toEqual([])
    expect(fitToLimit([tr('sc:1'), tr('sc:2')], 0, 10_000_000, 'max')).toHaveLength(2)
  })

  it('крупный трек останавливает подбор: следующие мелкие не обгоняют свежий лайк', () => {
    const got = fitToLimit([tr('sc:1'), { ref: 'ym:big', duration_ms: 600_000 }, tr('sc:2')], 0, 3_000_000, 'max')
    expect(got.map((t) => t.ref)).toEqual(['sc:1'])
  })
})

describe('likedPlan', () => {
  // трек SoundCloud на 60 с — 1 200 000 байт
  const tr = (ref: string) => ({ ref, duration_ms: 60_000 })
  const liked = ['sc:a', 'sc:b', 'sc:c', 'sc:d'].map(tr)

  it('скачанное пропускает, стоящее в очереди считает занятым местом', () => {
    const got = likedPlan(liked, new Set(['sc:a']), new Set(['sc:b']), 1_200_000, 3_600_000, 'max')
    expect(got.map((t) => t.ref)).toEqual(['sc:c'])
  })

  it('only — только этот лайк, но с учётом очереди', () => {
    expect(likedPlan(liked, new Set(), new Set(['sc:a', 'sc:b']), 0, 3_600_000, 'max', 'sc:d').map((t) => t.ref)).toEqual(['sc:d'])
    expect(likedPlan(liked, new Set(), new Set(['sc:a', 'sc:b', 'sc:c']), 0, 3_600_000, 'max', 'sc:d')).toEqual([])
  })
})
