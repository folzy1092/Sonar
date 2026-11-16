// Языки интерфейса (Система → Общее → Язык): русский, English, Українська. Переключаются на лету.
// Ключ перевода — **сама русская строка**: `t('Добрый вечер')`. Нет перевода — показывается русская,
// поэтому новая строка без словаря ничего не ломает. Подстановки — `t('Похожее на «{title}»', { title })`.
// Множественное число — `tn(n, ['трек', 'трека', 'треков'])`: ключ — три формы через «|», в английском
// словаре две формы («track|tracks»), в украинском — три (правило как в русском).
// Словари — части `src/i18n/en/*.ts` и `src/i18n/uk/*.ts` (`export default { 'рус': 'перевод' }`),
// собираются сами (import.meta.glob).
// Одно русское слово с разным смыслом — ключ с контекстом `'список::Обновить'`: по-русски видно
// «Обновить», а в словаре свой перевод («Refresh» вместо «Update» у обновления приложения).
import { settings } from './settings.svelte'

export type Lang = 'ru' | 'en' | 'uk'

type Dict = Record<string, string>

function collect(mods: Record<string, unknown>): Dict {
  const out: Dict = {}
  for (const m of Object.values(mods)) Object.assign(out, (m as { default?: Dict }).default ?? {})
  return out
}

const DICTS: Record<Exclude<Lang, 'ru'>, Dict> = {
  en: collect(import.meta.glob('../i18n/en/*.ts', { eager: true })),
  uk: collect(import.meta.glob('../i18n/uk/*.ts', { eager: true })),
}

/** Текущий язык (реактивно — шаблоны перерисуются при смене). */
export function lang(): Lang {
  const l = settings.get('general.language')
  return l === 'en' || l === 'uk' ? l : 'ru'
}

const fill = (s: string, params?: Record<string, string | number>) =>
  params ? s.replace(/\{(\w+)\}/g, (m, k: string) => (k in params ? String(params[k]) : m)) : s

/** Перевод строки интерфейса (ключ — русский текст). */
export function t(ru: string, params?: Record<string, string | number>): string {
  const l = lang()
  const at = ru.indexOf('::')
  const plain = at < 0 ? ru : ru.slice(at + 2)
  return fill(l === 'ru' ? plain : (DICTS[l][ru] ?? plain), params)
}

/** Русское правило множественного числа: 0 — одна, 1 — две, 2 — три форма. */
export function ruPlural(n: number): 0 | 1 | 2 {
  const a = Math.abs(n) % 100
  const b = a % 10
  if (a > 10 && a < 20) return 2
  if (b > 1 && b < 5) return 1
  return b === 1 ? 0 : 2
}

/** Слово при числе: `tn(5, ['трек', 'трека', 'треков'])` → «треков» / «tracks» / «треків». */
export function tn(n: number, forms: [string, string, string]): string {
  const l = lang()
  const key = forms.join('|')
  if (l === 'ru') return forms[ruPlural(n)]
  const tr = DICTS[l][key]?.split('|')
  if (!tr) return forms[ruPlural(n)]
  if (l === 'en') return Math.abs(n) === 1 ? tr[0] : (tr[1] ?? tr[0])
  return tr[ruPlural(n)] ?? tr[tr.length - 1]
}

/** Все ключи словаря языка — для теста полноты. */
export function dictionary(l: Exclude<Lang, 'ru'>): Dict {
  return DICTS[l]
}
