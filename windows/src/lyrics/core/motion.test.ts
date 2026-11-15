import { describe, expect, it } from 'vitest'
import { lineLook, lineOpacity, synthWords, wordLook } from './motion'

describe('lineOpacity (как в Dotify)', () => {
  it('текущая яркая, соседи тише, дальние ещё тише', () => {
    expect(lineOpacity(0, true, false)).toBe(1)
    expect(lineOpacity(1, true, false)).toBe(0.58)
    expect(lineOpacity(-1, true, false)).toBe(0.42)
    expect(lineOpacity(2, true, false)).toBe(0.4)
    expect(lineOpacity(-9, true, false)).toBe(0.16)
    expect(lineOpacity(3, false, false)).toBe(0.85)
  })
})

describe('lineLook', () => {
  it('обычный стиль и анимация — без трансформаций и размытия', () => {
    const l = lineLook('normal', 'normal', 2, true)
    expect(l.transform).toBe('none')
    expect(l.filter).toBe('none')
  })
  it('стиль «Размытие» не размывает текущую строку', () => {
    expect(lineLook('blur', 'normal', 0, true).filter).toBe('none')
    expect(lineLook('blur', 'normal', 1, true).filter).toBe('blur(2.5px)')
    expect(lineLook('blur', 'normal', 6, true).filter).toBe('blur(7px)')
  })
  it('без движения — только прозрачность', () => {
    const l = lineLook('scale', 'flip3d', 1, true, false, true)
    expect(l.transform).toBe('none')
    expect(l.filter).toBe('none')
  })
})

describe('wordLook', () => {
  it('будущие слова приглушены, прошедшие яркие', () => {
    expect(wordLook('fade', 0, false, false).opacity).toBe(0.52)
    expect(wordLook('fade', 1, true, false).opacity).toBe(1)
    expect(wordLook('normal', 0.5, false, true)).toEqual({})
  })
})

describe('synthWords', () => {
  it('делит время строки по длине слов', () => {
    const w = synthWords({ time: 10, duration: 4, text: 'раз два три', isBackground: false })
    expect(w.map((x) => x.text)).toEqual(['раз', 'два', 'три'])
    expect(w[0].time).toBe(10)
    expect(w[2].time + w[2].duration).toBeCloseTo(14)
    expect(w[2].hasSpaceAfter).toBe(false)
  })
})
