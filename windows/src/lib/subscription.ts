// Подписка Sonar+ (решение владельца 2026-11-18): в приложении выбирают тариф и срок, оплата — на сайте
// (`sonar.folzy.ru/pay`, будущая платёжка). Тарифы по числу мест: Solo · Duo · Trio · Squad (1–4 аккаунта).
// Платно — только функции Sonar, не доступ к музыке (CLAUDE.md). Цены — ЧЕРНОВИК: владелец их ещё не
// утверждал; с сервером придут из `GET /config`, тогда эта таблица — запасная.
import { SITE_URL } from './site'

export type PlanId = 'solo' | 'duo' | 'trio' | 'squad'
export type PeriodId = '1m' | '3m' | '6m' | '12m'

export interface Plan {
  id: PlanId
  name: string
  /** Сколько аккаунтов: ты и ещё N − 1. */
  seats: number
  /** Цена за месяц при оплате помесячно, ₽. */
  monthly: number
}

export interface Period {
  id: PeriodId
  months: number
  /** Скидка за срок, доля (0.25 = −25 %). */
  discount: number
}

export const PLANS: readonly Plan[] = [
  { id: 'solo', name: 'Solo', seats: 1, monthly: 149 },
  { id: 'duo', name: 'Duo', seats: 2, monthly: 249 },
  { id: 'trio', name: 'Trio', seats: 3, monthly: 329 },
  { id: 'squad', name: 'Squad', seats: 4, monthly: 399 },
]

export const PERIODS: readonly Period[] = [
  { id: '1m', months: 1, discount: 0 },
  { id: '3m', months: 3, discount: 0.1 },
  { id: '6m', months: 6, discount: 0.15 },
  { id: '12m', months: 12, discount: 0.25 },
]

/** Что даёт Sonar+ — ключи перевода; без этого музыка играет так же. */
export const PERKS: readonly string[] = [
  'Объёмный звук 3D · 8D · 12D · 16D',
  'Реверб и пространство: зал, клуб, собор',
  'Пульт-плюс: очередь и громкость ПК с iPhone, передача трека с той же секунды',
  'Видео-фон и живые обои из обложки',
  'Цвет и эффект ника, значок Sonar+ в профиле',
  'Больше места под кэш треков',
]

/** Цена за весь срок, ₽, округлено вниз до «…9». */
export function price(plan: Plan, period: Period): number {
  const raw = plan.monthly * period.months * (1 - period.discount)
  if (period.months === 1) return plan.monthly
  return Math.max(9, Math.floor((raw + 1) / 10) * 10 - 1)
}

/** Скидка в процентах от помесячной оплаты — по итоговой цене (как её увидят). */
export function savedPercent(plan: Plan, period: Period): number {
  if (period.months === 1) return 0
  return Math.round((1 - price(plan, period) / (plan.monthly * period.months)) * 100)
}

/** Ссылка на оплату на сайте; аккаунт сайт возьмёт из входа (с сервером), до него — по @username. */
export function payUrl(plan: PlanId, period: PeriodId, username?: string | null): string {
  const q = new URLSearchParams({ plan, period })
  if (username) q.set('u', username)
  return `${SITE_URL}/pay?${q}`
}

/** «1 799 ₽» — с тонким пробелом между тысячами. */
export const rub = (n: number): string => `${n.toLocaleString('ru-RU').replace(/\s/g, ' ')} ₽`
