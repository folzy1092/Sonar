import { describe, expect, test } from 'vitest'
import { findGroup, groupAlbums, groupArtists, groupId, parseGroupId } from './offline-groups'

const tr = (ref: string, artist: string, album: string | null, extra: { artists?: string[]; cover?: string } = {}) => ({
  ref,
  artist,
  artists: (extra.artists ?? [artist]).map((name) => ({ name, avatar_url: null })),
  album: album ? { title: album } : null,
  cover_url: extra.cover ?? null,
})

describe('groupAlbums', () => {
  test('один альбом из двух сервисов — одна группа, без альбома — мимо, больше треков выше', () => {
    const got = groupAlbums([
      tr('sc:1', 'Кино', 'Группа крови', { cover: 'c1' }),
      tr('ym:2', 'кино', 'группа крови'),
      tr('ym:3', 'Аквариум', 'Радио Африка'),
      tr('sc:4', 'Кино', null),
    ])
    expect(got.map((g) => [g.title, g.subtitle, g.tracks.map((t) => t.ref)])).toEqual([
      ['Группа крови', 'Кино', ['sc:1', 'ym:2']],
      ['Радио Африка', 'Аквариум', ['ym:3']],
    ])
    expect(got[0].cover).toBe('c1')
  })
})

describe('groupArtists', () => {
  test('фит попадает к каждому исполнителю, повтор имени — один раз', () => {
    const got = groupArtists([tr('1', 'A', null, { artists: ['A', 'B', 'a'] }), tr('2', 'B', 'X')])
    expect(got.map((g) => [g.title, g.tracks.map((t) => t.ref)])).toEqual([
      ['B', ['1', '2']],
      ['A', ['1']],
    ])
  })

  test('без списка исполнителей — по строке artist', () => {
    const got = groupArtists([{ ref: '1', artist: 'Solo', album: null }])
    expect(got.map((g) => g.title)).toEqual(['Solo'])
  })
})

describe('адрес группы', () => {
  test('туда и обратно, ключ с двоеточием цел', () => {
    const id = groupId('album', 'a:b|c')
    expect(parseGroupId(id)).toEqual({ kind: 'album', key: 'a:b|c' })
    expect(parseGroupId('pl_123')).toBeNull()
    expect(parseGroupId('offline:playlist:x')).toBeNull()
  })

  test('findGroup находит по адресу и молчит, если группы больше нет', () => {
    const tracks = [tr('1', 'Кино', 'Звезда'), tr('2', 'Кино', 'Звезда')]
    const [album] = groupAlbums(tracks)
    expect(findGroup(tracks, groupId('album', album.key))?.tracks).toHaveLength(2)
    expect(findGroup(tracks, groupId('artist', 'кино'))?.title).toBe('Кино')
    expect(findGroup(tracks, groupId('artist', 'нет такого'))).toBeNull()
  })
})
