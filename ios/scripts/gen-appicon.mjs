// Иконка приложения iOS из brand/icon/sonar_icon_windows.svg — та же, что у exe: белая S на тёмном
// градиенте. iOS сама скругляет углы, поэтому фон — на весь квадрат, а знак в той же пропорции к плитке,
// что у Windows (0.86 от плитки 960 → 0.917 от 1024). Варианты iOS 18: тёмный и тонированный.
// Запуск: cd ios/scripts && npm install && node gen-appicon.mjs, затем убрать альфу (иконке iOS она не нужна):
// python3 -c "from PIL import Image as I; [I.open(f).convert('RGB').save(f) for f in ['AppIcon.png','AppIcon-Dark.png','AppIcon-Tinted.png']]"
// в папке Assets.xcassets/AppIcon.appiconset.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const { Resvg } = require('@resvg/resvg-js')

const win = readFileSync(new URL('../../brand/icon/sonar_icon_windows.svg', import.meta.url), 'utf8')
const glyph = win.match(/<path[^>]*\sd="([^"]+)"/)[1]
const scale = 0.86 * (1024 / 960)

const svg = (bg, ink) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#1c1c20"/><stop offset="1" stop-color="#050506"/></linearGradient></defs>
  <rect width="1024" height="1024" fill="${bg}"/>
  <g transform="translate(512 512) scale(${scale}) translate(-512 -512)">
    <path fill="${ink}" fill-rule="evenodd" d="${glyph}"/>
  </g>
</svg>`

const dir = new URL('../Sonar/Resources/Assets.xcassets/AppIcon.appiconset/', import.meta.url)
mkdirSync(dir, { recursive: true })
const render = (file, bg, ink) => writeFileSync(new URL(file, dir), new Resvg(svg(bg, ink)).render().asPng())
render('AppIcon.png', 'url(#bg)', '#ffffff')
render('AppIcon-Dark.png', 'url(#bg)', '#ffffff')
// тонированная: система красит по яркости — белый знак на чёрном
render('AppIcon-Tinted.png', '#000000', '#ffffff')

writeFileSync(new URL('Contents.json', dir), JSON.stringify({
  images: [
    { filename: 'AppIcon.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
    { appearances: [{ appearance: 'luminosity', value: 'dark' }], filename: 'AppIcon-Dark.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
    { appearances: [{ appearance: 'luminosity', value: 'tinted' }], filename: 'AppIcon-Tinted.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
  ],
  info: { author: 'xcode', version: 1 },
}, null, 2) + '\n')
writeFileSync(new URL('../Contents.json', dir), JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2) + '\n')
console.log('готово')
