import { describe, expect, it } from 'vitest'
import { adderOf, isCollab } from './collab'
import type { PlaylistMember } from './api'

const member = (username: string, avatar_url: string | null = null): PlaylistMember => ({ username, display_name: null, avatar_url })
const shared = { owner: member('folzy', 'https://img/f.jpg'), collaborators: [member('friend', 'https://img/b.jpg')] }
const solo = { owner: null, collaborators: [] }

describe('collab', () => {
  it('совместный — только когда есть соавтор', () => {
    expect(isCollab(shared)).toBe(true)
    expect(isCollab(solo)).toBe(false)
    expect(isCollab({ owner: member('folzy'), collaborators: [] })).toBe(false)
  })

  it('добавивший — участник с аватаром, владелец тоже', () => {
    expect(adderOf(shared, 'friend')?.avatar_url).toBe('https://img/b.jpg')
    expect(adderOf(shared, 'folzy')?.avatar_url).toBe('https://img/f.jpg')
  })

  it('вышедший из плейлиста — только ник; нет added_by или плейлист обычный — null', () => {
    expect(adderOf(shared, 'gone')).toEqual(member('gone'))
    expect(adderOf(shared, undefined)).toBeNull()
    expect(adderOf(solo, 'friend')).toBeNull()
  })
})
