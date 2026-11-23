// Контроллер сведения (docs/BLEND.md §6, §14) на поддельных деках: преролл и тихий старт B, A текущий до
// промоута, промоут без `load()`, пауза, перемотка, «Следующий», ошибка B, откат при поздней загрузке,
// фаза сходится, выключение не рвёт идущий переход.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { BlendAnalysis } from './analysis'
import type { ChainLike } from './automation'
import { BLEND_DEFAULTS, type BlendDeck, BlendController, type BlendSettings, type MediaLike } from './controller.svelte'
import { BEATS_PER_BAR, type Phrase } from './structure'

const STEP = 0.05
const NYQUIST = 24_000

/** `AudioParam` с таймлайном: что реально звучит в момент t. */
class TimelineParam {
  private events: { t: number; v: number; ramp: boolean }[] = []
  constructor(
    private readonly clock: () => number,
    private readonly initial: number,
  ) {}
  get value() {
    return this.at(this.clock())
  }
  cancelScheduledValues(t: number) {
    this.events = this.events.filter((e) => e.t < t)
  }
  setValueAtTime(v: number, t: number) {
    this.events.push({ t, v, ramp: false })
  }
  linearRampToValueAtTime(v: number, t: number) {
    this.events.push({ t, v, ramp: true })
  }
  at(t: number): number {
    let v = this.initial
    let prevT = 0
    for (const e of this.events) {
      if (e.t <= t) {
        v = e.v
        prevT = e.t
        continue
      }
      return e.ramp ? v + ((e.v - v) * (t - prevT)) / (e.t - prevT) : v
    }
    return v
  }
}

class FakeMedia implements MediaLike {
  currentTime = 0
  playbackRate = 1
  preservesPitch = true
  paused = true
  play() {
    this.paused = false
    return Promise.resolve()
  }
  pause() {
    this.paused = true
  }
}

interface Deck extends BlendDeck {
  el: FakeMedia
  gain: TimelineParam
  shift: number
}

const PHRASES: Phrase[] = [
  { bar: 0, kind: 'intro' },
  { bar: 16, kind: 'body' },
  { bar: 32, kind: 'drop' },
  { bar: 48, kind: 'outro' },
] as Phrase[]

function track(ref: string, bpm = 128, nBars = 64): BlendAnalysis {
  const beatMs = 60000 / bpm
  const endMs = nBars * BEATS_PER_BAR * beatMs
  const fill = (x: number) => Array.from({ length: nBars }, () => x)
  return {
    version: 1,
    ref,
    durationMs: endMs + 2000,
    startMs: 0,
    endMs,
    bpm,
    bpmConf: 0.9,
    beatMs,
    firstBeatMs: 0,
    downbeat: 0,
    gridStable: true,
    key: 0,
    keyConf: 0.8,
    loudness: -10,
    bars: { energy: fill(0.5), low: fill(0.5), mid: fill(0.3), onsets: fill(0.5) },
    phrases: PHRASES,
  } as unknown as BlendAnalysis
}

interface Track {
  ref: string
}

interface Setup {
  settings?: Partial<BlendSettings>
  loadDelaySec?: number
  bpmB?: number
}

function setup(over: Setup = {}) {
  let now = 0
  const clock = () => now
  const decks: Deck[] = []
  const makeDeck = (): Deck => {
    const p = (v: number) => new TimelineParam(clock, v) as unknown as AudioParam
    const gain = new TimelineParam(clock, 1)
    const deck = { el: new FakeMedia(), gain, shift: 1 } as Deck
    deck.chain = {
      gain: { gain: gain as unknown as AudioParam },
      bands: { low: { gain: p(0) }, mid: { gain: p(0) }, high: { gain: p(0) } },
      hp: { frequency: p(10), Q: p(Math.SQRT1_2) },
      lp: { frequency: p(NYQUIST) },
      echoSend: { gain: p(0) },
      feedback: { gain: p(0) },
      delay: { delayTime: p(0) },
      setUserPitch: async () => {},
      setShift: async (r: number) => {
        deck.shift = r
      },
    } satisfies ChainLike
    decks.push(deck)
    return deck
  }
  const analyses = new Map([
    ['a', track('a')],
    ['b', track('b', over.bpmB ?? 128)],
  ])
  const log = {
    promoted: [] as { deck: Deck; listenedMs: number }[],
    released: [] as Deck[],
    held: [] as boolean[],
    loads: 0,
  }
  const ctl = new BlendController<Track, Deck>({
    now: clock,
    nyquist: NYQUIST,
    settings: () => ({ ...BLEND_DEFAULTS, type: 'bass', ...over.settings }),
    analysis: (ref) => analyses.get(ref) ?? null,
    sound: async () => ({ rate: 1, pitch: 0, linked: false }),
    load: (_t, startSec) => {
      log.loads++
      const deck = makeDeck()
      deck.gain.setValueAtTime(0, now)
      deck.el.currentTime = startSec
      if (!over.loadDelaySec) return Promise.resolve(deck)
      return new Promise<Deck>((r) => setTimeout(() => r(deck), over.loadDelaySec! * 1000))
    },
    promote: (deck, listenedMs) => log.promoted.push({ deck, listenedMs }),
    release: (deck) => {
      deck.el.pause()
      log.released.push(deck)
    },
    hold: (on) => log.held.push(on),
  })
  const deckA = makeDeck()
  deckA.el.paused = false
  const durMs = analyses.get('a')!.durationMs
  let enabled = true
  let current: Deck = deckA

  const consider = () =>
    ctl.consider({
      a: { ref: 'a' },
      b: { ref: 'b' },
      deckA,
      posMs: deckA.el.currentTime * 1000,
      durMs,
      enabled,
      rateA: 1,
      linkedA: false,
    })

  /** Как плеер: шаг времени, `timeupdate` → `consider`, пока A текущий; потом таймеры контроллера. */
  async function advance(sec: number) {
    for (let i = 0; i < Math.round(sec / STEP); i++) {
      now += STEP
      for (const d of decks) if (!d.el.paused) d.el.currentTime += STEP * d.el.playbackRate
      if (current === deckA) consider()
      await vi.advanceTimersByTimeAsync(STEP * 1000)
      const last = log.promoted.at(-1)
      if (last) current = last.deck
    }
  }

  async function until(done: () => boolean, maxSec = 60) {
    for (let t = 0; !done(); t += STEP) {
      if (t > maxSec) throw new Error('не дождались')
      await advance(STEP)
    }
  }

  /** Встать на середину A, дождаться плана и промотать A к самому прероллу. */
  async function toPreroll() {
    deckA.el.currentTime = 60
    await advance(STEP)
    expect(ctl.phase).toBe('planned')
    while (ctl.phase === 'planned') {
      deckA.el.currentTime += 0.5
      await advance(STEP)
    }
    expect(ctl.phase).toBe('prerolling')
  }

  const deckB = () => decks[1] as Deck | undefined
  const bPlaying = () => !!deckB() && !deckB()!.el.paused

  return {
    ctl,
    deckA,
    deckB,
    bPlaying,
    log,
    advance,
    until,
    toPreroll,
    consider,
    clock,
    setEnabled: (v: boolean) => (enabled = v),
  }
}

beforeEach(() => vi.useFakeTimers())
afterEach(() => vi.useRealTimers())

describe('BlendController', () => {
  it('без анализа, на коротком треке, без B и с выключенным сведением — не берётся', () => {
    const s = setup()
    const base = {
      a: { ref: 'a' },
      b: { ref: 'b' },
      deckA: s.deckA,
      posMs: 0,
      durMs: 200_000,
      enabled: true,
      rateA: 1,
      linkedA: false,
    }
    expect(s.ctl.consider({ ...base, a: { ref: 'x' } })).toBe(false)
    expect(s.ctl.consider({ ...base, durMs: 30_000 })).toBe(false)
    expect(s.ctl.consider({ ...base, enabled: false })).toBe(false)
    expect(s.ctl.consider({ ...base, b: null })).toBe(false)
    expect(s.ctl.phase).toBe('idle')
  })

  it('преролл, B стартует молча, A текущий до конца, промоут без load(), потом всё в покое', async () => {
    const s = setup()
    await s.toPreroll()
    expect(s.log.held).toEqual([true])
    expect(s.log.loads).toBe(1)
    const plan = s.ctl.current!.plan
    expect(plan.kind).toBe('bass')
    let maxEarlyGain = 0
    await s.until(() => {
      const b = s.deckB()!
      if (s.bPlaying() && s.deckA.el.currentTime * 1000 < plan.outMs)
        maxEarlyGain = Math.max(maxEarlyGain, b.gain.at(s.clock()))
      return s.log.promoted.length > 0
    })
    // до начала перехода B уже играет (синк сходится), но не слышен
    expect(maxEarlyGain).toBeLessThan(0.05)
    expect(s.log.loads).toBe(1)
    const { deck, listenedMs } = s.log.promoted[0]
    expect(deck).toBe(s.deckB())
    expect(listenedMs).toBeGreaterThan(1000)
    expect(s.deckA.el.currentTime * 1000).toBeGreaterThanOrEqual(plan.endAMs - 60)
    await s.advance(1)
    expect(s.log.released).toContain(s.deckA)
    expect(s.deckA.el.paused).toBe(true)
    await s.advance(1)
    expect(s.ctl.phase).toBe('idle')
    expect(s.log.held).toEqual([true, false])
    expect(s.bPlaying()).toBe(true)
    expect(s.deckB()!.el.playbackRate).toBe(1)
    expect(s.deckB()!.gain.at(s.clock() + 5)).toBeCloseTo(1, 6)
    expect(s.deckB()!.shift).toBe(1)
  })

  it('фаза B сходится к сетке A после сдвига на 30 мс', async () => {
    const s = setup({ bpmB: 126 })
    await s.toPreroll()
    await s.until(s.bPlaying)
    await s.advance(0.5)
    s.deckB()!.el.currentTime += 0.03
    await s.advance(STEP)
    expect(s.ctl.phaseErrMs).toBeGreaterThan(20)
    await s.advance(3)
    expect(s.log.promoted).toHaveLength(0)
    expect(Math.abs(s.ctl.phaseErrMs)).toBeLessThanOrEqual(10)
  })

  it('ошибка фазы больше 120 мс — перемотка B, а не догонялки скоростью', async () => {
    const s = setup()
    await s.toPreroll()
    await s.until(s.bPlaying)
    s.deckB()!.el.currentTime += 0.5
    await s.advance(STEP)
    await s.advance(STEP)
    expect(Math.abs(s.ctl.phaseErrMs)).toBeLessThan(30)
  })

  it('пауза: B и часы перехода стоят; продолжение — B снова играет', async () => {
    const s = setup()
    await s.toPreroll()
    await s.until(s.bPlaying)
    s.deckA.el.pause()
    s.ctl.pause()
    const b = s.deckB()!
    expect(b.el.paused).toBe(true)
    const at = b.el.currentTime
    await s.advance(2)
    expect(b.el.currentTime).toBe(at)
    expect(s.log.promoted).toHaveLength(0)
    s.deckA.el.paused = false
    s.ctl.resume()
    await s.advance(STEP)
    expect(b.el.paused).toBe(false)
  })

  it('перемотка до промоута: B гаснет за 300 мс и освобождается, A снова на своей скорости', async () => {
    const s = setup({ bpmB: 124 })
    await s.toPreroll()
    await s.until(s.bPlaying)
    await s.advance(3)
    expect(s.deckA.el.playbackRate).not.toBe(1)
    s.ctl.cancel()
    expect(s.ctl.phase).toBe('idle')
    expect(s.log.held.at(-1)).toBe(false)
    expect(s.deckA.el.playbackRate).toBe(1)
    expect(s.deckA.gain.at(s.clock() + 0.3)).toBe(1)
    await vi.advanceTimersByTimeAsync(400)
    expect(s.log.released).toContain(s.deckB())
    expect(s.log.promoted).toHaveLength(0)
  })

  it('«Следующий» до старта B — обычное листание', async () => {
    const s = setup()
    await s.toPreroll()
    expect(s.ctl.finishNow()).toBe(false)
    expect(s.ctl.phase).toBe('idle')
    expect(s.log.promoted).toHaveLength(0)
  })

  it('«Следующий» при играющем B — сразу промоут, A гаснет за 300 мс', async () => {
    const s = setup()
    await s.toPreroll()
    await s.until(s.bPlaying)
    expect(s.ctl.finishNow()).toBe(true)
    expect(s.log.promoted).toHaveLength(1)
    expect(s.deckA.gain.at(s.clock() + 0.3)).toBeCloseTo(0, 9)
    await s.advance(0.5)
    expect(s.log.released).toContain(s.deckA)
  })

  it('«Следующий» после промоута — листаем дальше, abort() из load() сразу кладёт обе цепочки в покой', async () => {
    const s = setup({ settings: { type: 'echo' } })
    await s.toPreroll()
    await s.until(() => s.log.promoted.length > 0)
    expect(s.ctl.phase).toBe('promoting')
    expect(s.ctl.finishNow()).toBe(false)
    s.ctl.abort()
    expect(s.ctl.phase).toBe('idle')
    expect(s.log.released).toContain(s.deckA)
    expect(s.deckA.gain.at(s.clock())).toBe(1)
    expect(s.deckB()!.gain.at(s.clock())).toBe(1)
    expect(s.deckB()!.shift).toBe(1)
    expect(s.log.held).toEqual([true, false])
  })

  it('отложенное освобождение старого B не трогает дек нового преролла', async () => {
    const s = setup()
    await s.toPreroll()
    await s.until(s.bPlaying)
    const old = s.deckB()!
    s.ctl.cancel()
    s.ctl.abort()
    expect(s.log.released).not.toContain(old)
    s.deckA.el.currentTime = 60
    await s.advance(STEP)
    while (s.ctl.phase === 'planned') {
      s.deckA.el.currentTime += 0.5
      await s.advance(STEP)
    }
    expect(s.log.released).toEqual([old])
    await s.advance(1)
    expect(s.log.released).toEqual([old])
  })

  it('ошибка B до промоута: A доигрывает, эту пару больше не сводим', async () => {
    const s = setup()
    await s.toPreroll()
    await s.until(s.bPlaying)
    expect(s.ctl.onDeckError(s.deckB()!.el)).toBe(true)
    expect(s.ctl.phase).toBe('idle')
    expect(s.deckA.el.paused).toBe(false)
    expect(s.consider()).toBe(false)
  })

  it('B загрузился позже старта — откат на обычный кроссфейд', async () => {
    const s = setup({ loadDelaySec: 12 })
    await s.toPreroll()
    await s.until(() => s.ctl.phase === 'fallback')
    expect(s.log.promoted).toHaveLength(0)
    expect(s.log.held).toEqual([true, false])
    expect(s.log.released).toHaveLength(1)
    expect(s.consider()).toBe(false)
  })

  it('выключили сведение во время перехода — переход доигрывает', async () => {
    const s = setup()
    await s.toPreroll()
    await s.until(() => s.ctl.phase === 'running')
    s.setEnabled(false)
    await s.until(() => s.log.promoted.length > 0)
    expect(s.log.promoted).toHaveLength(1)
  })

  it('выключили сведение до старта B — план тихо забыт', async () => {
    const s = setup({ loadDelaySec: 5 })
    await s.toPreroll()
    s.setEnabled(false)
    await s.advance(STEP)
    expect(s.ctl.phase).toBe('idle')
    expect(s.log.held).toEqual([true, false])
  })
})
