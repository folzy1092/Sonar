// Встроенные скрипты сайта, которые должны выполниться до отрисовки (`<script is:inline>`). Astro их
// не хэширует, поэтому хэши считает `astro.config.mjs` из этих же строк — текст и хэш не разойдутся.
import { createHash } from 'node:crypto'

/** Класс `.js` на <html> — включает появление блоков, сворачивание FAQ и анимации столбиков. */
export const JS_CLASS = "document.documentElement.classList.add('js')"

/** Языки с префиксом в адресе — как `LANGS` без `ru` (тест `csp.test.ts` сверяет). */
export const PREFIXED_LANGS = ['en', 'uk', 'es', 'de', 'pl']

/** 404: GitHub Pages отдаёт корневую (русскую) страницу и на `/en/…` — переводим на копию нужного языка. */
export const NOT_FOUND_LANG =
  `var p='${PREFIXED_LANGS.join('|')}',l=location.pathname;` +
  "var m=l.match(new RegExp('^/('+p+')(?=/|$)')),want=m?m[1]:'ru';" +
  "if(want!==document.documentElement.lang&&!new RegExp('^/('+p+')/404/?$').test(l))" +
  "location.replace('/'+want+'/404/?from='+encodeURIComponent(l+location.search+location.hash))"

/** `sha256-…` для `script-src`. */
export function cspHash(source) {
  return `sha256-${createHash('sha256').update(source).digest('base64')}`
}

export const INLINE_SCRIPT_HASHES = [JS_CLASS, NOT_FOUND_LANG].map(cspHash)
