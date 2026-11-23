import { describe, expect, it } from 'vitest'
import { ownSound } from './player-host'

const cur = { rate: 0.85, pitch: -2, linked: false }

describe('ownSound — свой звук B так, как его применит tempo.trackChanged', () => {
  it('«Для этого трека» сохранён — берём его', () => {
    const s = { rate: 1.1, pitch: 1, linked: true, reverb: 0, eq: null }
    expect(ownSound(s as never, false, cur)).toEqual({ rate: 1.1, pitch: 1, linked: true })
  })

  it('без своего звука и без «Запомнить» — нейтраль, связь тона остаётся', () => {
    expect(ownSound(null, false, cur)).toEqual({ rate: 1, pitch: 0, linked: false })
  })

  it('с «Запомнить» — общий звук переходит на B', () => {
    expect(ownSound(null, true, cur)).toEqual(cur)
  })
})
