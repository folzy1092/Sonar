import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import config from '../../astro.config.mjs'
import { DEFAULT_LANG, LANGS } from '../i18n'
import { INLINE_SCRIPT_HASHES, JS_CLASS, NOT_FOUND_LANG, PREFIXED_LANGS, cspHash } from './inline-scripts.mjs'

// CSP сайта — мета-тег Astro (GitHub Pages заголовков не даёт). Сторожим, чтобы правка конфига
// не открыла лишнего и не сломала шрифты, картинки и обращения к API.
const csp = config.experimental?.csp
const directives: string[] = typeof csp === 'object' ? (csp.directives ?? []) : []
const policy = directives.join('; ')

describe('CSP сайта', () => {
  it('включена', () => {
    expect(directives.length).toBeGreaterThan(0)
  })

  it('по умолчанию — только свой адрес, без плагинов и чужих форм', () => {
    expect(policy).toContain("default-src 'self'")
    expect(policy).toContain("object-src 'none'")
    expect(policy).toContain("base-uri 'self'")
    expect(policy).toContain("form-action 'self'")
  })

  it('шрифты и картинки: свои и встроенные data:', () => {
    expect(policy).toMatch(/font-src 'self' data:/)
    expect(policy).toMatch(/img-src 'self' data:/)
  })

  it('сеть — только API Sonar, релизы GitHub и lrclib (текст на странице трека)', () => {
    const connect = directives.find((d) => d.startsWith('connect-src')) ?? ''
    expect(connect.split(/\s+/).slice(1).sort()).toEqual([
      "'self'",
      'https://api.github.com',
      'https://lrclib.net',
      'https://sonar-api.folzy.ru',
    ])
  })

  it('встройки — только плееры YouTube без cookie и SoundCloud', () => {
    const frame = directives.find((d) => d.startsWith('frame-src')) ?? ''
    expect(frame.split(/\s+/).slice(1).sort()).toEqual(['https://w.soundcloud.com', 'https://www.youtube-nocookie.com'])
  })

  it('никакого unsafe-inline/eval для скриптов', () => {
    expect(policy).not.toMatch(/script-src[^;]*unsafe/)
    expect(policy).not.toContain('unsafe-eval')
  })
})

describe('встроенные скрипты (is:inline) — в CSP по хэшу', () => {
  it('хэши класса .js и языка 404 стоят в script-src', () => {
    const hashes = typeof csp === 'object' ? (csp.scriptDirective?.hashes ?? []) : []
    for (const h of INLINE_SCRIPT_HASHES) expect(hashes).toContain(h)
    expect(INLINE_SCRIPT_HASHES).toContain(cspHash(JS_CLASS))
    expect(INLINE_SCRIPT_HASHES).toContain(cspHash(NOT_FOUND_LANG))
  })

  it('префиксы языков 404 — все языки сайта, кроме русского', () => {
    expect(PREFIXED_LANGS).toEqual(LANGS.filter((l) => l !== DEFAULT_LANG))
  })

  // собранный сайт (если `npm run build` уже был): каждый исполняемый встроенный скрипт пропущен своей CSP
  const dist = fileURLToPath(new URL('../../dist', import.meta.url))
  it.skipIf(!existsSync(dist))('в dist/ у каждого встроенного скрипта есть хэш в CSP страницы', () => {
    const pages = readdirSync(dist, { recursive: true, encoding: 'utf8' }).filter((f) => f.endsWith('.html'))
    expect(pages.length).toBeGreaterThan(0)
    for (const page of pages) {
      const html = readFileSync(join(dist, page), 'utf8')
      const policy = html.match(/http-equiv="content-security-policy" content="([^"]+)"/i)?.[1] ?? ''
      for (const [, attrs, body] of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)) {
        if (/\bsrc=|type="application\/(ld\+)?json"/.test(attrs)) continue
        expect(policy, `${page}: ${body.slice(0, 60)}`).toContain(cspHash(body))
      }
    }
  })
})
