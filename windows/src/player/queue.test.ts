import { describe, expect, it } from 'vitest'
import { countsAsPlay, dropUpcoming, enqueue, enqueueAt, fallbackSkipPos, makeOrder, nextPos, nextRepeat, prevPos } from './queue'

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

describe('fallbackSkipPos', () => {
  it('пропускает трек без потока дальше по очереди, повтор одного не держит', () => {
    expect(fallbackSkipPos(0, 3, 'off', 1)).toBe(1)
    expect(fallbackSkipPos(0, 3, 'one', 1)).toBe(1)
  })
  it('конец очереди без повтора — стоп', () => {
    expect(fallbackSkipPos(2, 3, 'off', 1)).toBeNull()
  })
  it('вся очередь без потока при повторе всех — стоп, а не круг', () => {
    expect(fallbackSkipPos(2, 3, 'all', 1)).toBe(0)
    expect(fallbackSkipPos(0, 3, 'all', 3)).toBeNull()
    expect(fallbackSkipPos(0, 1, 'all', 1)).toBeNull()
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

describe('enqueue', () => {
  it('ставит следующим после текущего', () => {
    expect(enqueue([0, 1, 2], 0, 3, true)).toEqual([0, 3, 1, 2])
  })
  it('в конец очереди', () => {
    expect(enqueue([2, 0, 1], 1, 3, false)).toEqual([2, 0, 1, 3])
  })
  it('пустая очередь — один трек', () => {
    expect(enqueue([], 0, 0, true)).toEqual([0])
  })
})

describe('enqueueAt и dropUpcoming (автоплей похожих)', () => {
  it('enqueueAt вставляет на место и не вылезает за края', () => {
    expect(enqueueAt([0, 1, 2], 2, 9)).toEqual([0, 1, 9, 2])
    expect(enqueueAt([0, 1], 10, 9)).toEqual([0, 1, 9])
  })
  it('dropUpcoming убирает только будущие подходящие и пересчитывает индексы', () => {
    const tracks = ['a', 'x1', 'b', 'x2', 'c']
    // порядок перемешан: c, x1 (сыграны), a (текущий), x2, b
    const order = [4, 1, 0, 3, 2]
    const out = dropUpcoming(tracks, order, 2, (t) => t.startsWith('x'))
    expect(out.tracks).toEqual(['a', 'x1', 'b', 'c'])
    expect(out.order.map((i) => out.tracks[i])).toEqual(['c', 'x1', 'a', 'b'])
  })
  it('keep оставляет ближайшие не игравшие и отдаёт убранные по порядку очереди', () => {
    const tracks = ['a', 'x1', 'x2', 'x3', 'x4']
    // текущий — a, дальше x3, x1, x4, x2
    const order = [0, 3, 1, 4, 2]
    const out = dropUpcoming(tracks, order, 0, (t) => t.startsWith('x'), 1)
    expect(out.dropped).toEqual(['x1', 'x4', 'x2'])
    expect(out.order.map((i) => out.tracks[i])).toEqual(['a', 'x3'])
  })
  it('нечего убирать — те же массивы', () => {
    const tracks = ['a', 'b']
    const order = [0, 1]
    const out = dropUpcoming(tracks, order, 0, () => false)
    expect(out.tracks).toBe(tracks)
    expect(out.order).toBe(order)
    expect(out.dropped).toEqual([])
  })
})
