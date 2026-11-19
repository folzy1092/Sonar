// Языки сайта, как в приложении (`windows/src/lib/i18n.svelte.ts`): ключ перевода — сама русская строка,
// одно слово с разным смыслом — `t('контекст::Слово')`. ru — в корне, остальные — /en/…, /uk/…, /es/…, /de/…,
// /pl/…. Нет строки в es / de / pl — берётся английская, нет и её (и в uk) — русская.
import de from './de'
import en from './en'
import es from './es'
import pl from './pl'
import uk from './uk'

export const LANGS = ['ru', 'en', 'uk', 'es', 'de', 'pl'] as const
export type Lang = (typeof LANGS)[number]
export const DEFAULT_LANG: Lang = 'ru'

export const LANG_NAMES: Record<Lang, string> = {
  ru: 'Русский',
  en: 'English',
  uk: 'Українська',
  es: 'Español',
  de: 'Deutsch',
  pl: 'Polski',
}
/** Для `<html lang>` и `og:locale`. */
export const LOCALES: Record<Lang, string> = {
  ru: 'ru_RU',
  en: 'en_US',
  uk: 'uk_UA',
  es: 'es_ES',
  de: 'de_DE',
  pl: 'pl_PL',
}

export type Dict = Readonly<Record<string, string>>
export const DICTS: Record<Exclude<Lang, 'ru'>, Dict> = { en, uk, es, de, pl }

/** Языки, у которых недостающая строка берётся из английского. */
const EN_FALLBACK: ReadonlySet<Lang> = new Set(['es', 'de', 'pl'])
/** Языки с двумя формами множественного числа. */
const TWO_FORMS: ReadonlySet<Lang> = new Set(['en', 'es', 'de'])

const CONTEXT_SEP = '::'

function fill(text: string, vars?: Record<string, string | number>): string {
  if (!vars) return text
  return text.replace(/\{(\w+)\}/g, (m, k: string) => (k in vars ? String(vars[k]) : m))
}

function stripContext(key: string): string {
  const i = key.indexOf(CONTEXT_SEP)
  return i < 0 ? key : key.slice(i + CONTEXT_SEP.length)
}

/** Строка словаря и язык, из которого она взята (для es / de / pl — может быть английская). */
function lookup(lang: Lang, key: string): { text: string; from: Lang } | undefined {
  if (lang === 'ru') return undefined
  const own = DICTS[lang][key]
  if (own !== undefined) return { text: own, from: lang }
  const en = EN_FALLBACK.has(lang) ? DICTS.en[key] : undefined
  return en === undefined ? undefined : { text: en, from: 'en' }
}

export function translate(lang: Lang, key: string, vars?: Record<string, string | number>): string {
  return fill(lookup(lang, key)?.text ?? stripContext(key), vars)
}

/**
 * Номер формы множественного числа: en / es / de — две формы, ru / uk — три (1 / 2–4 / 5+), pl — три по
 * польскому правилу (1 / 2–4 кроме 12–14 / остальное: 21, 31… — уже «5+»).
 */
export function pluralIndex(lang: Lang, n: number): number {
  const abs = Math.abs(n)
  if (TWO_FORMS.has(lang)) return abs === 1 ? 0 : 1
  if (lang === 'pl') {
    if (abs === 1) return 0
    const d = abs % 10
    const h = abs % 100
    return d >= 2 && d <= 4 && (h < 12 || h > 14) ? 1 : 2
  }
  const mod10 = abs % 10
  const mod100 = abs % 100
  if (mod10 === 1 && mod100 !== 11) return 0
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 1
  return 2
}

/** `tn(lang, n, 'трек|трека|треков')` — ключ из русских форм через «|», `{n}` подставляется. */
export function translatePlural(lang: Lang, n: number, key: string, vars?: Record<string, string | number>): string {
  const found = lookup(lang, key)
  // правило — того языка, чья строка нашлась (английская подмена в польском — две формы)
  const rule = found?.from ?? 'ru'
  const forms = (found?.text ?? stripContext(key)).split('|')
  const form = forms[Math.min(pluralIndex(rule, n), forms.length - 1)]
  return fill(form, { n, ...vars })
}

export function useT(lang: Lang) {
  return {
    t: (key: string, vars?: Record<string, string | number>) => translate(lang, key, vars),
    tn: (n: number, key: string, vars?: Record<string, string | number>) => translatePlural(lang, n, key, vars),
  }
}

export function isLang(v: unknown): v is Lang {
  return typeof v === 'string' && (LANGS as readonly string[]).includes(v)
}

/** Язык из параметра `[...lang]`: пусто — русский. */
export function langParam(param: string | undefined): Lang {
  return isLang(param) ? param : DEFAULT_LANG
}

/** Пути для `getStaticPaths` страниц `[...lang]`. */
export function langPaths() {
  return LANGS.map((lang) => ({ params: { lang: lang === DEFAULT_LANG ? undefined : lang } }))
}

/** Ссылка на страницу сайта на нужном языке: `href('en', '/pay')` → `/en/pay`. */
export function href(lang: Lang, path: string): string {
  const clean = path.startsWith('/') ? path : `/${path}`
  if (lang === DEFAULT_LANG) return clean
  return clean === '/' ? `/${lang}/` : `/${lang}${clean}`
}

const LANG_PREFIX = new RegExp(`^/(${LANGS.filter((l) => l !== DEFAULT_LANG).join('|')})(?=/|$)(.*)$`)

/** Язык и путь без префикса: `/uk/faq` → `{ lang: 'uk', rest: '/faq' }`. */
export function splitLang(pathname: string): { lang: Lang; rest: string } {
  const m = pathname.match(LANG_PREFIX)
  if (!m) return { lang: DEFAULT_LANG, rest: pathname || '/' }
  return { lang: m[1] as Lang, rest: m[2] || '/' }
}
