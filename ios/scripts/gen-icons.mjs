// Генератор ios/Sonar/DesignSystem/Icons/IconPaths.swift: иконки MingCute (Apache-2.0, тот же набор, что
// в Windows-клиенте — windows/scripts/gen-icons.mjs), знаки сервисов из Simple Icons (CC0) и знак Sonar
// из brand/logo.svg. Каждый путь приводится к абсолютным M/L/C/Q/Z (дуги → кривые), Swift разбирает
// строку один раз и кэширует Path.
// Запуск: cd ios/scripts && npm install && node gen-icons.mjs
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const svgpath = require('svgpath')
const set = require('@iconify-json/mingcute/icons.json')
const brands = require('@iconify-json/simple-icons/icons.json')

/** Наше имя → имя MingCute (без -line / -fill). */
const MAP = {
  home: 'home-4', library: 'folder', search: 'search', settings: 'settings-3',
  play: 'play', pause: 'pause', next: 'skip-forward', prev: 'skip-previous',
  heart: 'heart', plus: 'add', filter: 'filter', sortLines: 'filter-2', sortArrows: 'transfer-vertical',
  more: 'more-2', moreH: 'more-1', back: 'left', chevronRight: 'right', chevronDown: 'down',
  check: 'check', close: 'close', shuffle: 'shuffle-2', repeatAll: 'repeat', repeatOne: 'repeat-one',
  edit: 'edit-2', download: 'download-2', listCheck: 'list-check-2', queue: 'playlist', share: 'share-2',
  wave: 'audio-waveform', user: 'circle-user', cloudOff: 'cloud-off', pin: 'pin', dislike: 'thumb-down-2',
  minusCircle: 'minus-circle', transfer: 'transfer-horizontal', bell: 'notification', history: 'history',
  link: 'link', trash: 'delete-2', drag: 'menu', music: 'music-2', lyrics: 'quote-left', time: 'time',
  refresh: 'refresh-2', info: 'information', lock: 'lock', album: 'album', mic: 'mic',
  bolt: 'flash', moon: 'moon', sun: 'sun', disc: 'disc', compass: 'compass', sparkles: 'sparkles', rain: 'drizzle',
  eyeClosed: 'eye-close', dash: 'minimize', square: 'square', palette: 'palette', capsule: 'layout-bottom', pic: 'pic', brush: 'brush', circle: 'round', grid: 'grid',
}

/** Знаки сервисов — одна заливка (Simple Icons, 24×24). */
const BRANDS = { soundcloud: 'soundcloud' }

const paths = (body) => [...body.matchAll(/<path[^>]*\sd="([^"]+)"/g)].map((m) => m[1])

function absolute(d) {
  // H и V превращаем в L, зная текущую точку
  const out = []
  let x = 0, y = 0, sx = 0, sy = 0
  svgpath(d).abs().unarc().unshort().iterate((seg) => {
    const [c, ...a] = seg
    switch (c) {
      case 'M': x = a[0]; y = a[1]; sx = x; sy = y; out.push(['M', x, y]); break
      case 'L': x = a[0]; y = a[1]; out.push(['L', x, y]); break
      case 'H': x = a[0]; out.push(['L', x, y]); break
      case 'V': y = a[0]; out.push(['L', x, y]); break
      case 'C': out.push(['C', ...a]); x = a[4]; y = a[5]; break
      case 'Q': out.push(['Q', ...a]); x = a[2]; y = a[3]; break
      case 'Z': out.push(['Z']); x = sx; y = sy; break
      default: throw new Error(`команда ${c}`)
    }
  })
  const n = (v) => String(Math.round(v * 1000) / 1000)
  return out.map(([c, ...a]) => [c, ...a.map(n)].join(' ')).join(' ')
}

const icon = (n) => {
  const i = set.icons[n] ?? set.icons[set.aliases?.[n]?.parent]
  if (!i) throw new Error(`нет иконки ${n}`)
  return paths(i.body).map(absolute).join(' ')
}

const entries = []
for (const [k, v] of Object.entries(MAP)) {
  entries.push({ name: k, line: icon(`${v}-line`), fill: icon(`${v}-fill`), size: 24 })
}
for (const [k, v] of Object.entries(BRANDS)) {
  const d = paths(brands.icons[v].body).map(absolute).join(' ')
  entries.push({ name: k, line: d, fill: d, size: 24 })
}

// знак Sonar: viewBox логотипа сдвинут, приводим к квадрату 0…S с центровкой
const logoSvg = readFileSync(new URL('../../brand/logo.svg', import.meta.url), 'utf8')
const [vx, vy, vw, vh] = logoSvg.match(/viewBox="([^"]+)"/)[1].split(/\s+/).map(Number)
const side = Math.max(vw, vh)
const dx = -vx + (side - vw) / 2, dy = -vy + (side - vh) / 2
const logo = paths(logoSvg).map((d) => absolute(svgpath(d).translate(dx, dy).toString())).join(' ')
entries.push({ name: 'logo', line: logo, fill: logo, size: side, evenOdd: true })

const q = (s) => JSON.stringify(s)
const cases = entries.map((e) => `    case ${e.name}`).join('\n')
const table = entries
  .map(
    (e) =>
      `        case .${e.name}: (${q(e.line)},\n                ${e.line === e.fill ? q(e.line) : q(e.fill)}, ${e.size}, ${e.evenOdd ? 'true' : 'false'})`,
  )
  .join('\n')

const swift = `// Сгенерировано ios/scripts/gen-icons.mjs из MingCute (Apache-2.0), Simple Icons (CC0) и brand/logo.svg.
// Руками не править: поменять набор — MAP в генераторе.
import Foundation

enum IconName: String, CaseIterable, Sendable {
${cases}
}

extension IconName {
    /// Контур, заливка, сторона квадрата исходных координат, правило заливки even-odd.
    var source: (line: String, fill: String, size: Double, evenOdd: Bool) {
        switch self {
${table}
        }
    }
}
`
const dir = new URL('../Sonar/DesignSystem/Icons/', import.meta.url)
mkdirSync(dir, { recursive: true })
writeFileSync(new URL('IconPaths.swift', dir), swift)
console.log(`иконок: ${entries.length}`)
