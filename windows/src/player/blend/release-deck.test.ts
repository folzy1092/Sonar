// Дек после оборванного сведения не должен нести фильтр перехода следующему треку («играет за стенкой»),
// а опоздавшая загрузка B — лезть в дек, который плеер уже забрал под кроссфейд.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { restDeck, setDeck } from './automation'
import { DeckChain, HP_REST_HZ } from './deck-chain'
import { FakeContext, type FakeParam } from './fake-audio'

const streamUrl = vi.fn()
vi.mock('hls.js', () => ({ default: { Events: { ERROR: 'hlsError' } } }))
vi.mock('../../lib/api', () => ({ api: { streamUrl: (...a: unknown[]) => streamUrl(...a) } }))
vi.mock('../../lib/settings.svelte', () => ({ settings: { get: () => null } }))
vi.mock('../tempo.svelte', () => ({ tempo: { rate: 1, pitch: 0, linked: true, keep: false } }))
vi.mock('./ratings.svelte', () => ({ blendRatings: { balance: 0 } }))

const { createBlendHost } = await import('./player-host')

const param = (p: unknown) => p as FakeParam

/** Цепочка в середине фильтрового перехода: B глухой, эхо крутится, тон сдвинут. */
function dirtyChain(ctx: FakeContext) {
  const c = new DeckChain(ctx as unknown as BaseAudioContext)
  setDeck(c, { gain: 0.7, lpHz: 300, hpHz: 1200, low: -40, echoSend: 0.5, feedback: 0.6 }, 0)
  const shift = vi.spyOn(c, 'setShift').mockResolvedValue()
  return { c, shift }
}

function expectRest(c: DeckChain, ctx: FakeContext) {
  expect(param(c.gain.gain).value).toBe(0)
  expect(param(c.lp.frequency).value).toBe(ctx.sampleRate / 2)
  expect(param(c.hp.frequency).value).toBe(HP_REST_HZ)
  expect(param(c.bands.low.gain).value).toBe(0)
  expect(param(c.echoSend.gain).value).toBe(0)
  expect(param(c.feedback.gain).value).toBe(0)
}

function fakeEl() {
  return { pause: vi.fn(), removeAttribute: vi.fn(), load: vi.fn(), readyState: 4 } as unknown as HTMLAudioElement & {
    pause: ReturnType<typeof vi.fn>
  }
}

describe('restDeck', () => {
  it('глушит дек и возвращает фильтры, изолятор, эхо и тон в покой', () => {
    // Arrange
    const ctx = new FakeContext()
    const { c, shift } = dirtyChain(ctx)
    // Act
    restDeck(c, ctx.sampleRate / 2, 1)
    // Assert
    expectRest(c, ctx)
    expect(shift).toHaveBeenCalledWith(1)
  })
})

describe('хост сведения отпускает дек', () => {
  let ctx: FakeContext
  let other: HTMLAudioElement | null
  const side = () => ({
    ctx: () => ctx as unknown as AudioContext,
    otherDeck: () => other,
    chain: () => undefined,
    analysis: () => null,
    promote: () => null,
    hold: () => {},
    deckError: () => {},
    mount: vi.fn(() => null),
  })

  beforeEach(() => {
    ctx = new FakeContext()
    streamUrl.mockReset()
  })

  it('свободный дек: останавливает и приводит цепочку в покой', () => {
    // Arrange
    const el = fakeEl()
    other = el
    const { c } = dirtyChain(ctx)
    const host = createBlendHost(side())
    // Act
    host.release({ el, chain: c })
    // Assert
    expect(el.pause).toHaveBeenCalled()
    expectRest(c, ctx)
  })

  it('дек уже играет у плеера: не останавливает и ручки не трогает', () => {
    // Arrange
    const el = fakeEl()
    other = fakeEl()
    const { c } = dirtyChain(ctx)
    const host = createBlendHost(side())
    // Act
    host.release({ el, chain: c })
    // Assert
    expect(el.pause).not.toHaveBeenCalled()
    expect(param(c.gain.gain).value).toBe(0.7)
  })

  it('плеер забрал дек, пока B грузился: поток B в него не монтируется', async () => {
    // Arrange
    const el = fakeEl()
    other = el
    const { c } = dirtyChain(ctx)
    const s = { ...side(), chain: () => c }
    let resolve!: (v: unknown) => void
    streamUrl.mockReturnValue(new Promise((r) => (resolve = r)))
    const host = createBlendHost(s)
    // Act
    const pending = host.load({ ref: 'sc:1' } as never, 10)
    other = fakeEl() // обычный кроссфейд сделал этот дек текущим
    resolve({ url: 'x', kind: 'file' })
    const deck = await pending
    // Assert
    expect(deck).toBeNull()
    expect(s.mount).not.toHaveBeenCalled()
    expect(el.pause).not.toHaveBeenCalled()
  })
})
