import { describe, expect, it } from 'vitest'
import { addFolder, hasArtist, isMissingLocal, removeFolder, servicesQuery } from './local'

const track = (over: Partial<{ ref: string; title: string; artist: string; available: boolean }> = {}) => ({
  ref: 'local:' + 'a'.repeat(40),
  title: 'Звезда',
  artist: 'Кино',
  available: true,
  ...over,
})

describe('isMissingLocal', () => {
  it('is true only for an unavailable local track', () => {
    expect(isMissingLocal(track({ available: false }))).toBe(true)
    expect(isMissingLocal(track())).toBe(false)
  })

  it('ignores unavailable tracks of streaming services', () => {
    expect(isMissingLocal(track({ ref: 'sc:1', available: false }))).toBe(false)
    expect(isMissingLocal(track({ ref: 'ym:1', available: false }))).toBe(false)
  })
})

describe('servicesQuery', () => {
  it('joins artist and title for the search box', () => {
    expect(servicesQuery(track())).toBe('Кино Звезда')
  })

  it('drops an empty artist and collapses spaces', () => {
    expect(servicesQuery(track({ artist: '', title: '  just  a title ' }))).toBe('just a title')
  })
})

describe('hasArtist', () => {
  it('treats blank artist as missing', () => {
    expect(hasArtist(track({ artist: '  ' }))).toBe(false)
    expect(hasArtist(track())).toBe(true)
  })
})

describe('addFolder', () => {
  it('appends a new folder without touching the old list', () => {
    const before = ['/music']
    expect(addFolder(before, ' /more ')).toEqual(['/music', '/more'])
    expect(before).toEqual(['/music'])
  })

  it('rejects blank paths and duplicates', () => {
    expect(addFolder(['/music'], '  ')).toBeNull()
    expect(addFolder(['/music'], '/music/')).toBeNull()
    expect(addFolder(['D:\\Music'], 'd:\\music\\')).toBeNull()
  })

  it('keeps case-sensitive unix paths distinct', () => {
    expect(addFolder(['/Music'], '/music')).toEqual(['/Music', '/music'])
  })
})

describe('removeFolder', () => {
  it('returns a new list without the folder', () => {
    const before = ['/a', '/b']
    expect(removeFolder(before, '/a')).toEqual(['/b'])
    expect(before).toEqual(['/a', '/b'])
  })
})
