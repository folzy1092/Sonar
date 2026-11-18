import { describe, expect, test } from 'vitest'
import { blurMask, drift, makeGrid, orb, play, POKE_LIFE, smooth, value, waves } from './field'

describe('поле точек героя', () => {
  test('сетка ровно по центру области', () => {
    const grid = makeGrid(100, 50, 8)
    expect(grid.cols).toBe(12)
    expect(grid.rows).toBe(6)
    expect(grid.originX).toBe(2)
    expect(grid.originY).toBe(1)
  })

  test('smooth зажат в 0…1 и гладкий на краях', () => {
    expect(smooth(-1)).toBe(0)
    expect(smooth(2)).toBe(1)
    expect(smooth(0.5)).toBe(0.5)
  })

  test('течение — не больше 1.5 px, размер 0.8…1', () => {
    for (let t = 0; t < 20; t += 0.7) {
      const d = drift(13, 7, t)
      expect(Math.abs(d.dx)).toBeLessThanOrEqual(1.5)
      expect(Math.abs(d.dy)).toBeLessThanOrEqual(1.5)
      expect(d.scale).toBeGreaterThanOrEqual(0.8)
      expect(d.scale).toBeLessThanOrEqual(1)
    }
  })

  test('касание: до прихода волны и после жизни точка на месте', () => {
    const poke = { x: 0, y: 0, time: 10, kind: 0 }
    expect(play(poke, 400, 0, 10.1)).toEqual({ dx: 0, dy: 0, scale: 1 })
    expect(play(poke, 10, 0, 10 + POKE_LIFE + 0.01)).toEqual({ dx: 0, dy: 0, scale: 1 })
    const moving = play(poke, 10, 0, 10.1)
    expect(moving.dx).not.toBe(0)
  })

  test('фигуры дают яркость 0…1', () => {
    for (let t = 0; t < 30; t += 1.3) {
      expect(orb(0, 0, t)).toBeGreaterThanOrEqual(0)
      expect(orb(0, 0, t)).toBeLessThanOrEqual(1)
      expect(orb(2, 2, t)).toBe(0)
      expect(waves(0, 0, 1.5, t)).toBeLessThanOrEqual(1)
    }
  })

  test('углы поля растворяются в ноль', () => {
    const grid = makeGrid(320, 320, 8)
    const logo = new Float32Array(grid.cols * grid.rows).fill(1)
    expect(value(0, 0, grid, logo, 0)).toBeLessThan(0.05)
    expect(value(grid.cols - 1, grid.rows - 1, grid, logo, 0)).toBeLessThan(0.05)
    expect(value(grid.cols / 2, grid.rows / 2, grid, logo, 0)).toBeGreaterThan(0.7)
  })

  test('размытие маски даёт мягкий край, но держит середину', () => {
    const hits = new Float32Array(25)
    hits[12] = 1
    const out = blurMask(hits, 5, 5)
    expect(out[12]).toBeCloseTo(Math.min(1, (4 / 12) * 1.25))
    expect(out[11]).toBeGreaterThan(0)
    expect(out[0]).toBe(0)
  })
})
