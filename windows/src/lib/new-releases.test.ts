import { describe, expect, it, vi } from 'vitest'

vi.mock('./api', () => ({ api: {} }))
vi.mock('./settings.svelte', () => ({ settings: { get: () => true } }))
vi.mock('./toast.svelte', () => ({ toast: { show: () => {} } }))
vi.mock('./i18n.svelte', () => ({ t: (s: string) => s }))
vi.mock('../app/router.svelte', () => ({ openRef: () => {} }))
vi.mock('../player/player.svelte', () => ({ player: {} }))

import { isFresh, unseenFresh } from './new-releases.svelte'
import type { ReleaseItem } from './api'

const NOW = Date.parse('2026-11-22T12:00:00')
const item = (ref: string, released: string): ReleaseItem => ({ ref, kind: 'album', title: ref, artist: 'ШИПЫ', cover_url: null, released, track: null })

describe('новинки исполнителей', () => {
  it('свежее — за последнюю неделю, не из будущего', () => {
    expect(isFresh('2026-11-22', NOW)).toBe(true)
    expect(isFresh('2026-11-16', NOW)).toBe(true)
    expect(isFresh('2026-11-14', NOW)).toBe(false)
    expect(isFresh('2026-11-30', NOW)).toBe(false)
    expect(isFresh('мусор', NOW)).toBe(false)
  })

  it('в колокольчик — только свежее и ещё не виденное, порядок ленты сохраняется', () => {
    const feed = [item('a', '2026-11-21'), item('b', '2026-11-20'), item('c', '2026-11-01')]
    expect(unseenFresh(feed, new Set(['a']), NOW).map((i) => i.ref)).toEqual(['b'])
    expect(unseenFresh(feed, new Set(), NOW).map((i) => i.ref)).toEqual(['a', 'b'])
  })
})
