import { describe, expect, it } from 'vitest'
import type { Track } from './api'
import {
  artistsPreview,
  dayKey,
  dedupe,
  interleave,
  isFresh,
  isMixId,
  limitPerArtist,
  matchTracks,
  mosaic,
  normName,
  parseSeed,
  pickFromPools,
  readCache,
  seedArtists,
  similarRow,
} from './home-mixes'

function tr(ref: string, artist: string, extra: Partial<Track> = {}): Track {
  return {
    ref,
    title: `t-${ref}`,
    artist,
    artists: [{ ref: `a:${artist}`, name: artist, avatar_url: null }],
    album: null,
    duration_ms: 1000,
    cover_url: `c-${ref}`,
    url: null,
    explicit: false,
    available: true,
    ...extra,
  }
}

describe('normName', () => {
  it('без регистра, лишних пробелов и ё', () => {
    expect(normName('  Пётр   Налич ')).toBe('петр налич')
  })
})

describe('dedupe', () => {
  it('убирает повтор ref и тот же трек с другого сервиса', () => {
    const a = tr('sc:1', 'X')
    const b = tr('ym:9', 'x', { title: 't-sc:1' })
    expect(dedupe([a, a, b, tr('sc:2', 'X')]).map((t) => t.ref)).toEqual(['sc:1', 'sc:2'])
  })
})

describe('limitPerArtist', () => {
  it('не больше N треков одного исполнителя, порядок сохраняется', () => {
    const list = [tr('1', 'A'), tr('2', 'A'), tr('3', 'B'), tr('4', 'A')]
    expect(limitPerArtist(list, 2).map((t) => t.ref)).toEqual(['1', '2', '3'])
    expect(limitPerArtist(list, 1).map((t) => t.ref)).toEqual(['1', '3'])
  })
})

describe('isFresh', () => {
  it('только при известном и малом счётчике', () => {
    expect(isFresh(tr('1', 'A', { plays: 1200 }))).toBe(true)
    expect(isFresh(tr('2', 'A', { plays: 2_000_000 }))).toBe(false)
    expect(isFresh(tr('3', 'A'))).toBe(false)
  })
})

describe('pickFromPools', () => {
  it('отсекает знакомых исполнителей, исключённые refs и недоступные треки', () => {
    const pools = [[tr('1', 'Known'), tr('2', 'New'), tr('3', 'Other', { available: false }), tr('4', 'Third')]]
    const out = pickFromPools(pools, { known: ['known'], exclude: ['4'] })
    expect(out.map((t) => t.ref)).toEqual(['2'])
  })

  it('выше — те, кого советуют несколько затравок', () => {
    const shared = tr('s', 'Shared')
    const pools = [
      [tr('a', 'A'), shared],
      [tr('b', 'B'), shared],
    ]
    expect(pickFromPools(pools)[0].ref).toBe('s')
  })

  it('соседи любимых по related поднимаются выше', () => {
    const pools = [[tr('a', 'A'), tr('b', 'B'), tr('n', 'Neighbour')]]
    const related = (name: string) => (name === 'Fav' ? ['neighbour'] : [])
    expect(pickFromPools(pools, { taste: ['Fav'], related })[0].ref).toBe('n')
    // без хука порядок как в пуле
    expect(pickFromPools(pools)[0].ref).toBe('a')
  })

  it('ограничение на исполнителя, фильтр и длина', () => {
    const pools = [[tr('1', 'A', { plays: 10 }), tr('2', 'A', { plays: 10 }), tr('3', 'A', { plays: 10 }), tr('4', 'B'), tr('5', 'C', { plays: 5 })]]
    const out = pickFromPools(pools, { maxPerArtist: 1, filter: (t) => isFresh(t) })
    expect(out.map((t) => t.ref)).toEqual(['1', '5'])
    expect(pickFromPools(pools, { limit: 2 })).toHaveLength(2)
  })
})

describe('artistsPreview', () => {
  it('2–3 исполнителя по частоте и «и ещё N»', () => {
    const list = [tr('1', 'A'), tr('2', 'B'), tr('3', 'B'), tr('4', 'C'), tr('5', 'D'), tr('6', 'E')]
    const p = artistsPreview(list, 3)
    expect(p.shown.map((a) => a.name)).toEqual(['B', 'A', 'C'])
    expect(p.more).toBe(2)
  })

  it('мало исполнителей — без «и ещё»', () => {
    expect(artistsPreview([tr('1', 'A')]).more).toBe(0)
  })

  it('берёт вариант с аватаркой и строку artist, если списка нет', () => {
    const a = tr('1', 'A')
    const b = { ...tr('2', 'A'), artists: [{ ref: 'a:A', name: 'A', avatar_url: 'img' }] }
    const bare = { ...tr('3', 'Solo'), artists: [] }
    const p = artistsPreview([a, b, bare])
    expect(p.shown[0].avatar_url).toBe('img')
    expect(p.shown[1].name).toBe('Solo')
  })
})

describe('mosaic', () => {
  it('до четырёх разных обложек', () => {
    const list = [tr('1', 'A'), tr('1b', 'A', { cover_url: 'c-1' }), tr('2', 'A', { cover_url: null }), tr('3', 'A'), tr('4', 'A'), tr('5', 'A')]
    expect(mosaic(list)).toEqual(['c-1', 'c-3', 'c-4', 'c-5'])
  })
})

describe('interleave', () => {
  it('по одному из каждого пула', () => {
    expect(interleave([[1, 2, 3], [4], [5, 6]])).toEqual([1, 4, 5, 2, 6, 3])
  })
})

describe('seedArtists', () => {
  it('разные исполнители из недавнего', () => {
    const out = seedArtists([tr('1', 'A'), tr('2', 'a'), tr('3', 'B'), tr('4', 'C'), tr('5', 'D')], 3)
    expect(out.map((x) => x.artist.name)).toEqual(['A', 'B', 'C'])
    expect(out[0].track.ref).toBe('1')
  })
})

describe('similarRow', () => {
  it('вперемешку из пулов, без слышанного, дублей и лишнего от одного исполнителя', () => {
    const pools = [
      [tr('1', 'A'), tr('2', 'A'), tr('3', 'A')],
      [tr('4', 'B'), tr('1', 'A'), tr('5', 'B', { available: false })],
    ]
    expect(similarRow(pools, ['4']).map((t) => t.ref)).toEqual(['1', '2'])
    expect(similarRow(pools, [], 2).map((t) => t.ref)).toEqual(['1', '4'])
  })

  it('соседи по карте исполнителей — первыми, порядок внутри тот же', () => {
    const pools = [[tr('1', 'A'), tr('2', 'C')], [tr('3', 'B'), tr('4', 'C')]]
    expect(similarRow(pools, [], 10, ['c']).map((t) => t.ref)).toEqual(['2', '4', '1', '3'])
  })
})

describe('matchTracks', () => {
  it('без запроса — все без повторов, с запросом — по названию и исполнителю', () => {
    const list = [tr('1', 'Ёлка'), tr('1', 'Ёлка'), tr('2', 'Other'), tr('3', 'Third', { title: 'Елочка' })]
    expect(matchTracks(list, '').map((t) => t.ref)).toEqual(['1', '2', '3'])
    expect(matchTracks(list, 'ёл').map((t) => t.ref)).toEqual(['1', '3'])
    expect(matchTracks(list, '', 1)).toHaveLength(1)
  })
})

describe('parseSeed', () => {
  it('битое значение — null', () => {
    expect(parseSeed(null)).toBeNull()
    expect(parseSeed('x')).toBeNull()
    expect(parseSeed({ ref: '', title: 'a' })).toBeNull()
  })
  it('нормальное — как есть', () => {
    expect(parseSeed({ ref: 'sc:1', title: 'T', artist: 'A', cover_url: 5 })).toEqual({ ref: 'sc:1', title: 'T', artist: 'A', cover_url: null })
  })
})

describe('isMixId', () => {
  it('знает свои подборки', () => {
    expect(isMixId('fresh')).toBe(true)
    expect(isMixId('wave')).toBe(false)
  })
})

describe('кэш на день', () => {
  const now = new Date(2026, 10, 18, 15)
  it('ключ дня — местная дата', () => {
    expect(dayKey(now)).toBe('2026-11-18')
  })
  it('сегодняшний кэш читается, вчерашний и битый — нет', () => {
    const raw = JSON.stringify({ day: '2026-11-18', seed: 'sc:1', new: [tr('1', 'A'), { bad: 1 }], fresh: [], like: 'x' })
    const c = readCache(raw, now)
    expect(c?.new.map((t) => t.ref)).toEqual(['1'])
    expect(c?.like).toEqual([])
    expect(readCache(raw, new Date(2026, 10, 19, 1))).toBeNull()
    expect(readCache('{oops', now)).toBeNull()
    expect(readCache(null, now)).toBeNull()
  })
})
