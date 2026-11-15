import { describe, expect, it } from 'vitest'
import { notchPath } from './notch'

describe('notchPath (чёлка как у Dotify)', () => {
  it('радиусы не больше 14 px, угол карточки — не меньше внутреннего', () => {
    const { w, h, d } = notchPath(130, 36, 22)
    expect(w).toBe(144) // вырез + внутренний радиус 14
    expect(h).toBe(50) // высота + радиус выпуклого угла (22 → 14)
    expect(d.startsWith('M0,0 A14.0,14.0 0 0 1 14.0,14.0')).toBe(true)
    expect(d).toContain('V22.0') // 36 - 14
    expect(d.endsWith('V50.0 H0 Z')).toBe(true)
  })
  it('маленький островок — радиус не больше половины стороны', () => {
    const { w, d } = notchPath(20, 16, 0)
    expect(w).toBe(28)
    expect(d).toContain('A8.0,8.0')
  })
})
