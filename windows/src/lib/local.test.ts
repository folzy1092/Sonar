import { describe, expect, it } from 'vitest'
import { addFolder, hasArtist, isMissingLocal, playableQueue, removeFolder, servicesQuery } from './local'

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

describe('playableQueue', () => {
  const list = [
    track({ ref: 'sc:1' }),
    track({ ref: 'local:' + 'b'.repeat(40), available: false }),
    track({ ref: 'sc:3' }),
    track({ ref: 'ym:4', available: false }),
    track({ ref: 'local:' + 'e'.repeat(40), available: false }),
  ]
  const refs = (q: { tracks: { ref: string }[] }) => q.tracks.map((x) => x.ref)

  it('drops missing local files and keeps the started track in place', () => {
    const q = playableQueue(list, 2)
    expect(refs(q)).toEqual(['sc:1', 'sc:3', 'ym:4'])
    expect(q.index).toBe(1)
    expect(list).toHaveLength(5)
  })

  it('starts from the next playable track when the chosen one is missing', () => {
    expect(playableQueue(list, 1).index).toBe(1)
    expect(playableQueue(list, 4).index).toBe(2)
  })

  it('returns an empty queue when nothing can play', () => {
    expect(playableQueue([list[1], list[4]], 0)).toEqual({ tracks: [], index: 0 })
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
