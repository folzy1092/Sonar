import { describe, expect, it } from 'vitest'
import { dHash, hamming, pickByHash, SAME_MAX_BITS } from './cover-hash'

/** Яркости 9×8 из функции от координат. */
const img = (f: (x: number, y: number) => number) => Array.from({ length: 72 }, (_, i) => f(i % 9, Math.floor(i / 9)))

describe('dHash', () => {
  it('16 hex-символов, у одной картинки — один отпечаток', () => {
    const a = dHash(img((x, y) => (x * 37 + y * 11) % 255))
    expect(a).toMatch(/^[0-9a-f]{16}$/)
    expect(dHash(img((x, y) => (x * 37 + y * 11) % 255))).toBe(a)
  })

  it('та же картинка чуть светлее — почти тот же отпечаток, другая — далеко', () => {
    const base = (x: number, y: number) => Math.sin(x * 1.3 + y * 0.7) * 100 + 120
    const a = dHash(img(base))
    const lighter = dHash(img((x, y) => base(x, y) * 1.1 + 5))
    const other = dHash(img((x, y) => Math.cos(x * 0.4 - y * 1.9) * 100 + 120))
    expect(hamming(a, lighter)).toBeLessThanOrEqual(SAME_MAX_BITS)
    expect(hamming(a, other)).toBeGreaterThan(SAME_MAX_BITS)
  })
})

describe('pickByHash', () => {
  it('одинаковые картинки под разными адресами — одна, порядок сохраняется', () => {
    const h: Record<string, string> = { a: 'f0f0f0f0f0f0f0f0', b: 'f0f0f0f0f0f0f0f1', c: '0f0f0f0f0f0f0f0f', d: 'aaaaaaaaaaaaaaaa', e: '5555555555555555' }
    expect(pickByHash(['a', 'b', 'c', 'd', 'e'], (u) => h[u])).toEqual(['a', 'c', 'd', 'e'])
  })

  it('нет отпечатка или картинка однотонная — не считаем повтором', () => {
    const h: Record<string, string | null> = { a: '0000000000000000', b: '0000000000000000', c: null, d: null }
    expect(pickByHash(['a', 'b', 'c', 'd'], (u) => h[u])).toEqual(['a', 'b', 'c', 'd'])
  })
})
