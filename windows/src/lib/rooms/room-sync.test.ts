import { describe, expect, it } from 'vitest'
import { clockOffset, nudgeDuration, serverTime, SYNC_RATE, syncAction } from './room-sync'

describe('часы', () => {
  it('берёт пинг с минимальным RTT и середину пути', () => {
    // настоящие часы сервера = наши + 5000; второй пинг почти без задержки
    const est = clockOffset([
      { sent: 0, server: 5300, received: 400 },
      { sent: 1000, server: 6020, received: 1040 },
      { sent: 2000, server: 7150, received: 2200 },
    ])
    expect(est).toEqual({ offset_ms: 5000, rtt_ms: 40 })
    expect(serverTime(10_000, est)).toBe(15_000)
  })

  it('кривые пинги (ответ раньше запроса) и пусто — null', () => {
    expect(clockOffset([])).toBeNull()
    expect(clockOffset([{ sent: 10, server: 0, received: 5 }])).toBeNull()
    expect(serverTime(100, null)).toBe(100)
  })

  it('асимметричный путь даёт ошибку не больше половины RTT', () => {
    // туда 90 мс, обратно 10: сервер ответил в наши 90 → его часы 90 + 1000
    const est = clockOffset([{ sent: 0, server: 1090, received: 100 }])!
    expect(Math.abs(est.offset_ms - 1000)).toBeLessThanOrEqual(est.rtt_ms / 2)
  })
})

describe('подстройка слушателя', () => {
  const playing = (position_ms: number, at = 0) => ({ playing: true, anchor: { server_ts_ms: at, position_ms } })

  it('меньше 250 мс — не трогаем', () => {
    expect(syncAction(playing(0), 10_100, 10_000)).toEqual({ kind: 'none', drift_ms: -100 })
  })

  it('отстаём на секунду — чуть быстрее, спешим — чуть медленнее', () => {
    expect(syncAction(playing(0), 9000, 10_000)).toEqual({ kind: 'nudge', rate: 1 + SYNC_RATE, drift_ms: 1000 })
    expect(syncAction(playing(0), 11_000, 10_000)).toMatchObject({ kind: 'nudge', rate: 1 - SYNC_RATE })
    // секунду при 3 % догоняем примерно за 33 с — поэтому больше 2 с уже перематываем
    expect(nudgeDuration(1000)).toBe(33_333)
  })

  it('больше 2 с — перемотка на позицию лидера', () => {
    expect(syncAction(playing(5000), 1000, 10_000)).toEqual({ kind: 'seek', position_ms: 15_000, drift_ms: 14_000 })
  })

  it('на паузе — без подстройки скоростью, сразу на точку', () => {
    const paused = { playing: false, anchor: { server_ts_ms: 0, position_ms: 30_000 } }
    expect(syncAction(paused, 29_000, 99_000)).toEqual({ kind: 'seek', position_ms: 30_000, drift_ms: 1000 })
    expect(syncAction(paused, 30_100, 99_000).kind).toBe('none')
  })

  it('трек ещё не стартовал — ждём', () => {
    expect(syncAction(playing(0, 11_500), 0, 10_000)).toEqual({ kind: 'wait', start_in_ms: 1500 })
  })
})
