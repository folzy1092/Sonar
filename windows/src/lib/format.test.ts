import { describe, expect, it } from 'vitest'
import { compact, durationText, plural, tracksText } from './format'

describe('format', () => {
  it('склоняет', () => {
    expect(tracksText(1)).toBe('1 трек')
    expect(tracksText(3)).toBe('3 трека')
    expect(tracksText(11)).toBe('11 треков')
    expect(tracksText(217)).toBe('217 треков')
    expect(tracksText(22)).toBe('22 трека')
    expect(plural(0, ['a', 'b', 'c'])).toBe('c')
  })
  it('длительность', () => {
    expect(durationText(51 * 60_000)).toBe('51 мин')
    expect(durationText((6 * 60 + 51) * 60_000)).toBe('6 часов 51 мин')
    expect(durationText(2 * 3_600_000)).toBe('2 часа')
  })
  it('коротко числа', () => {
    expect(compact(337)).toBe('337')
    expect(compact(9400)).toBe('9.4K')
    expect(compact(773_600)).toBe('774K')
    expect(compact(1_600_000)).toBe('1.6M')
  })
})
