// Генератор src/components/flags.ts: флаги языков из @iconify-json/flag (MIT, lipis/flag-icons),
// прямоугольные 4:3 — в интерфейсе со скруглёнными углами, вместо эмодзи Windows.
// Запуск: node scripts/gen-flags.mjs.
import { readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const set = JSON.parse(readFileSync(require.resolve('@iconify-json/flag/icons.json'), 'utf8'))
/** Код языка → флаг. */
const LANGS = { ru: 'ru', en: 'gb', uk: 'ua', es: 'es', de: 'de', pl: 'pl' }
/** Испания — только полосы, без герба: в 18 px его не видно, а весит он 80 КБ. */
const STRIPES_ONLY = new Set(['es'])
const stripes = (body) => body.match(/<path [^>]*\/>/g).slice(0, 2).join('')
const lines = Object.entries(LANGS).map(([lang, f]) => {
  const icon = set.icons[`${f}-4x3`]
  const w = icon.width ?? set.width
  const h = icon.height ?? set.height
  const body = STRIPES_ONLY.has(lang) ? stripes(icon.body) : icon.body
  return `  ${lang}: { body: ${JSON.stringify(body)}, view: '0 0 ${w} ${h}' },`
})
writeFileSync(
  new URL('../src/components/flags.ts', import.meta.url),
  `// Сгенерировано scripts/gen-flags.mjs из @iconify-json/flag (MIT). Руками не править.\n` +
    `export const flags: Record<string, { body: string; view: string }> = {\n${lines.join('\n')}\n}\n`,
)
