// Языки интерфейса (Система → Общее → Язык): русский, English, Українська, Español, Deutsch, Polski.
// Переключаются на лету. Ключ перевода — **сама русская строка**: `t('Добрый вечер')`. Нет перевода в
// украинском — показывается русская; в испанском, немецком и польском — английская (их читатель скорее
// поймёт английский), а нет и её — русская. Подстановки — `t('Похожее на «{title}»', { title })`.
// Множественное число — `tn(n, ['трек', 'трека', 'треков'])`: ключ — три формы через «|», в английском,
// испанском и немецком словарях две формы («track|tracks»: 1 — первая, иначе вторая), в украинском и
// польском — три (польское правило: 1 · 2–4 кроме 12–14 · остальное, совпадает с русским везде, кроме
// 21, 31… — там у поляков «5+»).
// Словари — части `src/i18n/<язык>/*.ts` (`export default { 'рус': 'перевод' }`), собираются сами
// (import.meta.glob).
// Одно русское слово с разным смыслом — ключ с контекстом `'список::Обновить'`: по-русски видно
// «Обновить», а в словаре свой перевод («Refresh» вместо «Update» у обновления приложения).
import { settings } from './settings.svelte'
import type { Lang } from './system-lang'

export type { Lang }

/** Все языки по порядку списка выбора. */
export const LANGS: readonly Lang[] = ['ru', 'en', 'uk', 'es', 'de', 'pl']

type Dict = Record<string, string>

function collect(mods: Record<string, unknown>): Dict {
  const out: Dict = {}
  for (const m of Object.values(mods)) Object.assign(out, (m as { default?: Dict }).default ?? {})
  return out
}

const DICTS: Record<Exclude<Lang, 'ru'>, Dict> = {
  en: collect(import.meta.glob('../i18n/en/*.ts', { eager: true })),
  uk: collect(import.meta.glob('../i18n/uk/*.ts', { eager: true })),
  es: collect(import.meta.glob('../i18n/es/*.ts', { eager: true })),
  de: collect(import.meta.glob('../i18n/de/*.ts', { eager: true })),
  pl: collect(import.meta.glob('../i18n/pl/*.ts', { eager: true })),
}

/** Языки, у которых недостающая строка берётся из английского, а не из русского. */
const EN_FALLBACK = new Set<Lang>(['es', 'de', 'pl'])
/** Языки с двумя формами множественного числа (1 — первая, иначе вторая). */
const TWO_FORMS = new Set<Lang>(['en', 'es', 'de'])

export function isLang(v: unknown): v is Lang {
  return typeof v === 'string' && (LANGS as readonly string[]).includes(v)
}

/** Текущий язык (реактивно — шаблоны перерисуются при смене). */
export function lang(): Lang {
  const l = settings.get('general.language')
  return isLang(l) ? l : 'ru'
}

const fill = (s: string, params?: Record<string, string | number>) =>
  params ? s.replace(/\{(\w+)\}/g, (m, k: string) => (k in params ? String(params[k]) : m)) : s

/** Перевод строки интерфейса (ключ — русский текст). */
export function t(ru: string, params?: Record<string, string | number>): string {
  const l = lang()
  const at = ru.indexOf('::')
  const plain = at < 0 ? ru : ru.slice(at + 2)
  if (l === 'ru') return fill(plain, params)
  const own = DICTS[l][ru] ?? (EN_FALLBACK.has(l) ? DICTS.en[ru] : undefined)
  return fill(own ?? plain, params)
}

/** Русское правило множественного числа: 0 — одна, 1 — две, 2 — три форма. */
export function ruPlural(n: number): 0 | 1 | 2 {
  const a = Math.abs(n) % 100
  const b = a % 10
  if (a > 10 && a < 20) return 2
  if (b > 1 && b < 5) return 1
  return b === 1 ? 0 : 2
}

/** Польское правило: 0 — 1, 1 — 2–4 (кроме 12–14), 2 — остальное (0, 5–21, 25…). */
export function plPlural(n: number): 0 | 1 | 2 {
  const a = Math.abs(n)
  if (a === 1) return 0
  const b = a % 10
  const c = a % 100
  return b > 1 && b < 5 && (c < 12 || c > 14) ? 1 : 2
}

function pick(l: Lang, n: number, tr: string[]): string {
  if (TWO_FORMS.has(l)) return Math.abs(n) === 1 ? tr[0] : (tr[1] ?? tr[0])
  const i = l === 'pl' ? plPlural(n) : ruPlural(n)
  return tr[i] ?? tr[tr.length - 1]
}

/** Слово при числе: `tn(5, ['трек', 'трека', 'треков'])` → «треков» / «tracks» / «треків» / «utworów». */
export function tn(n: number, forms: [string, string, string]): string {
  const l = lang()
  const key = forms.join('|')
  if (l === 'ru') return forms[ruPlural(n)]
  const own = DICTS[l][key]
  if (own) return pick(l, n, own.split('|'))
  const en = EN_FALLBACK.has(l) ? DICTS.en[key] : undefined
  if (en) return pick('en', n, en.split('|'))
  return forms[ruPlural(n)]
}

/** Все ключи словаря языка — для теста полноты. */
export function dictionary(l: Exclude<Lang, 'ru'>): Dict {
  return DICTS[l]
}
