import { describe, expect, it } from 'vitest'
import { levelFor, levelOf, mainArtist, prefList, trackKeys, withLevel, type ArtistPrefs } from './artist-prefs-core'

const tr = (artist: string, names: string[] = []) => ({ artist, artists: names.map((name, i) => ({ ref: `a:${i}`, name, avatar_url: null })) })

describe('trackKeys — зеркало wave.rs artist_keys', () => {
  it('совместный трек: имена из списка, главный первый, без повторов', () => {
    expect(trackKeys(tr('Oxxxymiron, Markul', ['Oxxxymiron', ' Markul ', 'markul']))).toEqual(['oxxxymiron', 'markul'])
  })
  it('списка нет — строка целиком, по запятым и & не режем', () => {
    expect(trackKeys(tr(' Tyler, The Creator '))).toEqual(['tyler, the creator'])
    expect(trackKeys(tr('Simon & Garfunkel'))).toEqual(['simon & garfunkel'])
  })
  it('главный артист для меню — первый непустой', () => {
    expect(mainArtist(tr('X', [' ', 'Markul']))).toEqual({ key: 'markul', name: 'Markul' })
    expect(mainArtist(tr(' Solo '))).toEqual({ key: 'solo', name: 'Solo' })
  })
})

describe('levelFor', () => {
  const prefs: ArtistPrefs = {
    a: { name: 'A', level: 'more' },
    b: { name: 'B', level: 'less' },
    n: { name: 'N', level: 'never' },
  }
  it('never любого соавтора главнее всего', () => {
    expect(levelFor(prefs, tr('', ['A', 'N']))).toBe('never')
  })
  it('more перебивает less, как Rust pref_of', () => {
    expect(levelFor(prefs, tr('', ['B', 'A']))).toBe('more')
    expect(levelFor(prefs, tr('', ['B']))).toBe('less')
  })
  it('нет записи или битая — ничего', () => {
    expect(levelFor(prefs, tr('Z'))).toBeNull()
    expect(levelFor({ z: { name: 'Z', level: 'meh' as never } }, tr('Z'))).toBeNull()
  })
})

describe('withLevel', () => {
  it('ставит по ключу в нижнем регистре и снимает null', () => {
    const p = withLevel({}, ' Markul ', 'more')
    expect(p).toEqual({ markul: { name: 'Markul', level: 'more' } })
    expect(levelOf(p, 'MARKUL')).toBe('more')
    expect(withLevel(p, 'markul', null)).toEqual({})
  })
  it('не меняет исходный словарь и пустое имя игнорирует', () => {
    const p = { a: { name: 'A', level: 'less' as const } }
    withLevel(p, 'A', 'never')
    expect(p.a.level).toBe('less')
    expect(withLevel(p, '  ', 'more')).toBe(p)
  })
})

describe('prefList', () => {
  it('по имени, с поиском, без битых записей', () => {
    const p = { b: { name: 'Beta', level: 'never' }, a: { name: 'alpha', level: 'more' }, x: { name: 'X', level: 'zzz' } } as never
    expect(prefList(p).map((e) => e.key)).toEqual(['a', 'b'])
    expect(prefList(p, 'BET').map((e) => e.key)).toEqual(['b'])
  })
})
