// Страница /status (SITE.md §5, SPEC §3.11). Данные — `GET /status` и `GET /status/history` (docs/API.md §9).
// Пока сервера нет, страница показывает заготовку «Нет данных» — цифр не выдумываем.

export type State = 'ok' | 'degraded' | 'down' | 'none'
type LiveState = Exclude<State, 'none'>

export interface StatusItem {
  readonly id: string
  readonly state: LiveState
  readonly ms: number | null
}

export interface StatusReport {
  readonly state: LiveState
  readonly uptime30d: number | null
  readonly checkedAt: number
  readonly items: ReadonlyMap<string, StatusItem>
}

export interface HistoryDay {
  readonly date: string
  readonly items: Readonly<Record<string, number>>
}

export interface StatusRow {
  readonly id: string
  readonly name: string
  /** `mc:`/`si:` — значок Icon, `svc:` — цветной знак сервиса из brand/icon. */
  readonly icon: string
}

export interface StatusGroup {
  readonly id: string
  readonly title: string
  readonly rows: readonly StatusRow[]
}

/** Блок «Sonar»: id совпадают с `infra[].id` из API. */
export const SONAR_ROWS: readonly StatusRow[] = [
  { id: 'api', name: 'Основной', icon: 'mc:server-line' },
  { id: 'bot', name: 'Бот', icon: 'mc:robot-line' },
  { id: 'storage', name: 'Хранилище', icon: 'mc:storage-line' },
  { id: 'site', name: 'Сайт', icon: 'mc:globe-line' },
]

/** Блок «Сервисы»: id совпадают с `platforms[].id` из API; чего сервер не прислал — «Нет данных». */
export const SERVICE_GROUPS: readonly StatusGroup[] = [
  {
    id: 'sound',
    title: 'Поиск и звук',
    rows: [
      { id: 'soundcloud', name: 'SoundCloud', icon: 'svc:sc' },
      { id: 'yandex', name: 'Яндекс Музыка', icon: 'svc:ym' },
      { id: 'youtube', name: 'YouTube Music', icon: 'svc:yt' },
      { id: 'vk', name: 'VK Музыка', icon: 'svc:vk' },
      { id: 'spotify', name: 'Spotify', icon: 'svc:sp' },
    ],
  },
  {
    id: 'lyrics',
    title: 'Тексты',
    rows: [
      { id: 'lrclib', name: 'lrclib', icon: 'mc:quote-left-line' },
      { id: 'genius', name: 'Genius', icon: 'si:genius' },
    ],
  },
  { id: 'other', title: 'Другое', rows: [{ id: 'telegram', name: 'Telegram', icon: 'si:telegram' }] },
  { id: 'import', title: 'Только импорт', rows: [{ id: 'apple', name: 'Apple Music', icon: 'svc:am' }] },
]

export const HISTORY_DAYS = 30
/** Пороги цвета полоски по аптайму за день. */
export const UPTIME_OK = 99.5
export const UPTIME_DEGRADED = 95

const LIVE_STATES: readonly string[] = ['ok', 'degraded', 'down']
const DAY_MS = 86_400_000
const MINUTE_MS = 60_000

function isLiveState(v: unknown): v is LiveState {
  return typeof v === 'string' && LIVE_STATES.includes(v)
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}

function finiteOrNull(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null
}

function parseItem(v: unknown): StatusItem | null {
  if (!isRecord(v) || typeof v.id !== 'string' || !isLiveState(v.state)) return null
  return { id: v.id, state: v.state, ms: finiteOrNull(v.ms) }
}

/** Ответ `GET /status` → отчёт; чужой или битый ответ → null (страница остаётся на «Нет данных»). */
export function parseStatus(json: unknown): StatusReport | null {
  if (!isRecord(json) || !isLiveState(json.state)) return null
  const checkedAt = finiteOrNull(json.checked_at)
  if (checkedAt === null) return null
  const list = [json.infra, json.platforms].flatMap((part) => (Array.isArray(part) ? part : []))
  const items = new Map(
    list
      .map(parseItem)
      .filter((item): item is StatusItem => item !== null)
      .map((item) => [item.id, item] as const),
  )
  return { state: json.state, uptime30d: finiteOrNull(json.uptime_30d), checkedAt, items }
}

/** Ответ `GET /status/history` → дни с процентами; битые дни и значения отбрасываются. */
export function parseHistory(json: unknown): readonly HistoryDay[] {
  if (!isRecord(json) || !Array.isArray(json.days)) return []
  return json.days.flatMap((day): HistoryDay[] => {
    if (!isRecord(day) || typeof day.date !== 'string' || !isRecord(day.items)) return []
    const items = Object.fromEntries(
      Object.entries(day.items).filter(([, pct]) => finiteOrNull(pct) !== null && (pct as number) >= 0 && (pct as number) <= 100),
    ) as Record<string, number>
    return [{ date: day.date, items }]
  })
}

/** Цвет полоски дня по аптайму; дня нет в истории — «Нет данных». */
export function uptimeState(pct: number | null | undefined): State {
  if (pct === null || pct === undefined) return 'none'
  if (pct >= UPTIME_OK) return 'ok'
  if (pct >= UPTIME_DEGRADED) return 'degraded'
  return 'down'
}

/** Даты последних `count` дней по UTC, от старой к сегодняшней: `['2026-10-20', …, '2026-11-18']`. */
export function lastDays(now: number, count = HISTORY_DAYS): readonly string[] {
  const today = Math.floor(now / DAY_MS) * DAY_MS
  return Array.from({ length: count }, (_, i) => new Date(today - (count - 1 - i) * DAY_MS).toISOString().slice(0, 10))
}

/** Средний аптайм сервиса за дни, где он есть; данных нет — null. */
export function averageUptime(history: readonly HistoryDay[], id: string): number | null {
  const values = history.map((d) => d.items[id]).filter((v): v is number => v !== undefined)
  if (values.length === 0) return null
  return values.reduce((sum, v) => sum + v, 0) / values.length
}

/** Сколько минут прошло с проверки (не меньше нуля — часы клиента могут спешить). */
export function minutesSince(checkedAt: number, now: number): number {
  return Math.max(0, Math.floor((now - checkedAt) / MINUTE_MS))
}

/** `99.93 %` с разделителем языка; без данных — «—». */
export function formatUptime(pct: number | null, locale: string): string {
  if (pct === null) return '—'
  const num = new Intl.NumberFormat(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(
    Math.floor(pct * 100) / 100,
  )
  return `${num} %`
}
