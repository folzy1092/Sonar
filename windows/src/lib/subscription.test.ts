import { describe, expect, it } from 'vitest'
import { PERIODS, PLANS, payUrl, price, savedPercent } from './subscription'

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

  it('цены заканчиваются на 9, скидка растёт со сроком', () => {
    for (const plan of PLANS)
      for (const period of PERIODS) expect(price(plan, period) % 10).toBe(9)
    const solo = PLANS[0]
    expect(PERIODS.map((p) => savedPercent(solo, p))).toEqual([...PERIODS.map((p) => savedPercent(solo, p))].sort((a, b) => a - b))
  })

  it('больше мест — дороже', () => {
    for (let i = 1; i < PLANS.length; i++) expect(PLANS[i].monthly).toBeGreaterThan(PLANS[i - 1].monthly)
  })

  it('ссылка на оплату', () => {
    expect(payUrl('duo', '3m', 'folzy')).toBe('https://sonar.folzy.ru/pay?plan=duo&period=3m&u=folzy')
    expect(payUrl('solo', '1m')).toBe('https://sonar.folzy.ru/pay?plan=solo&period=1m')
  })
})
