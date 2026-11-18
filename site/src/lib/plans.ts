// Тарифы Sonar Deep для страницы /pay. Источник — data/plans.json (зеркало приложения).
import data from '../../data/plans.json'

export type PlanId = 'ping' | 'echo' | 'pod' | 'fleet'
export type PeriodId = '1m' | '3m' | '6m' | '12m'

export interface Plan {
  readonly id: PlanId
  readonly name: string
  readonly seats: number
  readonly monthly: number
}

export interface Period {
  readonly id: PeriodId
  readonly months: number
  readonly discount: number
}

export const PLANS = data.plans as readonly Plan[]
export const PERIODS = data.periods as readonly Period[]
export const PERKS: readonly string[] = data.perks
export const FREE_LIMITS = data.free_limits
export const PAYMENT_PROVIDERS: readonly string[] = data.payment_providers

export const DEFAULT_PLAN: PlanId = 'ping'
export const DEFAULT_PERIOD: PeriodId = '1m'

/** Как в приложении (`avatar.ts`): латиница в нижнем регистре, цифры и «_», 3–32 знака. */
export const USERNAME_RE = /^[a-z0-9_]{3,32}$/

const ROUND_TO = 5

/** Цена за весь срок, ₽: месяц — как есть, дольше — со скидкой, вниз до 5 ₽ (как `subscription.ts`). */
export function price(plan: Plan, period: Period): number {
  if (period.months === 1) return plan.monthly
  const raw = plan.monthly * period.months * (1 - period.discount)
  return Math.max(ROUND_TO, Math.floor(raw / ROUND_TO) * ROUND_TO)
}

/** Скидка в процентах от помесячной оплаты — по итоговой цене. */
export function savedPercent(plan: Plan, period: Period): number {
  if (period.months === 1) return 0
  return Math.round((1 - price(plan, period) / (plan.monthly * period.months)) * 100)
}

/** «1 799 ₽» — тонкий пробел между тысячами, одинаково на всех языках сайта. */
export function rub(n: number): string {
  return `${String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')} ₽`
}

/** Убирает «@» и пробелы, приводит к нижнему регистру; неверное имя → пустая строка. */
export function normalizeUsername(raw: string | null | undefined): string {
  const name = (raw ?? '').trim().replace(/^@+/, '').toLowerCase()
  return USERNAME_RE.test(name) ? name : ''
}

export interface PaySelection {
  readonly plan: PlanId
  readonly period: PeriodId
  readonly username: string
}

const planIds = new Set<string>(PLANS.map((p) => p.id))
const periodIds = new Set<string>(PERIODS.map((p) => p.id))

/** Читает `?plan=&period=&u=` — неизвестное заменяется значениями по умолчанию. */
export function parsePayQuery(search: string): PaySelection {
  const q = new URLSearchParams(search)
  const plan = (q.get('plan') ?? '').toLowerCase()
  const period = (q.get('period') ?? '').toLowerCase()
  return {
    plan: planIds.has(plan) ? (plan as PlanId) : DEFAULT_PLAN,
    period: periodIds.has(period) ? (period as PeriodId) : DEFAULT_PERIOD,
    username: normalizeUsername(q.get('u')),
  }
}

/** Обратно в строку запроса — для `history.replaceState`, чтобы ссылкой можно было поделиться. */
export function payQuery(sel: PaySelection): string {
  const q = new URLSearchParams({ plan: sel.plan, period: sel.period })
  if (sel.username) q.set('u', sel.username)
  return `?${q}`
}

export function findPlan(id: PlanId): Plan {
  return PLANS.find((p) => p.id === id) ?? PLANS[0]
}

export function findPeriod(id: PeriodId): Period {
  return PERIODS.find((p) => p.id === id) ?? PERIODS[0]
}
