import { describe, expect, it } from 'vitest'
import {
  BEAT_PING,
  MAX_PINGS,
  PING_LIFE,
  PING_SPEED,
  TRACK_PING,
  addPing,
  dotRadius,
  pingValue,
  prunePings,
  stackPings,
  type Ping,
} from './sonar-ping'

const ping = (time = 10, strength = TRACK_PING): Ping => ({ time, strength })

describe('пинг сонара: кольцо от центра', () => {
  it('ярче всего на фронте кольца, по обе стороны гаснет', () => {
    const p = ping()
    const front = 0.5 * PING_SPEED
    const onFront = pingValue(p, front, 10.5)
    expect(onFront).toBeGreaterThan(0.3)
    expect(pingValue(p, front - 60, 10.5)).toBeLessThan(onFront * 0.2)
    expect(pingValue(p, front + 60, 10.5)).toBeLessThan(onFront * 0.2)
  })

  it('кольцо расходится: позже фронт дальше от центра', () => {
    const p = ping()
    expect(pingValue(p, 0.3 * PING_SPEED, 10.3)).toBeGreaterThan(pingValue(p, 0.3 * PING_SPEED, 10.8))
    expect(pingValue(p, 0.8 * PING_SPEED, 10.8)).toBeGreaterThan(pingValue(p, 0.8 * PING_SPEED, 10.3))
  })

  it('затухает к концу жизни и до своего времени молчит', () => {
    const p = ping()
    expect(pingValue(p, 0, 9.9)).toBe(0)
    expect(pingValue(p, PING_LIFE * PING_SPEED, 10 + PING_LIFE + 0.01)).toBe(0)
    const early = pingValue(p, 0.2 * PING_SPEED, 10.2)
    const late = pingValue(p, (PING_LIFE - 0.2) * PING_SPEED, 10 + PING_LIFE - 0.2)
    expect(late).toBeLessThan(early * 0.1)
  })

  it('бит слабее смены трека', () => {
    const d = 0.4 * PING_SPEED
    expect(pingValue(ping(10, BEAT_PING), d, 10.4)).toBeLessThan(pingValue(ping(10, TRACK_PING), d, 10.4))
  })

  it('несколько колец складываются, но не больше 1', () => {
    const pings = [ping(10), ping(10), ping(10)]
    expect(stackPings(pings, 0.4 * PING_SPEED, 10.4)).toBe(1)
    expect(stackPings([], 100, 10)).toBe(0)
  })
})

describe('пинг сонара: список колец', () => {
  it('отзвучавшие выкидываются, лишние — самые старые', () => {
    expect(prunePings([ping(1), ping(10)], 10.5)).toEqual([ping(10)])
    let pings: Ping[] = []
    for (let i = 0; i < MAX_PINGS + 3; i++) pings = addPing(pings, 10 + i * 0.01, BEAT_PING)
    expect(pings).toHaveLength(MAX_PINGS)
    expect(pings[0].time).toBeCloseTo(10 + 3 * 0.01)
  })

  it('addPing не меняет исходный список', () => {
    const before: Ping[] = [ping(10)]
    const after = addPing(before, 10.1, BEAT_PING)
    expect(before).toHaveLength(1)
    expect(after).toHaveLength(2)
  })
})

describe('радиус точки', () => {
  it('без музыки — доля шага по значению поля', () => {
    expect(dotRadius(10, 0, 0)).toBe(0)
    const full = dotRadius(10, 1, 0)
    expect(full).toBeGreaterThan(4)
    expect(full).toBeLessThan(5)
    expect(dotRadius(10, 0.5, 0)).toBeCloseTo(full / 2)
  })

  it('удар музыки надувает даже полные точки (значение поля упёрлось в 1)', () => {
    expect(dotRadius(10, 1, 1)).toBeGreaterThan(dotRadius(10, 1, 0) * 1.2)
  })

  it('значения за пределами 0…1 зажимаются', () => {
    expect(dotRadius(10, 2, 5)).toBe(dotRadius(10, 1, 1))
    expect(dotRadius(10, -1, -1)).toBe(0)
  })
})
