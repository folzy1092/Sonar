import { describe, expect, it } from 'vitest'
import { profileHandle, readProfile } from './profile'

describe('readProfile', () => {
  it('reads a found profile', () => {
    const r = readProfile(200, { username: 'mira', display_name: ' Мира ', number: 7, created_at: 1_700_000_000_000 }, 'mira')
    expect(r).toEqual({
      kind: 'found',
      profile: { username: 'mira', displayName: 'Мира', number: 7, createdAt: 1_700_000_000_000 },
    })
    if (r.kind === 'found') expect(profileHandle(r.profile)).toBe('@mira · #7')
  })

  it('treats 404 as a missing profile', () => {
    expect(readProfile(404, { error: 'not_found' }, 'mira')).toEqual({ kind: 'missing' })
  })

  it('treats other statuses and junk bodies as an error', () => {
    expect(readProfile(500, {}, 'mira').kind).toBe('error')
    expect(readProfile(200, null, 'mira').kind).toBe('error')
    expect(readProfile(200, 'oops', 'mira').kind).toBe('error')
  })

  it('falls back on junk fields instead of breaking', () => {
    const r = readProfile(200, { display_name: '', number: -1, created_at: 'x' }, 'mira')
    expect(r).toEqual({ kind: 'found', profile: { username: 'mira', displayName: 'mira', number: null, createdAt: null } })
    if (r.kind === 'found') expect(profileHandle(r.profile)).toBe('@mira')
  })
})
