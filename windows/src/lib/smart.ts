// Умные плейлисты (NEXT_PROMPT, этап 6): правила в JSON — общие для ПК и iPhone
// (docs/PLATFORMS.md «Умные плейлисты»). Считает их Rust (`store/smart_rules.rs`) при открытии,
// здесь — типы, готовые шаблоны, проверка формы конструктора и описание правил текстом.

export const RULES_VERSION = 1
export const MAX_DAYS = 3650
export const MAX_LIMIT = 1000
export const MAX_CONDITIONS = 20

export type SmartSource = { kind: 'liked' } | { kind: 'playlist'; id: string } | { kind: 'played' }
export type Cmp = 'gte' | 'lte'

export type SmartCondition =
  | { field: 'plays'; days?: number | null; op: Cmp; value: number }
  | { field: 'last_played'; op: 'before' | 'after'; days: number }
  | { field: 'added'; days: number }
  | { field: 'service'; op: 'is' | 'not'; value: string }
  | { field: 'artist'; op: 'is' | 'not'; value: string }
  | { field: 'duration'; op: Cmp; value: number }

export type SmartField = SmartCondition['field']
export type SortBy = 'plays' | 'last_played' | 'added' | 'title' | 'artist' | 'duration'

export interface SmartRules {
  v: number
  source: SmartSource
  match: 'all' | 'any'
  conditions: SmartCondition[]
  sort?: { by: SortBy; days?: number | null; desc: boolean } | null
  limit?: number | null
}

export type TemplateId = 'forgotten' | 'month_top' | 'barely' | 'worn_out' | 'new_liked'

export interface SmartTemplate {
  id: TemplateId
  /** Русское название — ключ перевода (`t(name)`), сохраняется уже переведённым. */
  name: string
  rules: SmartRules
}

const base = (source: SmartSource): Omit<SmartRules, 'conditions'> => ({ v: RULES_VERSION, source, match: 'all' })

/** Готовые шаблоны: создаются кнопкой, дальше правятся как обычные правила. */
export const TEMPLATES: readonly SmartTemplate[] = [
  {
    id: 'forgotten',
    name: 'Давно не слушал',
    rules: {
      ...base({ kind: 'liked' }),
      conditions: [{ field: 'last_played', op: 'before', days: 60 }],
      sort: { by: 'last_played', desc: false },
    },
  },
  {
    id: 'month_top',
    name: 'Топ месяца',
    rules: {
      ...base({ kind: 'played' }),
      conditions: [{ field: 'plays', days: 30, op: 'gte', value: 1 }],
      sort: { by: 'plays', days: 30, desc: true },
      limit: 50,
    },
  },
  {
    id: 'barely',
    name: 'Лайкнул, но почти не слушаю',
    rules: {
      ...base({ kind: 'liked' }),
      conditions: [{ field: 'plays', op: 'lte', value: 2 }],
      sort: { by: 'added', desc: true },
    },
  },
  {
    id: 'worn_out',
    name: 'Заслушанное',
    rules: {
      ...base({ kind: 'played' }),
      conditions: [{ field: 'plays', days: 30, op: 'gte', value: 10 }],
      sort: { by: 'plays', days: 30, desc: true },
    },
  },
  {
    id: 'new_liked',
    name: 'Новое в Любимых',
    rules: {
      ...base({ kind: 'liked' }),
      conditions: [{ field: 'added', days: 14 }],
      sort: { by: 'added', desc: true },
    },
  },
]

/** Пустые правила для «С нуля»: все Любимые, новые сверху. */
export function blankRules(): SmartRules {
  return { ...base({ kind: 'liked' }), conditions: [], sort: { by: 'added', desc: true }, limit: null }
}

/** Новое условие поля со значениями по умолчанию (кнопка «Условие» в конструкторе). */
export function defaultCondition(field: SmartField, service = 'sc'): SmartCondition {
  switch (field) {
    case 'plays':
      return { field, days: 30, op: 'gte', value: 5 }
    case 'last_played':
      return { field, op: 'before', days: 60 }
    case 'added':
      return { field, days: 14 }
    case 'service':
      return { field, op: 'is', value: service }
    case 'artist':
      return { field, op: 'is', value: '' }
    case 'duration':
      return { field, op: 'gte', value: 180 }
  }
}

/** Глубокая копия правил — конструктор правит копию, исходник не трогает. */
export function cloneRules(rules: SmartRules): SmartRules {
  return JSON.parse(JSON.stringify(rules)) as SmartRules
}

const clampInt = (n: unknown, lo: number, hi: number, fallback: number) => {
  const v = Math.round(Number(n))
  return Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : fallback
}

function normalizeCondition(c: SmartCondition): SmartCondition {
  switch (c.field) {
    case 'plays': {
      const days = clampInt(c.days ?? 0, 0, MAX_DAYS, 0)
      return { field: 'plays', days: days || null, op: c.op, value: clampInt(c.value, 0, 100_000, 0) }
    }
    case 'last_played':
      return { field: 'last_played', op: c.op, days: clampInt(c.days, 1, MAX_DAYS, 60) }
    case 'added':
      return { field: 'added', days: clampInt(c.days, 1, MAX_DAYS, 14) }
    case 'service':
    case 'artist':
      return { field: c.field, op: c.op, value: c.value.trim() }
    case 'duration':
      return { field: 'duration', op: c.op, value: clampInt(c.value, 0, 24 * 3600, 0) }
  }
}

/** Правила из конструктора в вид для сохранения: числа в границах, лишние пробелы убраны. */
export function normalizeRules(r: SmartRules): SmartRules {
  const sort = r.sort ? { by: r.sort.by, desc: r.sort.desc, days: r.sort.by === 'plays' ? clampInt(r.sort.days ?? 0, 0, MAX_DAYS, 0) || null : null } : null
  const limit = r.limit == null || r.limit === 0 ? null : clampInt(r.limit, 1, MAX_LIMIT, 50)
  return { v: RULES_VERSION, source: r.source, match: r.match, conditions: r.conditions.map(normalizeCondition), sort, limit }
}

/** Что не так с правилами (русский текст — ключ перевода) или null, если всё хорошо. */
export function rulesProblem(r: SmartRules, services: readonly string[]): string | null {
  if (r.v !== RULES_VERSION) return 'Правила из новой версии Sonar'
  if (r.source.kind === 'playlist' && !r.source.id) return 'Выбери плейлист'
  if (r.conditions.length > MAX_CONDITIONS) return 'Слишком много условий'
  for (const c of r.conditions) {
    if (c.field === 'artist' && !c.value.trim()) return 'Впиши исполнителя'
    if (c.field === 'service' && !services.includes(c.value)) return 'Выбери сервис'
  }
  return null
}

/** Разобрать сохранённые правила (из базы приходят как JSON) — null, если это не наши правила. */
export function parseRules(raw: unknown): SmartRules | null {
  if (!raw || typeof raw !== 'object') return null
  const r = raw as Partial<SmartRules>
  if (r.v !== RULES_VERSION || !r.source || !Array.isArray(r.conditions ?? [])) return null
  return { v: r.v, source: r.source, match: r.match === 'any' ? 'any' : 'all', conditions: r.conditions ?? [], sort: r.sort ?? null, limit: r.limit ?? null }
}

/** Id умного плейлиста — по префиксу (как `pl_` у обычных). */
export const isSmartId = (id: string | null | undefined): boolean => !!id && id.startsWith('sm_')
