import { describe, expect, it, vi } from 'vitest'

vi.mock('./player.svelte', () => ({ player: {} }))
vi.mock('./my-wave.svelte', () => ({ wave: {} }))
vi.mock('../lib/api', () => ({ api: {} }))

const { stationTracks } = await import('./station')

const tr = (ref: string, available = true) =>
  ({ ref, title: ref, artist: 'a', artists: [], album: null, duration_ms: 1, cover_url: null, url: null, explicit: false, available, plays: null, tags: null }) as never

describe('stationTracks', () => {
  it('без самого трека, 👎, недоступных и повторов, порядок сохраняется', () => {
    const out = stationTracks(tr('sc:1'), [tr('sc:2'), tr('sc:1'), tr('sc:3'), tr('sc:2'), tr('sc:4', false), tr('sc:5')], (r) => r === 'sc:3')
    expect(out.map((t: { ref: string }) => t.ref)).toEqual(['sc:2', 'sc:5'])
  })
})
