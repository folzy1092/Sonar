import { describe, expect, it } from 'vitest'
import { canCreatePlaylist, DEV_SUBSCRIPTION, FREE_LIMITS, FREE_SUBSCRIPTION, importCap, PERIODS, PLANS, payUrl, price, savedPercent, subscriptionOf } from './subscription'

describe('подписка', () => {
  it('месяц — ровно цена тарифа, дольше — дешевле в пересчёте на месяц', () => {
    for (const plan of PLANS) {
      expect(price(plan, PERIODS[0])).toBe(plan.monthly)
      let last = plan.monthly
      for (const period of PERIODS.slice(1)) {
        const perMonth = price(plan, period) / period.months
        expect(perMonth).toBeLessThan(last)
        last = perMonth
      }
    }
  })

  it('цены владельца ×1,5 (2026-11-22): 150 ₽ за место, дальше лесенкой дешевле; скидка растёт со сроком', () => {
    expect(PLANS.map((p) => p.monthly)).toEqual([150, 285, 425, 570])
    for (const plan of PLANS)
      for (const period of PERIODS) expect(price(plan, period) % 5).toBe(0)
    const solo = PLANS[0]
    expect(PERIODS.map((p) => savedPercent(solo, p))).toEqual([...PERIODS.map((p) => savedPercent(solo, p))].sort((a, b) => a - b))
  })

  it('больше мест — дороже', () => {
    for (let i = 1; i < PLANS.length; i++) expect(PLANS[i].monthly).toBeGreaterThan(PLANS[i - 1].monthly)
  })

  it('ссылка на оплату', () => {
    expect(payUrl('echo', '3m', 'folzy')).toBe('https://try-sonar.ru/pay?plan=echo&period=3m&u=folzy')
    expect(payUrl('ping', '1m')).toBe('https://try-sonar.ru/pay?plan=ping&period=1m')
  })

  it('пределы бесплатного: перенос до 500, плейлистов до 5 — только когда включены', () => {
    expect(importCap(650, FREE_SUBSCRIPTION, true)).toBe(FREE_LIMITS.import_tracks)
    expect(importCap(650, DEV_SUBSCRIPTION, true)).toBe(650)
    expect(importCap(650, FREE_SUBSCRIPTION, false)).toBe(650)
    expect(canCreatePlaylist(5, FREE_SUBSCRIPTION, true)).toBe(false)
    expect(canCreatePlaylist(4, FREE_SUBSCRIPTION, true)).toBe(true)
    expect(canCreatePlaylist(50, DEV_SUBSCRIPTION, true)).toBe(true)
    expect(canCreatePlaylist(50, FREE_SUBSCRIPTION)).toBe(true)
  })

  it('владелец — «Dev»: ник без учёта регистра, «@» и пробелов по краям', () => {
    for (const username of ['folzy', '@Folzy', ' folzy ', '  @FOLZY  ']) {
      const sub = subscriptionOf({ username })
      expect(sub.tier).toBe('dev')
      expect(sub.deep).toBe(true)
      expect(sub.unlimited).toBe(true)
      expect(sub.until).toBeNull()
    }
  })

  it('остальные и пустой ник — бесплатный Sonar', () => {
    for (const username of ['other', 'folzy2', 'fol zy', '', '   ', '@', null, undefined])
      expect(subscriptionOf({ username }).tier).toBe('free')
    expect(subscriptionOf(null)).toEqual(FREE_SUBSCRIPTION)
    expect(subscriptionOf(undefined).deep).toBe(false)
  })

  it('«Dev» снимает пределы, даже когда они включены', () => {
    const dev = subscriptionOf({ username: '@folzy' })
    expect(importCap(10_000, dev, true)).toBe(10_000)
    expect(canCreatePlaylist(999, dev, true)).toBe(true)
    expect(canCreatePlaylist(FREE_LIMITS.playlists, subscriptionOf({ username: 'guest' }), true)).toBe(false)
  })
})
