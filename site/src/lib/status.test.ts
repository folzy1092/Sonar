import { describe, expect, it } from 'vitest'
import {
  SERVICE_GROUPS,
  SONAR_ROWS,
  averageUptime,
  formatUptime,
  lastDays,
  minutesSince,
  parseHistory,
  parseStatus,
  uptimeState,
} from './status'
import type { HistoryDay } from './status'

const API_EXAMPLE = {
  state: 'degraded',
  title: 'Частичный сбой',
  uptime_30d: 99.87,
  listening_now: 3,
  listeners_24h: 7,
  users: 12,
  checked_at: 1_763_500_000_000,
  infra: [
    { id: 'api', name: 'API', icon: 'server', state: 'ok', ms: 42 },
    { id: 'bot', name: 'Бот', icon: 'bot', state: 'ok', ms: 120 },
  ],
  platforms: [{ id: 'yandex', name: 'Яндекс', icon: 'ym', state: 'degraded', ms: null }],
}

describe('parseStatus', () => {
  it('reads the API.md §9 response and merges infra with platforms', () => {
    const report = parseStatus(API_EXAMPLE)
    expect(report?.state).toBe('degraded')
    expect(report?.uptime30d).toBe(99.87)
    expect(report?.items.get('api')).toEqual({ id: 'api', state: 'ok', ms: 42 })
    expect(report?.items.get('yandex')?.state).toBe('degraded')
    expect(report?.people).toEqual({ online: 3, day: 7, users: 12 })
  })

  it('leaves people null when the server did not send them', () => {
    expect(parseStatus({ state: 'ok', checked_at: 1 })?.people).toEqual({ online: null, day: null, users: null })
  })

  it('returns null for a foreign or broken response', () => {
    expect(parseStatus(null)).toBeNull()
    expect(parseStatus({ state: 'great', checked_at: 1 })).toBeNull()
    expect(parseStatus({ state: 'ok' })).toBeNull()
  })

  it('drops items with unknown states instead of failing', () => {
    const report = parseStatus({ ...API_EXAMPLE, infra: [{ id: 'api', state: 'maybe' }, 'junk'] })
    expect(report?.items.has('api')).toBe(false)
    expect(report?.items.has('yandex')).toBe(true)
  })
})

describe('parseHistory', () => {
  it('keeps valid days and drops out-of-range percentages', () => {
    const days = parseHistory({
      days: [
        { date: '2026-11-17', items: { api: 100, bot: 101, site: 'x' } },
        { date: 7, items: {} },
      ],
    })
    expect(days).toEqual([{ date: '2026-11-17', items: { api: 100 } }])
  })

  it('returns an empty list for anything else', () => {
    expect(parseHistory(undefined)).toEqual([])
    expect(parseHistory({ days: 'no' })).toEqual([])
  })
})

describe('uptimeState', () => {
  it('colours a day by its uptime', () => {
    expect(uptimeState(100)).toBe('ok')
    expect(uptimeState(99.5)).toBe('ok')
    expect(uptimeState(97)).toBe('degraded')
    expect(uptimeState(80)).toBe('down')
    expect(uptimeState(undefined)).toBe('none')
    expect(uptimeState(null)).toBe('none')
  })
})

describe('lastDays', () => {
  it('returns 30 UTC dates ending today, oldest first', () => {
    const days = lastDays(Date.UTC(2026, 10, 18, 23, 59))
    expect(days).toHaveLength(30)
    expect(days[29]).toBe('2026-11-18')
    expect(days[0]).toBe('2026-10-20')
  })
})

describe('averageUptime', () => {
  it('averages only the days that have the service', () => {
    const history: HistoryDay[] = [
      { date: '2026-11-16', items: { api: 100 } },
      { date: '2026-11-17', items: { api: 98, bot: 100 } },
    ]
    expect(averageUptime(history, 'api')).toBe(99)
    expect(averageUptime(history, 'site')).toBeNull()
  })
})

describe('formatting', () => {
  it('formats uptime with the locale separator and never rounds up to 100', () => {
    expect(formatUptime(99.999, 'ru-RU')).toBe('99,99 %')
    expect(formatUptime(99.5, 'en-US')).toBe('99.50 %')
    expect(formatUptime(null, 'en-US')).toBe('—')
  })

  it('counts minutes since the check and clamps a clock ahead of the server', () => {
    expect(minutesSince(0, 5 * 60_000 + 59_000)).toBe(5)
    expect(minutesSince(10_000, 0)).toBe(0)
  })
})

describe('rows', () => {
  it('lists the four Sonar parts and every service group from SITE.md, with unique ids', () => {
    expect(SONAR_ROWS.map((r) => r.id)).toEqual(['api', 'bot', 'storage', 'site'])
    expect(SERVICE_GROUPS.map((g) => g.title)).toEqual(['Поиск и звук', 'Тексты', 'Другое', 'Только импорт'])
    const ids = [...SONAR_ROWS, ...SERVICE_GROUPS.flatMap((g) => g.rows)].map((r) => r.id)
    expect(new Set(ids).size).toBe(ids.length)
  })
})
