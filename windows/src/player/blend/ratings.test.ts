import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const api = {
  blendRate: vi.fn(async () => {}),
  blendBalance: vi.fn(async () => ({ echo: -0.5 })),
}
vi.mock('../../lib/api', () => ({ api }))

const { blendRatings, RATE_WINDOW_MS } = await import('./ratings.svelte')

const done = { from: { ref: 'sc:1' }, to: { ref: 'ym:2' }, kind: 'echo' as const }

describe('оценки переходов', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    api.blendRate.mockClear()
    api.blendBalance.mockClear()
    blendRatings.close()
  })
  afterEach(() => vi.useRealTimers())

  it('вопрос висит 60 с после перехода и сам пропадает', () => {
    blendRatings.open(done)
    vi.advanceTimersByTime(RATE_WINDOW_MS - 1)
    expect(blendRatings.ask).toBe(done)
    vi.advanceTimersByTime(1)
    expect(blendRatings.ask).toBeNull()
  })

  it('ответ пишется один раз и обновляет перевес', async () => {
    blendRatings.open(done)
    await blendRatings.rate(-1)
    await blendRatings.rate(1)
    expect(api.blendRate).toHaveBeenCalledTimes(1)
    expect(api.blendRate).toHaveBeenCalledWith('sc:1', 'ym:2', 'echo', -1)
    expect(blendRatings.answer).toBe(-1)
    expect(blendRatings.balance).toEqual({ echo: -0.5 })
  })

  it('не записалось — можно ответить ещё раз', async () => {
    api.blendRate.mockRejectedValueOnce(new Error('db'))
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    blendRatings.open(done)
    await blendRatings.rate(1)
    expect(blendRatings.answer).toBeNull()
    await blendRatings.rate(1)
    expect(api.blendRate).toHaveBeenCalledTimes(2)
    warn.mockRestore()
  })

  it('новый переход сбрасывает ответ и окно', () => {
    blendRatings.open(done)
    vi.advanceTimersByTime(RATE_WINDOW_MS - 10)
    const next = { ...done, kind: 'bass' as const }
    blendRatings.open(next)
    vi.advanceTimersByTime(20)
    expect(blendRatings.ask).toBe(next)
    expect(blendRatings.answer).toBeNull()
  })

  it('без вопроса оценка не пишется', async () => {
    await blendRatings.rate(1)
    expect(api.blendRate).not.toHaveBeenCalled()
  })
})
