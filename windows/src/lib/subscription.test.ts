import { describe, expect, it } from 'vitest'
import { canCreatePlaylist, FREE_LIMITS, importCap, PERIODS, PLANS, payUrl, price, savedPercent } from './subscription'

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

  it('цены владельца: 100 ₽ за место, на двоих −10, на троих −15, на четверых −20; скидка растёт со сроком', () => {
    expect(PLANS.map((p) => p.monthly)).toEqual([100, 190, 285, 380])
    for (const plan of PLANS)
      for (const period of PERIODS) expect(price(plan, period) % 5).toBe(0)
    const solo = PLANS[0]
    expect(PERIODS.map((p) => savedPercent(solo, p))).toEqual([...PERIODS.map((p) => savedPercent(solo, p))].sort((a, b) => a - b))
  })

  it('больше мест — дороже', () => {
    for (let i = 1; i < PLANS.length; i++) expect(PLANS[i].monthly).toBeGreaterThan(PLANS[i - 1].monthly)
  })

  it('ссылка на оплату', () => {
    expect(payUrl('echo', '3m', 'folzy')).toBe('https://sonar.folzy.ru/pay?plan=echo&period=3m&u=folzy')
    expect(payUrl('ping', '1m')).toBe('https://sonar.folzy.ru/pay?plan=ping&period=1m')
  })

  it('пределы бесплатного: перенос до 500, плейлистов до 5 — только когда включены', () => {
    expect(importCap(650, false, true)).toBe(FREE_LIMITS.import_tracks)
    expect(importCap(650, true, true)).toBe(650)
    expect(importCap(650, false, false)).toBe(650)
    expect(canCreatePlaylist(5, false, true)).toBe(false)
    expect(canCreatePlaylist(4, false, true)).toBe(true)
    expect(canCreatePlaylist(50, true, true)).toBe(true)
    expect(canCreatePlaylist(50, false)).toBe(true)
  })
})
