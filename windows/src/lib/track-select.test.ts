import { describe, expect, it } from 'vitest'
import { pickSelected, rangeKeys, selKey, shareText, toggleKey } from './track-select'

const row = (ref: string, item_id?: string, artist = 'A', title = 'T') => ({ ref, item_id, artist, title })

describe('track-select', () => {
  it('ключ строки — item_id, без него ref', () => {
    expect(selKey(row('sc:1', 'it_9'))).toBe('it_9')
    expect(selKey(row('sc:1'))).toBe('sc:1')
  })

  it('toggleKey не меняет исходный набор', () => {
    const a = new Set(['x'])
    const b = toggleKey(a, 'y')
    expect([...a]).toEqual(['x'])
    expect([...b].sort()).toEqual(['x', 'y'])
    expect([...toggleKey(b, 'x')]).toEqual(['y'])
  })

  it('rangeKeys: в любую сторону и в пределах списка', () => {
    const keys = ['a', 'b', 'c', 'd', 'e']
    expect(rangeKeys(keys, 1, 3)).toEqual(['b', 'c', 'd'])
    expect(rangeKeys(keys, 3, 1)).toEqual(['b', 'c', 'd'])
    expect(rangeKeys(keys, 4, 99)).toEqual(['e'])
    expect(rangeKeys(keys, -3, 1)).toEqual(['a', 'b'])
  })

  it('pickSelected: порядок списка, чужие отметки отбрасываются', () => {
    const list = [row('sc:1', 'i1'), row('sc:2', 'i2'), row('sc:3', 'i3')]
    expect(pickSelected(list, new Set(['i3', 'i1', 'gone'])).map((x) => x.ref)).toEqual(['sc:1', 'sc:3'])
    expect(pickSelected(list, new Set())).toEqual([])
  })

  it('shareText: название, пустая строка, «Артист — Название»; без артиста — одно название', () => {
    expect(shareText('Любимые', [row('a', undefined, 'Lil Peep', 'Star Shopping'), row('b', undefined, ' ', 'Solo')])).toBe(
      'Любимые\n\nLil Peep — Star Shopping\nSolo',
    )
  })
})
