// Знак Sonar как свой символ (SF Symbols template v3.0) для кнопки «Моя волна» в Пункте управления: кнопки
// Пункта управления (ControlWidget, iOS 18) рисуют только символы — обычную картинку или SwiftUI-фигуру там
// не показать, а SF Symbol владелец не хочет. Источник — brand/logo.svg, тот же знак, что LogoMark.
// Шаблон — минимальный «переменный» (Ultralight-S, Regular-S, Black-S), как у SwiftDraw: Xcode сам
// выводит из трёх вариантов все 27 начертаний. Знак залитый, поэтому все три варианта одинаковые.
// Запуск: cd ios/scripts && npm install && node gen-symbol.mjs
// → ios/SonarWidget/Assets.xcassets/sonar.mark.symbolset/sonar.mark.svg (+ Contents.json).
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const svgpath = require('svgpath')

const SYMBOL_NAME = 'sonar.mark'

// Размеры шаблона (единицы SF Symbols, кегль 100): линия прописных — 76, базовая — 146.
const CAPLINE = 76
const BASELINE = 146
// знак высокий и узкий: чуть выше прописной (1.2 от высоты H), по центру между линиями — как music.note
const GLYPH_HEIGHT = 84
const GLYPH_CENTER_Y = (CAPLINE + BASELINE) / 2
const VARIANTS = [
  { name: 'Ultralight', centerX: 265 },
  { name: 'Regular', centerX: 465 },
  { name: 'Black', centerX: 665 },
]
const CURVE_SAMPLES = 50

const round = (value) => Math.round(value * 1000) / 1000

/** Все `d` из `<path>` логотипа одной строкой, в абсолютных командах без дуг и сокращений. */
function logoPath(svg) {
  const ds = [...svg.matchAll(/<path[^>]*\sd="([^"]+)"/g)].map((m) => m[1])
  if (ds.length === 0) throw new Error('brand/logo.svg: нет <path d="…">')
  return svgpath(ds.join(' ')).abs().unarc().unshort().toString()
}

/** Точные границы пути: кривые проходятся по точкам, а не по контрольным точкам. */
function bounds(d) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  const add = (x, y) => {
    minX = Math.min(minX, x); maxX = Math.max(maxX, x)
    minY = Math.min(minY, y); maxY = Math.max(maxY, y)
  }
  svgpath(d).iterate((seg, _i, x, y) => {
    const [cmd, ...a] = seg
    if (cmd === 'M' || cmd === 'L') add(a[0], a[1])
    else if (cmd === 'H') add(a[0], y)
    else if (cmd === 'V') add(x, a[0])
    else if (cmd === 'C' || cmd === 'Q') {
      for (let k = 1; k <= CURVE_SAMPLES; k++) {
        const t = k / CURVE_SAMPLES, u = 1 - t
        if (cmd === 'C') {
          add(u * u * u * x + 3 * u * u * t * a[0] + 3 * u * t * t * a[2] + t * t * t * a[4],
              u * u * u * y + 3 * u * u * t * a[1] + 3 * u * t * t * a[3] + t * t * t * a[5])
        } else {
          add(u * u * x + 2 * u * t * a[0] + t * t * a[2], u * u * y + 2 * u * t * a[1] + t * t * a[3])
        }
      }
    }
  })
  if (!Number.isFinite(minX)) throw new Error('пустой путь логотипа')
  return { minX, minY, maxX, maxY, width: maxX - minX, height: maxY - minY }
}

/** Путь, вписанный по высоте GLYPH_HEIGHT с центром в (centerX, GLYPH_CENTER_Y), и его поля слева и справа. */
function placeGlyph(d, centerX) {
  const b = bounds(d)
  const scale = GLYPH_HEIGHT / b.height
  const width = b.width * scale
  const tx = centerX - width / 2 - b.minX * scale
  const ty = GLYPH_CENTER_Y - GLYPH_HEIGHT / 2 - b.minY * scale
  // каждая команда явно и через пробелы — без сжатия svgpath («C… …» подряд, «-» вместо пробела)
  const segments = []
  svgpath(d).matrix([scale, 0, 0, scale, tx, ty]).round(3).iterate((seg) => { segments.push(seg.join(' ')) })
  const placed = segments.join(' ')
  return { d: placed, left: round(centerX - width / 2), right: round(centerX + width / 2) }
}

const GUIDE = 'fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;'
// буква H — ориентир размера в шаблоне (из шаблона Apple / SwiftDraw)
const H_REFERENCE = 'M 85 145.755 L 87.685 145.755 L 113.369 79.287 L 114.052 79.287 L 114.052 76 L 112.148 76 L 85 145.755 Z '
  + 'M 95.693 121.536 L 130.996 121.536 L 130.263 119.313 L 96.474 119.313 L 95.693 121.536 Z '
  + 'M 139.15 145.755 L 141.787 145.755 L 114.638 76 L 113.466 76 L 113.466 79.287 L 139.15 145.755 Z'

function symbolSvg(logoSvg) {
  const d = logoPath(logoSvg)
  const placed = VARIANTS.map((v) => ({ ...v, ...placeGlyph(d, v.centerX) }))
  const margins = placed.map((v) => [
    `    <path id="left-margin-${v.name}-S" style="${GUIDE}" d="M ${v.left} 56 L ${v.left} 166"/>`,
    `    <path id="right-margin-${v.name}-S" style="${GUIDE}" d="M ${v.right} 56 L ${v.right} 166"/>`,
  ].join('\n')).join('\n')
  const symbols = placed.map((v) => `    <g id="${v.name}-S">\n      <path d="${v.d}"/>\n    </g>`).join('\n')
  const line = (id, y) => `    <path id="${id}" style="${GUIDE}" d="M 18 ${y} L 818 ${y}"/>`
  return `<?xml version="1.0" encoding="UTF-8"?>
<!-- Сгенерировано ios/scripts/gen-symbol.mjs из brand/logo.svg — не править руками. -->
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="800" height="600">
  <g id="Notes" font-family="sans-serif" font-size="13">
    <rect x="0" y="0" width="800" height="600" fill="white"/>
    <text x="18" y="176">Small</text>
    <text x="18" y="376">Medium</text>
    <text x="18" y="576">Large</text>
    <text x="250" y="30" font-size="9">Ultralight</text>
    <text x="450" y="30" font-size="9">Regular</text>
    <text x="650" y="30" font-size="9">Black</text>
    <text id="template-version" fill="#505050" x="785" y="575" font-size="9" text-anchor="end">Template v.3.0</text>
  </g>
  <g id="Guides">
    <path id="H-reference" style="fill:#27AAE1;stroke:none;" d="${H_REFERENCE}"/>
${line('Capline-S', CAPLINE)}
${line('Baseline-S', BASELINE)}
${line('Capline-M', CAPLINE + 200)}
${line('Baseline-M', BASELINE + 200)}
${line('Capline-L', CAPLINE + 400)}
${line('Baseline-L', BASELINE + 400)}
${margins}
  </g>
  <g id="Symbols">
${symbols}
  </g>
</svg>
`
}

const contents = (body) => `${JSON.stringify({ ...body, info: { author: 'xcode', version: 1 } }, null, 2)}\n`

function main() {
  const logo = readFileSync(new URL('../../brand/logo.svg', import.meta.url), 'utf8')
  const catalog = new URL('../SonarWidget/Assets.xcassets/', import.meta.url)
  const dir = new URL(`${SYMBOL_NAME}.symbolset/`, catalog)
  mkdirSync(dir, { recursive: true })
  writeFileSync(new URL('Contents.json', catalog), contents({}))
  writeFileSync(new URL('Contents.json', dir), contents({ symbols: [{ filename: `${SYMBOL_NAME}.svg`, idiom: 'universal' }] }))
  writeFileSync(new URL(`${SYMBOL_NAME}.svg`, dir), symbolSvg(logo))
  console.log(`${SYMBOL_NAME}.symbolset готов`)
}

main()
