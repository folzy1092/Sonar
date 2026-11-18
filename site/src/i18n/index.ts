// Языки сайта, как в приложении (`windows/src/lib/i18n.svelte.ts`): ключ перевода — сама русская строка,
// одно слово с разным смыслом — `t('контекст::Слово')`. ru — в корне, en — /en/…, uk — /uk/….
import en from './en'
import uk from './uk'

export const LANGS = ['ru', 'en', 'uk'] as const
export type Lang = (typeof LANGS)[number]
export const DEFAULT_LANG: Lang = 'ru'

export const LANG_NAMES: Record<Lang, string> = { ru: 'Русский', en: 'English', uk: 'Українська' }
/** Для `<html lang>` и `og:locale`. */
export const LOCALES: Record<Lang, string> = { ru: 'ru_RU', en: 'en_US', uk: 'uk_UA' }

export type Dict = Readonly<Record<string, string>>
export const DICTS: Record<Exclude<Lang, 'ru'>, Dict> = { en, uk }

const CONTEXT_SEP = '::'

function fill(text: string, vars?: Record<string, string | number>): string {
  if (!vars) return text
  return text.replace(/\{(\w+)\}/g, (m, k: string) => (k in vars ? String(vars[k]) : m))
}

function stripContext(key: string): string {
  const i = key.indexOf(CONTEXT_SEP)
  return i < 0 ? key : key.slice(i + CONTEXT_SEP.length)
}

export function translate(lang: Lang, key: string, vars?: Record<string, string | number>): string {
  const text = lang === 'ru' ? undefined : DICTS[lang][key]
  return fill(text ?? stripContext(key), vars)
}

/** Номер формы множественного числа: ru/uk — три формы (1 / 2–4 / 5+), en — две. */
export function pluralIndex(lang: Lang, n: number): number {
  const abs = Math.abs(n)
  if (lang === 'en') return abs === 1 ? 0 : 1
  const mod10 = abs % 10
  const mod100 = abs % 100
  if (mod10 === 1 && mod100 !== 11) return 0
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 1
  return 2
}

/** `tn(lang, n, 'трек|трека|треков')` — ключ из русских форм через «|», `{n}` подставляется. */
export function translatePlural(lang: Lang, n: number, key: string, vars?: Record<string, string | number>): string {
  const forms = translate(lang, key).split('|')
  const form = forms[Math.min(pluralIndex(lang, n), forms.length - 1)]
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

/** Язык и путь без префикса: `/uk/faq` → `{ lang: 'uk', rest: '/faq' }`. */
export function splitLang(pathname: string): { lang: Lang; rest: string } {
  const m = pathname.match(/^\/(en|uk)(?=\/|$)(.*)$/)
  if (!m) return { lang: DEFAULT_LANG, rest: pathname || '/' }
  return { lang: m[1] as Lang, rest: m[2] || '/' }
}
