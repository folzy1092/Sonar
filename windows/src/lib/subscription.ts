// Подписка Sonar Deep (решение владельца 2026-11-18): в приложении выбирают тариф и срок, оплата — на сайте
// (`try-sonar.ru/pay`, будущая платёжка). Тарифы по числу мест, по теме глубины: Ping (только ты) ·
// Echo (ты + 1) · Pod (ты + 2, «стая») · Fleet (ты + 3, «флотилия»).
// Платно — только функции Sonar, не доступ к музыке (CLAUDE.md). Цены — ЧЕРНОВИК: владелец их ещё не
// утверждал; с сервером придут из `GET /config`, тогда эта таблица — запасная.
// Помесячные цены утвердил владелец 2026-11-18; скидки за срок — черновик.
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
  // Цены владельца: с 2026-11-22 ×1,5 (одно место — 150 ₽; запас под акции, чтобы скидка не выглядела как «подписка за 30 ₽»),
  // за каждое следующее место чуть дешевле — та же лесенка, что и у прежних 100 / 190 / 285 / 380.
  { id: 'ping', name: 'Ping', seats: 1, monthly: 150 },
  { id: 'echo', name: 'Echo', seats: 2, monthly: 285 },
  { id: 'pod', name: 'Pod', seats: 3, monthly: 425 },
  { id: 'fleet', name: 'Fleet', seats: 4, monthly: 570 },
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

/** Чья подписка: `free` — бесплатный Sonar, `dev` — разработчик (всё Sonar Deep, без срока и пределов).
 *  С сервером добавятся тарифы (`PlanId`) из `GET /me`. */
export type SubscriptionTier = 'free' | 'dev'

export interface Subscription {
  tier: SubscriptionTier
  /** Открыты все функции Sonar Deep. */
  deep: boolean
  /** Пределы бесплатного (`FREE_LIMITS`) не действуют. */
  unlimited: boolean
  /** До какого дня, ISO-дата; `null` — без срока (или подписки нет). */
  until: string | null
}

/** Ники разработчиков (без «@», строчными): статус «Dev» до сервера. */
export const DEV_USERNAMES: readonly string[] = ['folzy']

export const FREE_SUBSCRIPTION: Readonly<Subscription> = Object.freeze({ tier: 'free', deep: false, unlimited: false, until: null })
export const DEV_SUBSCRIPTION: Readonly<Subscription> = Object.freeze({ tier: 'dev', deep: true, unlimited: true, until: null })

/** «  @Folzy » → «folzy»: без пробелов по краям и «@» в начале, без учёта регистра. */
export const normalizeUsername = (raw: string | null | undefined): string => (raw ?? '').trim().replace(/^@+/, '').trim().toLowerCase()

/** Подписка профиля — ЕДИНСТВЕННОЕ место, где это решается; все проверки Sonar Deep и пределов идут
 *  через неё. До сервера это ЛОКАЛЬНАЯ проверка по нику: владелец (`@folzy`) — «Dev», остальные —
 *  бесплатный Sonar. С сервером её заменит ответ `GET /me` (поле подписки), а ник решать перестанет. */
export function subscriptionOf(profile: { username?: string | null } | null | undefined): Readonly<Subscription> {
  const nick = normalizeUsername(profile?.username)
  return nick && DEV_USERNAMES.includes(nick) ? DEV_SUBSCRIPTION : FREE_SUBSCRIPTION
}

/** Сколько треков перенести за раз: с подпиской — все, без — до предела. */
export function importCap(total: number, sub: Readonly<Subscription>, enforced = LIMITS_ENFORCED): number {
  return sub.unlimited || !enforced ? total : Math.min(total, FREE_LIMITS.import_tracks)
}

/** Можно ли создать ещё один плейлист. */
export function canCreatePlaylist(count: number, sub: Readonly<Subscription>, enforced = LIMITS_ENFORCED): boolean {
  return sub.unlimited || !enforced || count < FREE_LIMITS.playlists
}

/** Что даёт Sonar Deep — ключи перевода, по важности; без этого музыка играет так же. Состав — docs/DEEP.md. */
export const PERKS: readonly string[] = [
  'Объёмный звук 3D · 8D · 12D · 16D',
  'Реверб и пространство: зал, клуб, собор',
  'Эквалайзер',
  'Сведение: DJ-переходы между треками и режим вечеринки',
  'Sonar Mix под себя: тонкая подстройка, свои волны, больше настроений',
  'Подробная статистика: история без срока, итоги за любой период, экспорт',
  'Больше устройств и пульт-плюс: очередь и эквалайзер ПК с iPhone, передача трека с той же секунды',
  'Перевод текстов песен',
  'Кэш треков без лимита',
  'Плейлисты без лимита',
  'Больше умных плейлистов',
  'Перенос плейлистов из сервисов без лимита',
  'Свои темы оверлея и OBS-плашки',
  'Приоритет у баг-репортов и идей в боте',
  'Чат подписчиков',
  'Доступ к бета-версиям',
]

/** Цена за весь срок, ₽: месяц — как есть, дольше — со скидкой, округлено вниз до 5 ₽. */
export function price(plan: Plan, period: Period): number {
  const raw = plan.monthly * period.months * (1 - period.discount)
  if (period.months === 1) return plan.monthly
  return Math.max(5, Math.floor(raw / 5) * 5)
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
