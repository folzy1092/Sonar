import { describe, expect, it } from 'vitest'
import type { Track } from './api'
import {
  buildState,
  likeNeedsToggle,
  parseCommand,
  queueIndexNow,
  QUEUE_LIMIT,
  shouldSend,
  STATE_REFRESH_MS,
  type PlayerSnapshot,
} from './remote-core'

const track = (ref: string, extra: Partial<Track> = {}): Track => ({
  ref,
  title: `Song ${ref}`,
  artist: 'Band',
  artists: [],
  album: null,
  duration_ms: 200_000,
  cover_url: null,
  url: null,
  explicit: false,
  available: true,
  ...extra,
})

const snap = (over: Partial<PlayerSnapshot> = {}): PlayerSnapshot => ({
  current: track('sc:1'),
  positionMs: 10_000,
  durationMs: 200_000,
  playing: true,
  volume: 0.8,
  repeat: 'off',
  shuffle: false,
  liked: false,
  upNext: [track('sc:2'), track('ym:3')],
  contextTitle: 'Любимые',
  ...over,
})

describe('buildState', () => {
  it('сводит плеер к состоянию для телефона', () => {
    const s = buildState(snap({ current: track('sc:1', { plays: 5, why: { kind: 'x' } as never }) }), 1000)
    expect(s.track).toEqual({ ...track('sc:1') })
    expect(s.track && 'plays' in s.track).toBe(false)
    expect(s.position_at).toBe(1000)
    expect(s.queue.map((t) => t.ref)).toEqual(['sc:2', 'ym:3'])
    expect(s.context_title).toBe('Любимые')
  })

  it('режет очередь до 50 и чинит числа', () => {
    const upNext = Array.from({ length: 80 }, (_, i) => track(`sc:${i}`))
    const s = buildState(snap({ upNext, volume: 3, positionMs: NaN, durationMs: 0 }), 0)
    expect(s.queue).toHaveLength(QUEUE_LIMIT)
    expect(s.volume).toBe(1)
    expect(s.position_ms).toBe(0)
    expect(s.duration_ms).toBe(200_000)
  })

  it('без трека — не играет', () => {
    const s = buildState(snap({ current: null, playing: true }), 0)
    expect(s.track).toBeNull()
    expect(s.playing).toBe(false)
  })
})

describe('shouldSend', () => {
  const sent = buildState(snap(), 0)

  it('первый раз и при изменении — сразу', () => {
    expect(shouldSend(sent, null, 0)).toBe(true)
    expect(shouldSend(buildState(snap({ playing: false }), 100), sent, 100)).toBe(true)
    expect(shouldSend(buildState(snap({ liked: true }), 100), sent, 100)).toBe(true)
  })

  it('обычное движение позиции не шлём, перемотку и раз в 5 с — шлём', () => {
    expect(shouldSend(buildState(snap({ positionMs: 11_000 }), 1000), sent, 1000)).toBe(false)
    expect(shouldSend(buildState(snap({ positionMs: 90_000 }), 1000), sent, 1000)).toBe(true)
    expect(shouldSend(buildState(snap({ positionMs: 15_000 }), STATE_REFRESH_MS), sent, STATE_REFRESH_MS)).toBe(true)
  })

  it('на паузе позиция стоит', () => {
    const paused = buildState(snap({ playing: false }), 0)
    expect(shouldSend(buildState(snap({ playing: false }), 3000), paused, 3000)).toBe(false)
  })
})

describe('parseCommand', () => {
  it('простые команды', () => {
    expect(parseCommand({ type: 'toggle' })).toEqual({ type: 'toggle' })
    expect(parseCommand({ type: 'seek', ms: 5000 })).toEqual({ type: 'seek', ms: 5000 })
    expect(parseCommand({ type: 'seek', ms: -1 })).toBeNull()
    expect(parseCommand({ type: 'volume', value: 2 })).toEqual({ type: 'volume', value: 1 })
    expect(parseCommand({ type: 'queue_play_index', index: 49 })).toEqual({ type: 'queue_play_index', index: 49 })
    expect(parseCommand({ type: 'queue_play_index', index: 50 })).toBeNull()
  })

  it('лайк, play и очередь', () => {
    expect(parseCommand({ type: 'like' })).toEqual({ type: 'like' })
    expect(parseCommand({ type: 'like', ref: 'sc:1', value: false })).toEqual({ type: 'like', ref: 'sc:1', value: false })
    expect(parseCommand({ type: 'play', wave: true })).toEqual({ type: 'play', wave: true })
    expect(parseCommand({ type: 'play', ref: 'ym:1' })).toEqual({ type: 'play', wave: false, ref: 'ym:1', track: undefined })
    const t = track('sc:9')
    expect(parseCommand({ type: 'queue_add', ref: 'sc:9', track: t, next: true })).toEqual({ type: 'queue_add', ref: 'sc:9', track: t, next: true })
    // трек с чужим ref не берём
    expect(parseCommand({ type: 'queue_add', ref: 'sc:9', track: track('sc:8') })).toEqual({ type: 'queue_add', ref: 'sc:9', track: undefined, next: false })
    expect(parseCommand({ type: 'play' })).toBeNull()
  })

  it('мусор — null', () => {
    for (const raw of [null, 'toggle', [], { type: 'dance' }, { type: 'queue_add' }]) expect(parseCommand(raw)).toBeNull()
  })
})

describe('queueIndexNow', () => {
  it('находит трек, даже если очередь сдвинулась', () => {
    expect(queueIndexNow(['a', 'b', 'c'], 1, ['a', 'b', 'c'])).toBe(1)
    expect(queueIndexNow(['a', 'b', 'c'], 2, ['b', 'c'])).toBe(1)
    expect(queueIndexNow(['a', 'b'], 0, ['b'])).toBeNull()
    expect(queueIndexNow(['a'], 5, ['a'])).toBeNull()
  })
})

it('лайк переключается только когда нужно', () => {
  expect(likeNeedsToggle(false, undefined)).toBe(true)
  expect(likeNeedsToggle(true, true)).toBe(false)
  expect(likeNeedsToggle(true, false)).toBe(true)
})
