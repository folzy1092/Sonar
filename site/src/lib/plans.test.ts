import { describe, expect, test } from 'vitest'
import * as app from '../../../windows/src/lib/subscription'
import {
  FREE_LIMITS, PERIODS, PERKS, PLANS, findPeriod, findPlan, normalizeUsername, parsePayQuery, payQuery, price, rub,
  savedPercent,
} from './plans'

describe('plans.json совпадает с приложением (windows/src/lib/subscription.ts)', () => {
  test('тарифы, места и помесячные цены', () => {
    expect(PLANS.map(({ id, name, seats, monthly }) => ({ id, name, seats, monthly }))).toEqual(
      app.PLANS.map(({ id, name, seats, monthly }) => ({ id, name, seats, monthly })),
    )
  })

  test('сроки и скидки', () => {
    expect(PERIODS).toEqual(app.PERIODS)
  })

  test('цена и скидка каждой пары тариф × срок', () => {
    for (const plan of app.PLANS) {
      for (const period of app.PERIODS) {
        const site = { plan: findPlan(plan.id), period: findPeriod(period.id) }
        expect(price(site.plan, site.period)).toBe(app.price(plan, period))
        expect(savedPercent(site.plan, site.period)).toBe(app.savedPercent(plan, period))
      }
    }
  })

  test('что входит в Sonar Deep и бесплатные пределы', () => {
    expect(PERKS).toEqual(app.PERKS)
    expect(FREE_LIMITS.playlists).toBe(app.FREE_LIMITS.playlists)
    expect(FREE_LIMITS.import_tracks).toBe(app.FREE_LIMITS.import_tracks)
  })

  test('утверждённые владельцем цены: 150 / 285 / 425 / 570 ₽', () => {
    expect(PLANS.map((p) => p.monthly)).toEqual([150, 285, 425, 570])
  })
})

describe('parsePayQuery', () => {
  test('читает ссылку из приложения целиком', () => {
    const url = new URL(app.payUrl('pod', '6m', 'folzy'))
    expect(parsePayQuery(url.search)).toEqual({ plan: 'pod', period: '6m', username: 'folzy' })
  })

  test('без параметров — Ping на месяц без аккаунта', () => {
    expect(parsePayQuery('')).toEqual({ plan: 'ping', period: '1m', username: '' })
  })

  test('неизвестный тариф и срок заменяет значениями по умолчанию', () => {
    expect(parsePayQuery('?plan=gold&period=99y&u=ok_name')).toEqual({ plan: 'ping', period: '1m', username: 'ok_name' })
  })

  test('регистр и «@» в параметрах не мешают', () => {
    expect(parsePayQuery('?plan=FLEET&period=12M&u=@Folzy')).toEqual({ plan: 'fleet', period: '12m', username: 'folzy' })
  })

  test('туда и обратно через payQuery', () => {
    const sel = { plan: 'echo', period: '3m', username: 'a_b' } as const
    expect(parsePayQuery(payQuery(sel))).toEqual(sel)
  })
})

describe('normalizeUsername', () => {
  test.each([
    ['folzy', 'folzy'],
    ['  @Folzy_1 ', 'folzy_1'],
    ['ab', ''],
    ['имя', ''],
    ['a'.repeat(33), ''],
    ['<script>', ''],
    [null, ''],
  ])('%s → %s', (raw, want) => {
    expect(normalizeUsername(raw)).toBe(want)
  })
})

test('rub разделяет тысячи тонким пробелом', () => {
  expect(rub(100)).toBe('100 ₽')
  expect(rub(3420)).toBe('3 420 ₽')
})
