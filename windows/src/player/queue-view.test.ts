import { describe, expect, it } from 'vitest'
import type { Track } from '../lib/api'
import { growLimit, QUEUE_STEP, queueItems, queueView, type QueueSource } from './queue-view'

const tr = (ref: string): Track => ({
  ref,
  title: ref,
  artist: 'a',
  artists: [],
  album: null,
  duration_ms: 1000,
  cover_url: null,
  url: null,
  explicit: false,
  available: true,
})

const src = (over: Partial<QueueSource> = {}): QueueSource => {
  const tracks = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'].map(tr)
  return {
    tracks,
    order: tracks.map((_, i) => i),
    pos: 6,
    ids: tracks.map((_, i) => 100 + i),
    autoRefs: new Set(),
    ...over,
  }
}

const refs = (list: { track: Track }[]) => list.map((e) => e.track.ref)

describe('queueView', () => {
  it('«Ранее» — последние сыгранные (до 5), по порядку воспроизведения', () => {
    const view = queueView(src())
    expect(refs(view.earlier)).toEqual(['b', 'c', 'd', 'e', 'f'])
    expect(view.current?.track.ref).toBe('g')
    expect(refs(view.own)).toEqual(['h'])
  })

  it('в начале очереди «Ранее» пусто', () => {
    expect(queueView(src({ pos: 0 })).earlier).toEqual([])
  })

  it('размер «Ранее» настраивается', () => {
    expect(refs(queueView(src({ earlierSize: 3 })).earlier)).toEqual(['d', 'e', 'f'])
    expect(queueView(src({ earlierSize: 0 })).earlier).toEqual([])
  })

  it('id строки — стабильный id элемента очереди, а не позиция', () => {
    const before = queueView(src({ pos: 3 }))
    const after = queueView(src({ pos: 4 }))
    // трек «e» был в «Далее», стал текущим — id тот же, строка переедет
    expect(before.own[0]).toMatchObject({ id: 104, pos: 4 })
    expect(after.current).toMatchObject({ id: 104, pos: 4 })
    // бывший текущий «d» ушёл в «Ранее» с тем же id
    expect(after.earlier.at(-1)).toMatchObject({ id: 103 })
  })

  it('перемешивание: позиция — по order, id — по треку', () => {
    const view = queueView(src({ order: [2, 0, 1], tracks: ['a', 'b', 'c'].map(tr), ids: [7, 8, 9], pos: 1 }))
    expect(view.earlier).toEqual([{ id: 9, track: expect.objectContaining({ ref: 'c' }), pos: 0 }])
    expect(view.current).toMatchObject({ id: 7, pos: 1 })
    expect(view.own).toMatchObject([{ id: 8, pos: 2 }])
  })

  it('ids не той длины — id по индексу трека (очередь правили в обход player)', () => {
    const view = queueView(src({ ids: [1, 2], pos: 1 }))
    expect(view.current?.id).toBe(1)
    expect(view.earlier[0].id).toBe(0)
  })

  it('похожие автоплея — с первого такого трека после текущего', () => {
    const view = queueView(src({ pos: 2, autoRefs: new Set(['f', 'a']) }))
    expect(refs(view.own)).toEqual(['d', 'e'])
    expect(refs(view.auto)).toEqual(['f', 'g', 'h'])
  })

  it('пустая очередь', () => {
    const view = queueView(src({ tracks: [], order: [], ids: [], pos: 0 }))
    expect(view).toEqual({ earlier: [], current: null, own: [], auto: [] })
  })
})

describe('queueItems', () => {
  const keys = (items: { key: string }[]) => items.map((i) => i.key)

  it('разделы по порядку: Ранее, Сейчас, Далее, тумблер, похожие', () => {
    const view = queueView(src({ pos: 2, earlierSize: 1, autoRefs: new Set(['g']) }))
    expect(keys(queueItems(view, { autoSection: true, autoOn: true }))).toEqual([
      'h-earlier', 'e101', 'h-now', 'e102', 'h-next', 'e103', 'e104', 'e105', 'auto-switch', 'e106', 'e107',
    ])
  })

  it('без «Ранее» в начале и без тумблера в Sonar Mix', () => {
    const view = queueView(src({ pos: 0, tracks: [tr('a'), tr('b')], order: [0, 1], ids: [1, 2] }))
    expect(keys(queueItems(view, { autoSection: false, autoOn: false }))).toEqual(['h-now', 'e1', 'h-next', 'e2'])
  })

  it('«пусто» — только когда нечего играть и автоплей выключен', () => {
    const view = queueView(src({ pos: 7 }))
    expect(keys(queueItems(view, { autoSection: true, autoOn: false }))).toContain('empty')
    expect(keys(queueItems(view, { autoSection: true, autoOn: true }))).not.toContain('empty')
  })

  it('разделы у строк треков проставлены', () => {
    const view = queueView(src({ pos: 1, earlierSize: 1 }))
    const sections = queueItems(view, { autoSection: false, autoOn: false })
      .filter((i) => i.kind === 'track')
      .map((i) => (i.kind === 'track' ? i.section : ''))
    expect(sections).toEqual(['earlier', 'now', 'next', 'next', 'next', 'next', 'next', 'next'])
  })

  it('ключи уникальны', () => {
    const items = queueItems(queueView(src({ pos: 3, autoRefs: new Set(['f']) })), { autoSection: true, autoOn: false })
    expect(new Set(keys(items)).size).toBe(items.length)
  })

  it('длинная очередь — рисуются только первые `limit` треков после текущего, дальше строка «ещё»', () => {
    const view = queueView(src({ pos: 0 }))
    const items = queueItems(view, { autoSection: true, autoOn: true, limit: 3 })
    expect(keys(items)).toEqual(['h-now', 'e100', 'h-next', 'e101', 'e102', 'e103', 'more'])
  })

  it('окно доходит до похожих — тумблер и часть похожих видны, хвост — «ещё»', () => {
    const view = queueView(src({ pos: 2, earlierSize: 0, autoRefs: new Set(['f']) }))
    const items = queueItems(view, { autoSection: true, autoOn: true, limit: 3 })
    expect(keys(items)).toEqual(['h-now', 'e102', 'h-next', 'e103', 'e104', 'auto-switch', 'e105', 'more'])
  })

  it('всё влезло в окно — строки «ещё» нет', () => {
    const view = queueView(src({ pos: 2, autoRefs: new Set(['f']) }))
    expect(keys(queueItems(view, { autoSection: true, autoOn: true, limit: 5 }))).not.toContain('more')
  })
})

describe('growLimit', () => {
  it('добавляет шаг и не уходит за длину очереди', () => {
    expect(growLimit(60, 1000)).toBe(60 + QUEUE_STEP)
    expect(growLimit(60, 70)).toBe(70)
    expect(growLimit(80, 70)).toBe(80)
  })
})
