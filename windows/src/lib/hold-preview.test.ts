import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { HOLD_DELAY, HoldGate } from './hold-preview'

describe('HoldGate', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  const make = () => {
    const log: string[] = []
    const gate = new HoldGate({ onhold: () => log.push('hold'), onrelease: () => log.push('release') })
    return { gate, log }
  }

  it('короткий клик: предпросмотра нет, клик проходит', () => {
    const { gate, log } = make()
    gate.down()
    vi.advanceTimersByTime(HOLD_DELAY - 50)
    gate.up()
    expect(log).toEqual([])
    expect(gate.consumeClick()).toBe(false)
  })

  it('удержание: звучит предпросмотр, отпустил — возврат, клик съеден один раз', () => {
    const { gate, log } = make()
    gate.down()
    vi.advanceTimersByTime(HOLD_DELAY)
    expect(log).toEqual(['hold'])
    gate.up()
    expect(log).toEqual(['hold', 'release'])
    expect(gate.consumeClick()).toBe(true)
    expect(gate.consumeClick()).toBe(false)
  })

  it('ушёл с кнопки после удержания — всё равно вернулось; повторный up ничего не делает', () => {
    const { gate, log } = make()
    gate.down()
    vi.advanceTimersByTime(HOLD_DELAY + 10)
    gate.up()
    gate.up()
    expect(log).toEqual(['hold', 'release'])
  })

  it('новое нажатие сбрасывает прошлое удержание', () => {
    const { gate, log } = make()
    gate.down()
    vi.advanceTimersByTime(HOLD_DELAY)
    gate.up()
    gate.down()
    vi.advanceTimersByTime(10)
    gate.up()
    expect(gate.consumeClick()).toBe(false)
    expect(log).toEqual(['hold', 'release'])
  })

  it('задержка настраивается', () => {
    const log: string[] = []
    const gate = new HoldGate({ delay: 100, onhold: () => log.push('hold'), onrelease: () => log.push('release') })
    gate.down()
    vi.advanceTimersByTime(100)
    expect(log).toEqual(['hold'])
  })
})
