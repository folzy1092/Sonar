import { describe, expect, it } from 'vitest'
import type { DupeGroup, ListTrack } from './api'
import { dupeListOf, extraCount, initialMarks, keepOnly, keptIn, reasonOf, removalIds, toggleMark } from './dupes'

function item(item_id: string, ref: string, title = 'Song'): ListTrack {
  return {
    item_id,
    added_at: 0,
    ref,
    title,
    artist: 'A',
    artists: [],
    album: null,
    duration_ms: 100_000,
    cover_url: null,
    url: null,
    explicit: false,
    available: true,
  } as ListTrack
}

const g1: DupeGroup = { keep: 'ym', items: [item('ym', 'ym:1'), item('sc', 'sc:1'), item('sc2', 'sc:2', 'Song (prod. X)')] }
const g2: DupeGroup = { keep: 'b', items: [item('b', 'yt:1'), item('a', 'yt:1')] }

describe('список для поиска дублей', () => {
  it('принимает Любимые и свои плейлисты, остальное — нет', () => {
    expect(dupeListOf('favorites')).toBe('favorites')
    expect(dupeListOf('pl_abc')).toBe('pl_abc')
    for (const bad of [null, undefined, '', 'pl_', 'local', 'scpl:likes', 'ympl:1:3']) expect(dupeListOf(bad)).toBeNull()
  })
})

describe('почему дубль', () => {
  it('тот же ref, другой сервис, похожее название', () => {
    expect(reasonOf(g2.items[1], g2.items[0])).toBe('same')
    expect(reasonOf(g1.items[1], g1.items[0])).toBe('service')
    expect(reasonOf(g1.items[2], g1.items[1])).toBe('similar')
  })
})

describe('отметки', () => {
  it('по умолчанию отмечены все, кроме того, кого оставить', () => {
    // Arrange / Act
    const marks = initialMarks([g1, g2])
    // Assert
    expect([...marks].sort()).toEqual(['a', 'sc', 'sc2'])
    expect(keptIn(g1, marks)).toBe(1)
    expect(extraCount([g1, g2])).toBe(3)
  })

  it('последний оставленный в группе не отмечается, набор не мутируется', () => {
    const marks = initialMarks([g1])
    const same = toggleMark(marks, g1, 'ym')
    expect(same).toBe(marks)
    const unmarked = toggleMark(marks, g1, 'sc')
    expect(unmarked.has('sc')).toBe(false)
    expect(marks.has('sc')).toBe(true)
    const again = toggleMark(unmarked, g1, 'ym')
    expect(again.has('ym')).toBe(true)
    expect(keptIn(g1, again)).toBe(1)
  })

  it('чужой id не трогает отметки', () => {
    const marks = initialMarks([g1])
    expect(toggleMark(marks, g1, 'nope')).toBe(marks)
    expect(keepOnly(marks, g1, 'nope')).toBe(marks)
  })

  it('«оставить только этот» отмечает остальных в группе', () => {
    const marks = keepOnly(initialMarks([g1, g2]), g1, 'sc2')
    expect([...marks].sort()).toEqual(['a', 'sc', 'ym'])
  })

  it('что убрать — по порядку групп, без повторов и лишнего', () => {
    const marks = new Set(['sc2', 'a', 'sc', 'ghost'])
    expect(removalIds([g1, g2], marks)).toEqual(['sc', 'sc2', 'a'])
    expect(removalIds([], marks)).toEqual([])
  })
})
