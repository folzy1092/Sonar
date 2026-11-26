import { describe, expect, it } from 'vitest'
import { BATCH_PAUSE_MS, BATCH_SIZE, batches, canBackfill, mergeMissing, needsBackfill, planQueue, settledRefs } from './track-backfill'

const card = (ref: string, cover_url: string | null = null, duration_ms = 0) => ({ ref, cover_url, duration_ms, title: 'из Dotify' })

describe('track-backfill', () => {
  it('constants match the iPhone', () => {
    expect(BATCH_SIZE).toBe(20)
    expect(BATCH_PAUSE_MS).toBe(1500)
  })

  it('backfills only soundcloud and yandex refs', () => {
    expect(canBackfill('sc:1')).toBe(true)
    expect(canBackfill('ym:5:77')).toBe(true)
    for (const r of ['sc:', 'yt:abc', 'local:1', 'vk:1_2', 'sp:x']) expect(canBackfill(r)).toBe(false)
  })

  it('needs backfill when cover is empty or duration is not positive', () => {
    expect(needsBackfill(card('sc:1', null, 1000))).toBe(true)
    expect(needsBackfill(card('sc:1', '', 1000))).toBe(true)
    expect(needsBackfill(card('sc:1', 'https://c', 0))).toBe(true)
    expect(needsBackfill(card('sc:1', 'https://c', -5))).toBe(true)
    expect(needsBackfill({ ref: 'sc:1', cover_url: 'https://c' })).toBe(true)
    expect(needsBackfill(card('sc:1', 'https://c', 1000))).toBe(false)
  })

  it('merge takes only missing fields and keeps the rest', () => {
    const fresh = { ...card('sc:1', 'https://new', 90_000), title: 'Другое' }
    expect(mergeMissing(card('sc:1'), fresh)).toEqual({ ...card('sc:1', 'https://new', 90_000) })
    expect(mergeMissing(card('sc:1', 'https://old', 0), fresh)).toEqual(card('sc:1', 'https://old', 90_000))
    expect(mergeMissing(card('sc:1', null, 5), fresh)).toEqual(card('sc:1', 'https://new', 5))
  })

  it('merge returns the same object when nothing to add', () => {
    const old = card('sc:1', 'https://old', 5)
    expect(mergeMissing(old, card('sc:1', 'https://new', 90_000))).toBe(old)
    const bare = card('sc:1')
    expect(mergeMissing(bare, card('sc:1', '', 0))).toBe(bare)
  })

  it('merge does not mutate the old card', () => {
    const old = card('sc:1')
    mergeMissing(old, card('sc:1', 'https://new', 1))
    expect(old).toEqual(card('sc:1'))
  })

  it('queue puts current first, dedupes and skips full, foreign and settled refs', () => {
    const list = [card('sc:1'), card('ym:2', 'https://c', 100), card('yt:3'), card('sc:4'), card('sc:1'), card('ym:5')]
    expect(planQueue(list, { current: card('sc:4'), skip: new Set(['ym:5']) })).toEqual(['sc:4', 'sc:1'])
    expect(planQueue(list)).toEqual(['sc:1', 'sc:4', 'ym:5'])
    expect(planQueue(list, { current: card('ym:2', 'https://c', 100) })).toEqual(['sc:1', 'sc:4', 'ym:5'])
  })

  it('splits refs into batches of 20', () => {
    const refs = Array.from({ length: 45 }, (_, i) => `sc:${i}`)
    expect(batches(refs).map((b) => b.length)).toEqual([20, 20, 5])
    expect(batches([])).toEqual([])
  })

  it('remembers everything asked except failed', () => {
    expect(settledRefs(['sc:1', 'sc:2', 'ym:3'], ['ym:3'])).toEqual(['sc:1', 'sc:2'])
  })
})
