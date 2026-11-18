// Подписка Sonar Deep (решение владельца 2026-11-18): в приложении выбирают тариф и срок, оплата — на сайте
// (`sonar.folzy.ru/pay`, будущая платёжка). Тарифы по числу мест, по теме глубины: Ping (только ты) ·
// Echo (ты + 1) · Pod (ты + 2, «стая») · Fleet (ты + 3, «флотилия»).
// Платно — только функции Sonar, не доступ к музыке (CLAUDE.md). Цены — ЧЕРНОВИК: владелец их ещё не
// утверждал; с сервером придут из `GET /config`, тогда эта таблица — запасная.
import { SITE_URL } from './site'

export type PlanId = 'ping' | 'echo' | 'pod' | 'fleet'

/** Название подписки (бренд, не переводится). */
export const SUB_NAME = 'Sonar Deep'
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
  { id: 'ping', name: 'Ping', seats: 1, monthly: 149 },
  { id: 'echo', name: 'Echo', seats: 2, monthly: 249 },
  { id: 'pod', name: 'Pod', seats: 3, monthly: 329 },
  { id: 'fleet', name: 'Fleet', seats: 4, monthly: 399 },
]

export const PERIODS: readonly Period[] = [
  { id: '1m', months: 1, discount: 0 },
  { id: '3m', months: 3, discount: 0.1 },
  { id: '6m', months: 6, discount: 0.15 },
  { id: '12m', months: 12, discount: 0.25 },
]

/** Бесплатный Sonar — всё основное, с пределами. Скачивание треков — бесплатно и без предела (решение
 *  владельца 2026-11-18). Пределы включатся только вместе с оплатой и сервером: до них никто не ограничен. */
export const FREE_LIMITS = {
  /** Своих плейлистов Sonar. */
  playlists: 5,
  /** Перенос плейлиста из другого сервиса — треков за раз (у кого 600 в Яндексе — перенесётся 500). */
  import_tracks: 500,
  /** Кэш треков на диске, МБ. */
  cache_mb: 2048,
} as const

/** Пределы пока выключены: без оплаты подписку не оформить, а резать своих нельзя. */
export const LIMITS_ENFORCED = false

/** Сколько треков перенести за раз: с подпиской — все, без — до предела. */
export function importCap(total: number, subscribed: boolean, enforced = LIMITS_ENFORCED): number {
  return subscribed || !enforced ? total : Math.min(total, FREE_LIMITS.import_tracks)
}

/** Можно ли создать ещё один плейлист. */
export function canCreatePlaylist(count: number, subscribed: boolean, enforced = LIMITS_ENFORCED): boolean {
  return subscribed || !enforced || count < FREE_LIMITS.playlists
}

/** Что даёт Sonar Deep — ключи перевода, по важности; без этого музыка играет так же. */
export const PERKS: readonly string[] = [
  'Объёмный звук 3D · 8D · 12D · 16D',
  'Реверб и пространство: зал, клуб, собор',
  'Свои шрифты интерфейса',
  'Своя тема: цвета, фон, поверхности',
  'Перевод текстов песен',
  'Кэш треков без лимита',
  'Плейлисты без лимита',
  'Перенос плейлистов из сервисов без лимита',
  'Пульт-плюс: очередь и громкость ПК с iPhone, передача трека с той же секунды',
  'Подробная статистика прослушиваний',
  'Видео-фон и живые обои из обложки',
  'Цвет и эффект ника, значок Sonar Deep в профиле',
  'Чат подписчиков',
  'Доступ к бета-версиям',
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
