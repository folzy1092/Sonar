import { describe, expect, it } from 'vitest'
import { nextUpRise, nextUpSide } from './next-up'

describe('карточка «Дальше» у мини-плеера', () => {
  it('мини-плеер снизу (под карточкой и во всю ширину) — карточка над ним', () => {
    expect(nextUpSide('bottom', 0.86)).toBe('above')
    expect(nextUpSide('bottom_full', 0.86)).toBe('above')
  })

  it('мини-плеер сверху — карточка под ним', () => {
    expect(nextUpSide('top', 0.86)).toBe('below')
  })

  it('плавающий — по половине окна, где он висит', () => {
    expect(nextUpSide('floating', 0.86)).toBe('above')
    expect(nextUpSide('floating', 0.2)).toBe('below')
    expect(nextUpSide('floating', 0.5)).toBe('above')
  })

  it('выезжает от мини-плеера', () => {
    expect(nextUpRise('above')).toBe(8)
    expect(nextUpRise('below')).toBe(-8)
  })
})
