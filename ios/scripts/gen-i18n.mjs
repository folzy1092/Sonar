// Генератор ios/Sonar/Core/I18n/Strings+Windows.swift: словари en / uk из Windows-клиента
// (windows/src/i18n/{en,uk}/*.ts) — те же ключи (русская строка), те же переводы. Строки, которых
// на Windows нет, — руками в ios/Sonar/Core/I18n/Strings+iOS.swift (они главнее).
// Запуск: cd ios/scripts && node gen-i18n.mjs
import { readFileSync, readdirSync, writeFileSync } from 'node:fs'

const root = new URL('../../windows/src/i18n/', import.meta.url)

function load(lang) {
  const out = {}
  const dir = new URL(`${lang}/`, root)
  for (const name of readdirSync(dir).filter((n) => n.endsWith('.ts')).sort()) {
    const src = readFileSync(new URL(name, dir), 'utf8')
      .replace(/^\s*\/\/.*$/gm, '')
      .replace(/export\s+default/, 'return')
      .replace(/\}\s*satisfies[^\n]*/, '}')
    Object.assign(out, new Function(src)())
  }
  return out
}

const q = (s) => JSON.stringify(s).replace(/\\u([0-9a-f]{4})/g, (_, h) => `\\u{${h}}`)

function dict(name, d) {
  const rows = Object.keys(d)
    .sort()
    .map((k) => `        ${q(k)}: ${q(d[k])},`)
    .join('\n')
  return `    static let ${name}: [String: String] = [\n${rows}\n    ]`
}

const en = load('en')
const uk = load('uk')
const swift = `// Сгенерировано ios/scripts/gen-i18n.mjs из windows/src/i18n/{en,uk}/*.ts. Руками не править:
// новая строка Windows — в её словарь и перегенерировать; строка только iOS — Strings+iOS.swift.

extension I18n {
${dict('windowsEN', en)}

${dict('windowsUK', uk)}
}
`
writeFileSync(new URL('../Sonar/Core/I18n/Strings+Windows.swift', import.meta.url), swift)
console.log(`en: ${Object.keys(en).length}, uk: ${Object.keys(uk).length}`)
