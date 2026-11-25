import { describe, expect, it } from 'vitest'
import { railPins } from './rail-pins'
import type { Playlist } from '../lib/api'

const pl = (id: string, updated_at: number, hidden = false): Playlist => ({
  id,
  name: id,
  hidden,
  source_ref: null,
  created_at: 0,
  updated_at,
  track_count: 0,
  duration_ms: 0,
  covers: [],
  tracks: null,
  owner: null,
  collaborators: [],
})

describe('плейлисты в панели Sonar', () => {
  it('свежие правки сверху, скрытых нет', () => {
    const got = railPins([pl('a', 1), pl('b', 3), pl('c', 2, true), pl('d', 2)])
    expect(got.map((p) => p.id)).toEqual(['b', 'd', 'a'])
  })

  it('не больше предела, исходный список не трогает', () => {
    const src = [pl('a', 1), pl('b', 2), pl('c', 3)]
    expect(railPins(src, 2).map((p) => p.id)).toEqual(['c', 'b'])
    expect(src.map((p) => p.id)).toEqual(['a', 'b', 'c'])
  })
})
