import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  clampIso,
  DeckChain,
  HP_REST_HZ,
  ISO_MAX_DB,
  ISO_MIN_DB,
  PITCH_XFADE_SEC,
  pitchRatioOf,
  pitchWanted,
} from './deck-chain'
import { FakeContext, FakeNode, FakeParam, FakeWorklet, installFakeWorklet, reaches } from './fake-audio'

function chainOn(ctx: FakeContext) {
  return new DeckChain(ctx as unknown as BaseAudioContext)
}
const node = (n: unknown) => n as FakeNode
const param = (p: unknown) => p as FakeParam
/** Узел тона цепочки (появляется после первого включения тона). */
const worklet = (c: DeckChain) => (c as unknown as { pitch: FakeWorklet | null }).pitch
const inner = (c: DeckChain) => c as unknown as { direct: GainNode; pitchGain: GainNode }

describe('цепочка дека в покое', () => {
  it('все узлы нейтральны: изолятор 0 дБ, фильтры за краями слышимого, эхо без посыла', () => {
    // Arrange
    const ctx = new FakeContext()
    // Act
    const c = chainOn(ctx)
    // Assert
    for (const b of Object.values(c.bands)) expect(param(b.gain).value).toBe(0)
    expect(c.bands.low.type).toBe('lowshelf')
    expect(c.bands.mid.type).toBe('peaking')
    expect(c.bands.high.type).toBe('highshelf')
    expect(param(c.hp.frequency).value).toBe(HP_REST_HZ)
    expect(param(c.lp.frequency).value).toBe(ctx.sampleRate / 2)
    expect(param(c.echoSend.gain).value).toBe(0)
    expect(param(c.feedback.gain).value).toBe(0)
    expect(param(c.gain.gain).value).toBe(1)
  })

  it('звук идёт от входа до выхода через изолятор и фильтры, тон отключён', () => {
    const c = chainOn(new FakeContext())
    const isWorklet = (n: FakeNode) => n.kind === 'worklet'
    expect(reaches(node(c.gain), node(c.output), isWorklet)).toBe(true)
    expect(reaches(node(c.gain), node(c.bands.high))).toBe(true)
    expect(reaches(node(c.bands.high), node(c.lp))).toBe(true)
    expect(worklet(c)).toBeNull()
  })

  it('эхо — петля через задержку рядом с основным путём, а не разрыв его', () => {
    const c = chainOn(new FakeContext())
    expect(reaches(node(c.feedback), node(c.delay))).toBe(true)
    expect(reaches(node(c.delay), node(c.output))).toBe(true)
    const viaEcho = (n: FakeNode) => n === node(c.echoSend)
    expect(reaches(node(c.lp), node(c.output), viaEcho)).toBe(true)
  })
})

describe('тон в цепочке дека', () => {
  beforeEach(() => {
    installFakeWorklet()
    vi.useFakeTimers()
  })
  afterEach(() => vi.useRealTimers())

  it('включается перекрытием 30 мс и стоит после изолятора', async () => {
    const c = chainOn(new FakeContext())
    await c.setUserPitch(1.122)
    const w = worklet(c)!
    expect(w.name).toBe('sonar-pitch')
    expect(w.parameters.get('ratio')!.target).toBeCloseTo(1.122)
    expect(reaches(node(c.lp), w)).toBe(true)
    expect(reaches(w, node(c.output))).toBe(true)
    expect(param(inner(c).direct.gain).target).toBe(0)
    const wet = param(inner(c).pitchGain.gain)
    expect(wet.target).toBe(1)
    expect(wet.until).toBeCloseTo(PITCH_XFADE_SEC)
  })

  it('тон 1 — перекрытие обратно, worklet отключается после него', async () => {
    const c = chainOn(new FakeContext())
    await c.setUserPitch(0.9)
    const w = worklet(c)!
    await c.setUserPitch(1)
    expect(param(inner(c).direct.gain).target).toBe(1)
    expect(reaches(node(c.lp), w)).toBe(true) // ещё звучит хвост перекрытия
    vi.advanceTimersByTime(PITCH_XFADE_SEC * 2000 + 1)
    expect(reaches(node(c.lp), w)).toBe(false)
  })

  it('повторное включение до конца перекрытия не даёт таймеру выключить тон', async () => {
    const c = chainOn(new FakeContext())
    await c.setUserPitch(0.9)
    const w = worklet(c)!
    await c.setUserPitch(1)
    await c.setUserPitch(1.2)
    vi.advanceTimersByTime(1000)
    expect(reaches(node(c.lp), w)).toBe(true)
  })

  it('сдвиг перехода умножается на тон пользователя', async () => {
    const c = chainOn(new FakeContext())
    await c.setUserPitch(1.1)
    await c.setShift(1 / 1.1)
    expect(worklet(c)!.parameters.get('ratio')!.target).toBeCloseTo(1)
    vi.advanceTimersByTime(1000)
    expect(reaches(node(c.lp), worklet(c)!)).toBe(false)
  })

  it('модуль worklet грузится в контекст один раз на все деки', async () => {
    const ctx = new FakeContext()
    await chainOn(ctx).setUserPitch(1.1)
    await chainOn(ctx).setUserPitch(0.9)
    expect(ctx.modules).toBe(1)
  })
})

describe('чистые расчёты цепочки', () => {
  it('изолятор держится в −40…+6 дБ', () => {
    expect(clampIso(-90)).toBe(ISO_MIN_DB)
    expect(clampIso(12)).toBe(ISO_MAX_DB)
    expect(clampIso(-3)).toBe(-3)
    expect(clampIso(Number.NaN)).toBe(0)
  })
  it('множитель тона и порог включения', () => {
    expect(pitchRatioOf(1.2, 0.5)).toBeCloseTo(0.6)
    expect(pitchRatioOf(Number.NaN, 1)).toBe(1)
    expect(pitchWanted(1.0005)).toBe(false)
    expect(pitchWanted(1.01)).toBe(true)
  })
})
