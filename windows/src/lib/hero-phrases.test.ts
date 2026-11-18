import { describe, expect, it } from 'vitest'
import { HERO_PHRASES, heroPhrase } from './hero-phrases'
import { drift, fieldValue, makeGrid, phaseAt, slime, SHAPES } from './sonar-field'

describe('фразы героя', () => {
  it('на каждую часть суток не меньше 6 фраз, без пустых', () => {
    for (const list of Object.values(HERO_PHRASES)) {
      expect(list.length).toBeGreaterThanOrEqual(6)
      for (const [a, b] of list) expect(a.trim() && b.trim()).toBeTruthy()
    }
  })

  it('за запуск фраза не прыгает', () => {
    const first = heroPhrase('evening', () => 0.99)
    expect(heroPhrase('evening', () => 0)).toBe(first)
    expect(first).toBe(HERO_PHRASES.evening[HERO_PHRASES.evening.length - 1])
  })
})

describe('поле точек', () => {
  it('фазы идут по кругу и перетекают плавно', () => {
    expect(phaseAt(0)).toEqual({ index: 0, k: 0 })
    const { k } = phaseAt(8)
    expect(k).toBeGreaterThan(0)
    expect(k).toBeLessThan(1)
    expect(phaseAt(-1).index).toBe(SHAPES.length - 1)
  })

  it('слизь плотная в центре капли и пустая далеко', () => {
    expect(slime(10, 10, 0, 2)).toBe(0)
    const values = [0, 1, 2, 3].map((t) => Math.max(...[-0.5, 0, 0.5].flatMap((x) => [-0.3, 0, 0.3].map((y) => slime(x, y, t, 2)))))
    expect(Math.max(...values)).toBeGreaterThan(0.5)
  })

  it('значения точек в 0…1, края пустые', () => {
    const g = makeGrid(300, 200, 10)
    for (let col = 0; col < g.cols; col += 3)
      for (let row = 0; row < g.rows; row += 3) {
        const v = fieldValue(col, row, g, null, 5, true)
        expect(v).toBeGreaterThanOrEqual(0)
        expect(v).toBeLessThanOrEqual(1)
      }
    expect(fieldValue(0, 0, g, null, 5, false)).toBeLessThan(0.05)
    expect(Math.abs(drift(3, 4, 2).dx)).toBeLessThanOrEqual(1.5)
  })
})
