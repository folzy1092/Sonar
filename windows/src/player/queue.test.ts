import { describe, expect, it } from 'vitest'
import { countsAsPlay, makeOrder, nextPos, nextRepeat, prevPos } from './queue'

describe('makeOrder', () => {
  it('без перемешивания — по порядку', () => {
    expect(makeOrder(4, 2, false)).toEqual([0, 1, 2, 3])
  })
  it('перемешивание: текущий первым, все треки на месте', () => {
    const order = makeOrder(6, 3, true, () => 0.42)
    expect(order[0]).toBe(3)
    expect([...order].sort()).toEqual([0, 1, 2, 3, 4, 5])
  })
})

describe('nextPos', () => {
  it('идёт дальше и кончается без повтора', () => {
    expect(nextPos(0, 3, 'off', false)).toBe(1)
    expect(nextPos(2, 3, 'off', false)).toBeNull()
  })
  it('повтор всего — по кругу', () => {
    expect(nextPos(2, 3, 'all', false)).toBe(0)
  })
  it('повтор трека держит трек, но не кнопку «вперёд»', () => {
    expect(nextPos(1, 3, 'one', false)).toBe(1)
    expect(nextPos(1, 3, 'one', true)).toBe(2)
  })
  it('пустая очередь', () => {
    expect(nextPos(0, 0, 'all', true)).toBeNull()
  })
})

describe('prevPos', () => {
  it('назад и упор в начало', () => {
    expect(prevPos(2, 3, 'off')).toBe(1)
    expect(prevPos(0, 3, 'off')).toBe(0)
    expect(prevPos(0, 3, 'all')).toBe(2)
  })
})

describe('countsAsPlay', () => {
  it('30 секунд или половина короткого трека', () => {
    expect(countsAsPlay(29_000, 200_000)).toBe(false)
    expect(countsAsPlay(30_000, 200_000)).toBe(true)
    expect(countsAsPlay(20_000, 40_000)).toBe(true)
  })
})

it('повтор по кругу: выкл → всё → трек → выкл', () => {
  expect(nextRepeat('off')).toBe('all')
  expect(nextRepeat('all')).toBe('one')
  expect(nextRepeat('one')).toBe('off')
})
