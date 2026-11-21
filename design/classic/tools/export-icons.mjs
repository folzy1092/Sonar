// Выгрузка значков прототипа в icons/*.svg (24×24, контур 1.75, currentColor).
// Подвижные части (класс p-*) получают id без префикса: p-bar1 → id="bar1".
// Запуск из design/classic: node tools/export-icons.mjs
import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import vm from 'node:vm'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const OUT = join(ROOT, 'icons')
const STROKE = 1.75

const loadIcons = () => {
  const sandbox = { window: { Sonar: {} } }
  vm.runInNewContext(readFileSync(join(ROOT, 'js/art.js'), 'utf8'), sandbox)
  const icons = sandbox.window.Sonar.icons
  if (!icons || !Object.keys(icons).length) throw new Error('В js/art.js не нашлось S.icons')
  return icons
}

// class="fill p-bar1" → fill="currentColor" stroke="none" id="bar1"
const toAttrs = (body) =>
  body.replace(/class="([^"]+)"/g, (_, list) => {
    const names = list.split(/\s+/)
    const fill = names.includes('fill') ? ' fill="currentColor" stroke="none"' : ''
    const part = names.find((n) => n.startsWith('p-'))
    return `${part ? `id="${part.slice(2)}"` : ''}${fill}`.trim()
  }).replace(/\s+>/g, '>').replace(/\s+\/>/g, '/>')

const svgOf = (body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" ` +
  `stroke="currentColor" stroke-width="${STROKE}" stroke-linecap="round" stroke-linejoin="round">` +
  `${toAttrs(body)}</svg>\n`

const kebab = (name) => name.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)

const main = () => {
  const icons = loadIcons()
  rmSync(OUT, { recursive: true, force: true })
  mkdirSync(OUT, { recursive: true })
  const moving = []
  for (const [name, body] of Object.entries(icons)) {
    const svg = svgOf(body)
    writeFileSync(join(OUT, `${kebab(name)}.svg`), svg)
    const ids = [...svg.matchAll(/id="([^"]+)"/g)].map((m) => m[1])
    if (ids.length) moving.push(`${kebab(name)}: ${ids.join(', ')}`)
  }
  console.log(`icons/: ${Object.keys(icons).length} шт.`)
  console.log(`с подвижными частями:\n  ${moving.join('\n  ')}`)
}

main()
