import { describe, expect, it } from 'vitest'
import type { Track } from './api'
import {
  EMPTY_IMPORT,
  applyProgress,
  fromResult,
  importSummary,
  importTracks,
  manualQuery,
  newJobId,
  progressShare,
  unreadCount,
  type ImportHead,
  type ImportState,
} from './import'

function track(ref: string, over: Partial<Track> = {}): Track {
  return {
    ref,
    title: `Song ${ref}`,
    artist: 'Artist',
    artists: [],
    album: null,
    duration_ms: 1000,
    cover_url: null,
    url: null,
    explicit: false,
    available: true,
    ...over,
  }
}

const head: ImportHead = {
  service: 'am',
  album: false,
  title: 'Hits',
  owner: 'Apple Music',
  cover_url: null,
  total: 5,
  source: 'https://music.apple.com/us/playlist/hits/pl.1',
}

const source = [track('am:1'), track('am:2'), track('am:3')]

function started(): ImportState {
  return applyProgress(EMPTY_IMPORT, { kind: 'head', job: 'j', head, tracks: source })
}

describe('applyProgress', () => {
  it('шапка задаёт треки, все ещё ищутся', () => {
    const s = started()
    expect(s.head).toEqual(head)
    expect(s.steps).toEqual([null, null, null])
    expect(importSummary(s)).toEqual({ checked: 0, matched: 0, total: 3, missing: [], done: false })
  })

  it('шаги приходят в любом порядке, прежнее состояние не меняется', () => {
    const a = started()
    const b = applyProgress(a, { kind: 'step', job: 'j', step: { index: 2, status: 'missing', track: null } })
    const c = applyProgress(b, { kind: 'step', job: 'j', step: { index: 0, status: 'found', track: track('ym:10') } })
    expect(a.steps).toEqual([null, null, null])
    expect(b.steps[2]?.status).toBe('missing')
    expect(importSummary(c)).toEqual({ checked: 2, matched: 1, total: 3, missing: [2], done: false })
  })

  it('шаг с чужим номером не ломает состояние', () => {
    const s = started()
    expect(applyProgress(s, { kind: 'step', job: 'j', step: { index: 9, status: 'kept', track: track('sc:1') } })).toBe(s)
  })
})

describe('итог', () => {
  const result = {
    head,
    tracks: source,
    steps: [
      { index: 0, status: 'found' as const, track: track('ym:10') },
      { index: 1, status: 'kept' as const, track: track('sc:5') },
      { index: 2, status: 'found' as const, track: track('ym:10') },
    ],
  }

  it('fromResult — всё проверено, «нашлось 3 из 3»', () => {
    const s = fromResult(result)
    expect(importSummary(s)).toEqual({ checked: 3, matched: 3, total: 3, missing: [], done: true })
    expect(progressShare(importSummary(s))).toBe(1)
  })

  it('треки плейлиста — по порядку источника, без повторов', () => {
    expect(importTracks(fromResult(result)).map((t) => t.ref)).toEqual(['ym:10', 'sc:5'])
  })

  it('ненайденные в плейлист не попадают', () => {
    const s = applyProgress(started(), { kind: 'step', job: 'j', step: { index: 1, status: 'missing', track: null } })
    expect(importTracks(s)).toEqual([])
  })

  it('Apple отдала не все треки — сколько не прочиталось', () => {
    expect(unreadCount(started())).toBe(2)
    expect(unreadCount(EMPTY_IMPORT)).toBe(0)
  })
})

describe('помощники', () => {
  it('запрос «Искать вручную» — исполнитель и название', () => {
    expect(manualQuery({ artist: ' Tate  McRae', title: 'Housewife ' })).toBe('Tate McRae Housewife')
  })

  it('доля прогресса', () => {
    expect(progressShare({ checked: 1, matched: 1, total: 4, missing: [], done: false })).toBe(0.25)
    expect(progressShare({ checked: 0, matched: 0, total: 0, missing: [], done: false })).toBe(0)
  })

  it('id задач не повторяются', () => {
    expect(newJobId(1)).not.toBe(newJobId(1))
  })
})
