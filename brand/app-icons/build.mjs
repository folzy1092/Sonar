// Значки приложения Sonar: основной («Стекло», решение владельца 2026-11-24) и ещё девять на выбор —
// Интерфейс → Вид → «Значок приложения» на ПК и iPhone. Один генератор делает всё:
//   brand/app-icons/<id>.svg            — исходники, квадрат 1024 (как плитка iOS)
//   brand/icon/sonar_icon_*.svg/png     — основной значок бренда («Стекло»); site/public/apple-touch-icon.png — оттуда же
//   windows/src-tauri/icons/app/        — PNG 64 и 32 для окна, панели задач и трея (app_icon.rs)
//   windows/public/app-icons/           — PNG 160 для плиток выбора в настройках
//   ios/Sonar/Resources/Assets.xcassets — AppIcon («Стекло», светлый / тёмный / тонированный), AppIcon-<Имя>
//                                         для остальных (альтернативные значки) и IconPreview-<id> для плиток
// Знак — контур из brand/logo.svg: две лопасти и два тонких «эха». Объём строится на стандартных
// примитивах (градиенты, размытие, смещение), которые одинаково рисует resvg — им собирается и этот
// скрипт. Освещение (feDiffuseLighting) не берём: в resvg оно зернит и даёт швы.
// Запуск (нужен Node 22.2+: `zlib.crc32`): cd brand/app-icons && npm install && node build.mjs
// Затем значки exe: cd windows && npx tauri icon ../brand/icon/sonar_icon_windows.svg
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { crc32, deflateSync } from 'node:zlib'

const { Resvg } = createRequire(import.meta.url)('@resvg/resvg-js')

const root = (f) => new URL(`../../${f}`, import.meta.url)
const D = readFileSync(new URL('../logo.svg', import.meta.url), 'utf8').match(/ d="([^"]+)"/)[1]
// подконтуры: 0 — правая нижняя лопасть, 1 — эхо у её хвоста, 2 — левая верхняя лопасть, 3 — эхо вверху
const parts = D.split(/(?=M)/).filter(Boolean)
const BLADES = `${parts[0]} ${parts[2]}`
const ECHOES = `${parts[1]} ${parts[3]}`

// знак в той же пропорции к плитке, что у иконки iOS (gen-appicon.mjs)
const T = `translate(512 512) scale(0.917) translate(-512 -512)`

const frame = (defs, body, bg = 'url(#bg)') => `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 1024 1024" width="1024" height="1024" role="img" aria-label="Sonar">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1c1c20"/><stop offset="1" stop-color="#050506"/></linearGradient>
    <path id="all" d="${D}" fill-rule="evenodd"/>
    <path id="bl" d="${BLADES}" fill-rule="evenodd"/>
    <path id="ec" d="${ECHOES}" fill-rule="evenodd"/>
${defs}
  </defs>
  <rect width="1024" height="1024" fill="${bg}"/>
${body}
</svg>
`

const use = (id, extra = '') => `<use xlink:href="#${id}" ${extra}/>`
const mark = (inner) => `  <g transform="${T}">\n    ${inner}\n  </g>`

/** Тень под знаком: чёрный след с размытием. */
const shadow = (id, dx, dy, blur, op) => `    <filter id="${id}" x="-25%" y="-25%" width="150%" height="150%"><feGaussianBlur in="SourceAlpha" stdDeviation="${blur}"/><feOffset dx="${dx}" dy="${dy}"/><feComponentTransfer><feFuncA type="linear" slope="${op}"/></feComponentTransfer></filter>`

/** Внутренняя тень и внутренний блик — «углубление». Тень падает от верхнего левого края. */
const inset = (id, s, h) => `    <filter id="${id}" x="-10%" y="-10%" width="120%" height="120%" color-interpolation-filters="sRGB">
      <feComponentTransfer in="SourceAlpha" result="inv"><feFuncA type="table" tableValues="1 0"/></feComponentTransfer>
      <feOffset in="inv" dx="${s.dx}" dy="${s.dy}" result="so"/><feGaussianBlur in="so" stdDeviation="${s.blur}" result="sb"/>
      <feFlood flood-color="${s.color}" flood-opacity="${s.op}"/><feComposite in2="sb" operator="in" result="sc"/><feComposite in="sc" in2="SourceAlpha" operator="in" result="shadow"/>
      <feOffset in="inv" dx="${h.dx}" dy="${h.dy}" result="ho"/><feGaussianBlur in="ho" stdDeviation="${h.blur}" result="hb"/>
      <feFlood flood-color="${h.color}" flood-opacity="${h.op}"/><feComposite in2="hb" operator="in" result="hc"/><feComposite in="hc" in2="SourceAlpha" operator="in" result="hl"/>
      <feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="shadow"/><feMergeNode in="hl"/></feMerge>
    </filter>`

const blur = (id, sd) => `    <filter id="${id}" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="${sd}"/></filter>`

const variants = []
const add = (id, title, note, svg) => variants.push({ id, title, note, svg })

// Освещение (feDiffuseLighting) в resvg зернит и даёт швы, поэтому весь объём — градиенты и внутренние тени.

// 1. Фаска — плоская грань, скошенный край ловит свет
add('bevel', 'Фаска', 'Как вырезанный из металла знак: грань плоская, края скошены.',
  frame(
    [
      shadow('sh', 0, 22, 20, 0.7),
      `    <linearGradient id="bf" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#d9d9e0"/></linearGradient>`,
      inset('bv', { dx: 7, dy: 9, blur: 4.5, color: '#4f4f5b', op: 0.9 }, { dx: -5, dy: -6, blur: 3, color: '#ffffff', op: 1 }),
    ].join('\n'),
    mark(`${use('all', 'filter="url(#sh)"')}\n    ${use('all', 'fill="url(#bf)" filter="url(#bv)"')}`),
  ))

// 2. Подушка — вздутый объём: лопасти пузатые, эхо — тонкое
add('puff', 'Подушка', 'Вздутый глянцевый объём, как надувной знак. Эхо остаётся тонким.',
  frame(
    [
      shadow('sh', 0, 26, 24, 0.75),
      `    <linearGradient id="pg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#b4b4c0"/></linearGradient>`,
      inset('pi', { dx: 22, dy: 30, blur: 26, color: '#33333f', op: 1 }, { dx: -14, dy: -17, blur: 14, color: '#ffffff', op: 1 }),
      inset('pe', { dx: 5, dy: 7, blur: 4, color: '#4f4f5b', op: 0.9 }, { dx: -3, dy: -4, blur: 2.5, color: '#ffffff', op: 1 }),
    ].join('\n'),
    mark(`${use('all', 'filter="url(#sh)"')}\n    ${use('bl', 'fill="url(#pg)" filter="url(#pi)"')}\n    ${use('ec', 'fill="url(#pg)" filter="url(#pe)"')}`),
  ))

// 3. Блок — знак как толстая объёмная деталь
{
  let layers = ''
  const N = 34
  for (let i = N; i >= 1; i--) {
    const k = i / N
    const v = Math.round(206 - 150 * k) // ближе к грани светлее, в глубине темнее
    const c = `rgb(${v},${v},${v + 4})`
    layers += `    <use xlink:href="#all" transform="translate(${(i * 0.95).toFixed(2)} ${(i * 1.25).toFixed(2)})" fill="${c}" stroke="${c}" stroke-width="2.4" stroke-linejoin="round"/>\n`
  }
  add('block', 'Блок', 'Знак — толстая объёмная деталь: видна боковая стенка, под ней тень.',
    frame(
      [
        shadow('sh', 18, 30, 26, 0.8),
        `    <linearGradient id="bf" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#dedee5"/></linearGradient>`,
        inset('bv', { dx: 5, dy: 7, blur: 4, color: '#6a6a76', op: 0.8 }, { dx: -4, dy: -5, blur: 2.5, color: '#ffffff', op: 1 }),
      ].join('\n'),
      mark(`<g transform="translate(14 22)" filter="url(#sh)">${use('all')}</g>\n${layers}    ${use('all', 'fill="url(#bf)" filter="url(#bv)"')}`),
    ))
}

// 4. Стекло — прозрачная белая масса с бликом сверху
add('glass', 'Стекло', 'Матовое стекло: блик по верху, тёмный низ, светящийся край.',
  frame(
    [
      shadow('sh', 0, 24, 22, 0.7),
      blur('glow', 26),
      `    <linearGradient id="gf" gradientUnits="userSpaceOnUse" x1="0" y1="100" x2="0" y2="920"><stop offset="0" stop-color="#ffffff"/><stop offset=".55" stop-color="#d9dde4"/><stop offset="1" stop-color="#8f96a3"/></linearGradient>`,
      `    <linearGradient id="gs" gradientUnits="userSpaceOnUse" x1="0" y1="100" x2="0" y2="560"><stop offset="0" stop-color="#ffffff" stop-opacity=".95"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></linearGradient>`,
      inset('gi', { dx: 0, dy: -14, blur: 12, color: '#4b5160', op: 0.75 }, { dx: 0, dy: 8, blur: 5, color: '#ffffff', op: 0.9 }),
      `    <clipPath id="cp"><use xlink:href="#all"/></clipPath>`,
    ].join('\n'),
    mark(`<g opacity=".28" filter="url(#glow)">${use('all', 'fill="#ffffff"')}</g>\n    ${use('all', 'filter="url(#sh)"')}\n    ${use('all', 'fill="url(#gf)" filter="url(#gi)"')}\n    <g clip-path="url(#cp)"><rect x="190" y="100" width="650" height="460" fill="url(#gs)"/></g>\n    ${use('all', 'fill="none" stroke="#ffffff" stroke-opacity=".55" stroke-width="2.4"')}`),
  ))

// 5. Вдавленный в чёрное — знак вырезан в тёмной поверхности
add('carved', 'Вдавленный', 'Знак продавлен в тёмную плиту: тень сверху внутри, светлая кромка снизу.',
  frame(
    [
      blur('lip', 1.6),
      inset('ci', { dx: 10, dy: 18, blur: 13, color: '#000000', op: 1 }, { dx: -5, dy: -9, blur: 6, color: '#b4b4c4', op: 0.7 }),
      `    <linearGradient id="slab" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3e3e46"/><stop offset="1" stop-color="#23232a"/></linearGradient>`,
    ].join('\n'),
    mark(`<g transform="translate(6 9)" filter="url(#lip)" opacity=".5">${use('all', 'fill="#ffffff"')}</g>\n    ${use('all', 'fill="#050506" filter="url(#ci)"')}`),
    'url(#slab)',
  ))

// 6. Вдавленный в светлое — мягкое «нео», светлая тема
add('light', 'Светлый', 'Светлая плита и мягкая вмятина. Для светлой темы и бумажных носителей.',
  frame(
    [
      blur('lip', 2.2),
      inset('ci', { dx: 12, dy: 15, blur: 14, color: '#5d6578', op: 1 }, { dx: -9, dy: -10, blur: 7, color: '#ffffff', op: 1 }),
      `    <linearGradient id="slab" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f1f3f6"/><stop offset="1" stop-color="#dadee5"/></linearGradient>`,
      `    <linearGradient id="pit" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#aab1bf"/><stop offset="1" stop-color="#d3d8e0"/></linearGradient>`,
    ].join('\n'),
    mark(`<g transform="translate(7 8)" filter="url(#lip)" opacity=".95">${use('all', 'fill="#ffffff"')}</g>\n    <g transform="translate(-5 -6)" filter="url(#lip)" opacity=".3">${use('all', 'fill="#8a92a3"')}</g>\n    ${use('all', 'fill="url(#pit)" filter="url(#ci)"')}`),
    'url(#slab)',
  ))

// 7. Колодец сонара — плита вогнута чашей, по дну идут кольца, знак вздут над ней
{
  const rings = [150, 245, 340, 430].map((r, i) => `<circle cx="512" cy="512" r="${r}" fill="none" stroke="#ffffff" stroke-opacity="${(0.15 - i * 0.03).toFixed(2)}" stroke-width="2.5"/>`).join('')
  add('well', 'Колодец', 'Плита вогнута чашей, по дну идут кольца эха, знак вздут над ней. Глубина и в плите, и в самом знаке.',
    frame(
      [
        shadow('sh', 0, 34, 28, 0.85),
        `    <linearGradient id="pg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#cfcfd8"/></linearGradient>`,
        inset('pi', { dx: 16, dy: 22, blur: 19, color: '#3f3f4c', op: 0.95 }, { dx: -10, dy: -12, blur: 11, color: '#ffffff', op: 1 }),
        inset('pe', { dx: 5, dy: 7, blur: 4, color: '#4f4f5b', op: 0.9 }, { dx: -3, dy: -4, blur: 2.5, color: '#ffffff', op: 1 }),
        `    <linearGradient id="bowl" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#000000"/><stop offset=".55" stop-color="#0c0c0f"/><stop offset="1" stop-color="#2b2b32"/></linearGradient>`,
        `    <linearGradient id="rim" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#000000" stop-opacity=".95"/><stop offset=".45" stop-color="#000000" stop-opacity="0"/><stop offset=".6" stop-color="#ffffff" stop-opacity="0"/><stop offset="1" stop-color="#ffffff" stop-opacity=".38"/></linearGradient>`,
      ].join('\n'),
      `  <circle cx="512" cy="512" r="470" fill="url(#bowl)"/>\n  <circle cx="512" cy="512" r="462" fill="none" stroke="url(#rim)" stroke-width="22"/>\n  ${rings}\n${mark(`${use('all', 'filter="url(#sh)"')}\n    ${use('bl', 'fill="url(#pg)" filter="url(#pi)"')}\n    ${use('ec', 'fill="url(#pg)" filter="url(#pe)"')}`)}`,
    ))
}

// 8. Хром — зеркальный металл с линией горизонта
add('chrome', 'Хром', 'Зеркальный металл с тёмной линией горизонта по центру. Самый «железный» из набора.',
  frame(
    [
      shadow('sh', 0, 24, 22, 0.75),
      `    <linearGradient id="cr" gradientUnits="userSpaceOnUse" x1="0" y1="100" x2="0" y2="920"><stop offset="0" stop-color="#ffffff"/><stop offset=".2" stop-color="#d4d8df"/><stop offset=".4" stop-color="#7d838e"/><stop offset=".49" stop-color="#2a2c31"/><stop offset=".52" stop-color="#e9ecf1"/><stop offset=".74" stop-color="#aab0bb"/><stop offset="1" stop-color="#f4f5f8"/></linearGradient>`,
      inset('cv', { dx: 5, dy: 7, blur: 4, color: '#15161a', op: 0.7 }, { dx: -4, dy: -5, blur: 3, color: '#ffffff', op: 1 }),
    ].join('\n'),
    mark(`${use('all', 'filter="url(#sh)"')}\n    ${use('all', 'fill="url(#cr)" filter="url(#cv)"')}\n    ${use('all', 'fill="none" stroke="#ffffff" stroke-opacity=".6" stroke-width="2"')}`),
  ))

// 9. Лопасти выпуклые, эхо — вдавленные канавки
add('echo', 'Эхо', 'Лопасти выпуклые, а «эхо» — вдавленные в плиту канавки: два уровня глубины.',
  frame(
    [
      shadow('sh', 0, 22, 20, 0.7),
      `    <linearGradient id="pg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#cfcfd8"/></linearGradient>`,
      inset('pf', { dx: 12, dy: 17, blur: 14, color: '#3f3f4c', op: 0.95 }, { dx: -7, dy: -9, blur: 8, color: '#ffffff', op: 1 }),
      blur('lip', 1.4),
      inset('ci', { dx: 4, dy: 7, blur: 4.5, color: '#000000', op: 1 }, { dx: -2, dy: -3, blur: 3, color: '#a0a0ae', op: 0.5 }),
      `    <linearGradient id="slab" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a2a30"/><stop offset="1" stop-color="#15151a"/></linearGradient>`,
    ].join('\n'),
    mark(`<g transform="translate(3 5)" filter="url(#lip)" opacity=".4">${use('ec', 'fill="#ffffff"')}</g>\n    ${use('ec', 'fill="#050506" filter="url(#ci)"')}\n    ${use('bl', 'filter="url(#sh)"')}\n    ${use('bl', 'fill="url(#pg)" filter="url(#pf)"')}`),
    'url(#slab)',
  ))

// 0. Плоский — прежний значок: белая S на тёмном градиенте
add('flat', 'Плоский', 'Прежний значок: белая S без объёма.', frame('', mark(use('all', 'fill="#ffffff"'))))

// --- вывод ---
const ORDER = ['glass', 'flat', 'bevel', 'puff', 'block', 'echo', 'well', 'chrome', 'carved', 'light']
const DEFAULT = 'glass'
const byId = Object.fromEntries(variants.map((v) => [v.id, v]))
const icons = ORDER.map((id) => byId[id])
if (icons.some((v) => !v) || icons.length !== variants.length) throw new Error('набор значков и ORDER разошлись')

/** Плитка для Windows: тот же рисунок на 960 × 960 со скруглением 224 и прозрачными углами (как значок exe). */
const tileOf = (svg) =>
  svg.replace(/(<svg[^>]*>)([\s\S]*)<\/svg>/, (_, open, inner) => {
    const [, defs, art] = inner.match(/^([\s\S]*?<\/defs>)([\s\S]*)$/)
    return `${open}${defs}
  <clipPath id="tile"><rect x="32" y="32" width="960" height="960" rx="224"/></clipPath>
  <g clip-path="url(#tile)"><g transform="translate(512 512) scale(0.9375) translate(-512 -512)">${art}</g></g>
</svg>
`
  })

/** Тонированный значок iOS: тот же рисунок на чёрном — система красит по яркости. */
const tinted = (svg) => svg.replace('<rect width="1024" height="1024" fill="url(#bg)"/>', '<rect width="1024" height="1024" fill="#000000"/>')

const render = (svg, size) => new Resvg(svg, { fitTo: { mode: 'width', value: size } }).render()

/** PNG без альфа-канала: значку iOS он не нужен, а квадрат целиком закрашен. */
function rgbPng({ width, height, pixels }) {
  const row = width * 3
  const raw = Buffer.alloc((row + 1) * height)
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const s = (y * width + x) * 4
      const d = y * (row + 1) + 1 + x * 3
      raw[d] = pixels[s]
      raw[d + 1] = pixels[s + 1]
      raw[d + 2] = pixels[s + 2]
    }
  }
  const chunk = (type, data) => {
    const head = Buffer.alloc(4)
    head.writeUInt32BE(data.length)
    const body = Buffer.concat([Buffer.from(type), data])
    const tail = Buffer.alloc(4)
    tail.writeUInt32BE(crc32(body))
    return Buffer.concat([head, body, tail])
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8 // глубина
  ihdr[9] = 2 // RGB
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

const put = (url, data) => {
  mkdirSync(new URL('.', url), { recursive: true })
  writeFileSync(url, data)
}
const here = (f) => new URL(f, import.meta.url)
const assets = (f) => root(`ios/Sonar/Resources/Assets.xcassets/${f}`)
const json = (o) => `${JSON.stringify(o, null, 2)}\n`
const info = { author: 'xcode', version: 1 }
const image = (filename, extra = {}) => ({ filename, idiom: 'universal', platform: 'ios', size: '1024x1024', ...extra })

/** Имя набора значка в каталоге: основной — AppIcon, остальные — AppIcon-<Имя> (альтернативные значки iOS). */
export const setName = (id) => (id === DEFAULT ? 'AppIcon' : `AppIcon-${id[0].toUpperCase()}${id.slice(1)}`)

let total = 0
for (const v of icons) {
  put(here(`${v.id}.svg`), v.svg)

  // Windows: окно, панель задач, трей (Rust) и плитки в настройках
  const tile = tileOf(v.svg)
  put(root(`windows/src-tauri/icons/app/${v.id}-64.png`), render(tile, 64).asPng())
  put(root(`windows/src-tauri/icons/app/${v.id}-32.png`), render(tile, 32).asPng())
  put(root(`windows/public/app-icons/${v.id}.png`), render(tile, 160).asPng())

  // iOS: значок и образец для плитки в настройках
  const big = rgbPng(render(v.svg, 1024))
  total += big.length
  if (v.id === DEFAULT) {
    put(assets('AppIcon.appiconset/AppIcon.png'), big)
    put(assets('AppIcon.appiconset/AppIcon-Dark.png'), big)
    put(assets('AppIcon.appiconset/AppIcon-Tinted.png'), rgbPng(render(tinted(v.svg), 1024)))
    put(assets('AppIcon.appiconset/Contents.json'), json({
      images: [
        image('AppIcon.png'),
        image('AppIcon-Dark.png', { appearances: [{ appearance: 'luminosity', value: 'dark' }] }),
        image('AppIcon-Tinted.png', { appearances: [{ appearance: 'luminosity', value: 'tinted' }] }),
      ],
      info,
    }))
  } else {
    const set = setName(v.id)
    put(assets(`${set}.appiconset/${set}.png`), big)
    put(assets(`${set}.appiconset/Contents.json`), json({ images: [image(`${set}.png`)], info }))
  }
  put(assets(`IconPreview-${v.id}.imageset/IconPreview-${v.id}.png`), rgbPng(render(v.svg, 256)))
  put(assets(`IconPreview-${v.id}.imageset/Contents.json`), json({ images: [{ filename: `IconPreview-${v.id}.png`, idiom: 'universal' }], info }))
}

// основной значок бренда — «Стекло»
const glass = byId[DEFAULT].svg
put(root('brand/icon/sonar_icon_dark.svg'), glass)
put(root('brand/icon/sonar_icon_dark.png'), rgbPng(render(glass, 1024)))
put(root('brand/icon/sonar_icon_windows.svg'), tileOf(glass))
put(root('site/public/apple-touch-icon.png'), rgbPng(render(glass, 180)))

// список для тестов обеих платформ и project.yml
put(here('icons.json'), json({ default: DEFAULT, icons: icons.map((v) => ({ id: v.id, title: v.title, set: setName(v.id) })) }))

const card = (v, i) => `    <figure><img src="${v.id}.svg" alt="${v.title}"><figcaption><b>${i + 1}. ${v.title}</b><span>${v.note}</span></figcaption></figure>`
writeFileSync(here('index.html'), `<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Sonar — значки приложения</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; padding: 32px; background: #0d0d0f; color: #e8e8ec; font: 15px/1.4 system-ui, sans-serif; }
  h1 { font-size: 20px; font-weight: 600; margin: 0 0 20px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, 240px); gap: 24px; }
  figure { margin: 0; }
  img { width: 240px; height: 240px; border-radius: 54px; display: block; }
  figcaption { margin-top: 8px; display: grid; gap: 2px; }
  figcaption span { color: #9a9aa4; font-size: 13px; }
</style></head>
<body>
  <h1>Значки приложения Sonar — основной «Стекло» и ещё ${icons.length - 1}</h1>
  <div class="grid">
${icons.map(card).join('\n')}
  </div>
</body></html>
`)

console.log(`${icons.length} значков; iOS 1024 px — ${(total / 1024 / 1024).toFixed(1)} МБ всего`)
console.log(`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: "${icons.filter((v) => v.id !== DEFAULT).map((v) => setName(v.id)).join(' ')}"`)
