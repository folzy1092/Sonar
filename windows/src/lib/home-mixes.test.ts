import { describe, expect, it } from 'vitest'
import type { Track } from './api'
import {
  artistsPreview,
  cleanSimilar,
  dayKey,
  dedupe,
  interleave,
  isFresh,
  isMixId,
  limitPerArtist,
  matchTracks,
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

describe('pickFromPools: случайные советы', () => {
  it('исполнителя, которого советует одна затравка, нет, если надёжных хватает', () => {
    // 6 затравок, у каждой — 8 общих исполнителей и свой «случайный»
    const shared = Array.from({ length: 8 }, (_, i) => `Shared${i}`)
    const pools = Array.from({ length: 6 }, (_, p) => [
      tr(`odd${p}`, `Odd${p}`),
      ...shared.map((a) => tr(`${a}-${p}`, a)),
    ])
    const out = pickFromPools(pools)
    expect(out.some((t) => t.artist.startsWith('Odd'))).toBe(false)
    expect(out.length).toBeGreaterThanOrEqual(12)
  })

  it('надёжных мало — одиночки идут добором после надёжных', () => {
    const pools = [
      [tr('x', 'Once'), tr('s1', 'Shared')],
      [tr('s2', 'Shared'), tr('y', 'Twice')],
    ]
    const out = pickFromPools(pools)
    expect(out.slice(0, 2).map((t) => t.artist)).toEqual(['Shared', 'Shared'])
    expect(out.map((t) => t.ref)).toContain('x')
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

describe('cleanSimilar', () => {
  const pop = (ref: string, plays: number, extra: Partial<Track> = {}) => tr(ref, `A${ref}`, { plays, duration_ms: 180_000, ...extra })

  it('склеивает перезаливы: то же название и длина ±2 с у разных исполнителей — остаётся первый', () => {
    const list = [
      pop('1', 900_000),
      tr('2', 'The Groove', { title: "Don't Look Any Further", duration_ms: 169_000, plays: 50_000 }),
      tr('3', 'Playerism', { title: "don't look  any further", duration_ms: 170_500, plays: 60_000 }),
      tr('4', 'Other', { title: "Don't Look Any Further", duration_ms: 240_000, plays: 70_000 }),
    ]
    expect(cleanSimilar(list, 0).map((t) => t.ref)).toEqual(['1', '2', '4'])
  })

  it('длину 0 не считает совпадением — без длины перезалив не угадать', () => {
    const list = [tr('1', 'X', { title: 'Song', duration_ms: 0 }), tr('2', 'Y', { title: 'Song', duration_ms: 0 })]
    expect(cleanSimilar(list, 0)).toHaveLength(2)
  })

  it('выкидывает почти не слушанное на фоне подборки, порядок сохраняет', () => {
    const list = [pop('1', 1_700_000), pop('2', 77_000), pop('3', 15), pop('4', 421_000), pop('5', 31), pop('6', 160_000)]
    expect(cleanSimilar(list, 0).map((t) => t.ref)).toEqual(['1', '2', '4', '6'])
  })

  it('треки без счётчика (Яндекс) не трогает', () => {
    const list = [pop('1', 500_000), pop('2', 400_000), tr('ym:3', 'Y', { title: 'ya', plays: undefined }), pop('4', 12)]
    expect(cleanSimilar(list, 0).map((t) => t.ref)).toEqual(['1', '2', 'ym:3'])
  })

  it('мало осталось — добирает лучшими из выкинутых, а не пустеет', () => {
    const list = [pop('1', 1_000_000), pop('2', 10), pop('3', 40), pop('4', 25)]
    expect(cleanSimilar(list, 3).map((t) => t.ref)).toEqual(['1', '3', '4'])
  })

  it('нишевая подборка, где у всех мало прослушиваний, остаётся целой', () => {
    const list = [pop('1', 300), pop('2', 150), pop('3', 220)]
    expect(cleanSimilar(list, 0).map((t) => t.ref)).toEqual(['1', '2', '3'])
  })
})
