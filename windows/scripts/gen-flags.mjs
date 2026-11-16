// Генератор src/components/flags.ts: круглые флаги языков из @iconify-json/circle-flags (MIT,
// HatScripts/circle-flags) — вместо эмодзи Windows. Запуск: node scripts/gen-flags.mjs.
import { readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const set = JSON.parse(readFileSync(require.resolve('@iconify-json/circle-flags/icons.json'), 'utf8'))
/** Код языка → флаг. */
const LANGS = { ru: 'ru', en: 'gb', uk: 'ua' }
const lines = Object.entries(LANGS).map(([lang, f]) => `  ${lang}: ${JSON.stringify(set.icons[f].body)},`)
writeFileSync(
  new URL('../src/components/flags.ts', import.meta.url),
  `// Сгенерировано scripts/gen-flags.mjs из @iconify-json/circle-flags (MIT). Руками не править.\n` +
    `export const flags: Record<string, string> = {\n${lines.join('\n')}\n}\n`,
)
