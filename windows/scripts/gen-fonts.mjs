// Генератор src/theme/fonts.css: @font-face для шрифтов из scripts/fonts.txt (пакеты fontsource),
// только латиница и кириллица, только woff2 — в exe не тащим лишние алфавиты и форматы.
// Файл качается браузером лишь когда шрифт реально выбран (или показан в настройках).
// Запуск: node scripts/gen-fonts.mjs (после правки fonts.txt и npm i).
import { existsSync, readFileSync, writeFileSync } from 'node:fs'

const root = new URL('../node_modules/', import.meta.url)
// строка `пакет wdth` — шрифт с осью ширины: берём standard.css (wght + wdth), иначе только wght
const pkgs = readFileSync(new URL('./fonts.txt', import.meta.url), 'utf8').split(/\r?\n/).filter(Boolean)
const out = []
const families = []

for (const line of pkgs) {
  const [pkg, axes] = line.trim().split(/\s+/)
  const variable = pkg.startsWith('@fontsource-variable/')
  const sheets = variable ? [axes === 'wdth' ? 'standard.css' : 'index.css'] : ['400.css', '500.css', '600.css', '700.css']
  let family = ''
  for (const sheet of sheets) {
    const file = new URL(`${pkg}/${sheet}`, root)
    if (!existsSync(file)) continue
    const css = readFileSync(file, 'utf8')
    for (const block of css.match(/@font-face\s*{[^}]*}/g) ?? []) {
      const woff2 = /url\(\.\/files\/([^)]+?-(?:latin|cyrillic)-[a-z0-9]+-normal\.woff2)\)/.exec(block)?.[1]
      if (!woff2) continue
      family ||= /font-family:\s*'([^']+)'/.exec(block)[1]
      const src = `src: url('../../node_modules/${pkg}/files/${woff2}') format('woff2');`
      out.push(block.replace(/src:[^;]+;/, src))
    }
  }
  if (!family) throw new Error(`нет латиницы/кириллицы: ${pkg}`)
  families.push(family)
}

writeFileSync(
  new URL('../src/theme/fonts.css', import.meta.url),
  `/* Сгенерировано scripts/gen-fonts.mjs из пакетов fontsource (OFL). Руками не править. */\n${out.join('\n')}\n`,
)
console.log(families.join(' | '))
