/// <reference types="node" />
import { readFileSync, readdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { ICONS, uniquifyIds } from './service-icons'
import { SERVICES } from './services'

const here = dirname(fileURLToPath(import.meta.url))
const ASSETS = resolve(here, '../assets/services')
const BRAND = resolve(here, '../../../brand/icon')

// Копия в сборке ← файл бренда (§3.2). Значки Яндекс Музыки не копируются — у них прежняя разметка.
const SOURCES: Record<string, string> = {
  'sc.svg': 'SoundCloud.svg',
  'sc-mono.svg': 'soundcloud-mono.svg',
  'yt.svg': 'youtube-music.svg',
  'yt-mono.svg': 'youtube-music-mono.svg',
  'vk.svg': 'vk.svg',
  'vk-mono.svg': 'vk-mono.svg',
  'sp.svg': 'spotify.svg',
  'sp-mono.svg': 'spotify-mono.svg',
}

const assets = readdirSync(ASSETS).filter((f) => f.endsWith('.svg'))
const read = (dir: string, file: string) => readFileSync(resolve(dir, file))

describe('файлы значков', () => {
  it('в папке ровно те копии, что перечислены', () => {
    expect([...assets].sort()).toEqual(Object.keys(SOURCES).sort())
  })

  it.each(Object.entries(SOURCES))('%s — байт в байт %s', (copy, source) => {
    expect(read(ASSETS, copy).equals(read(BRAND, source))).toBe(true)
  })

  it.each(assets)('%s без style=', (file) => {
    expect(read(ASSETS, file).toString('utf8')).not.toContain('style=')
  })

  it.each(assets.filter((f) => f.endsWith('-mono.svg')))('%s — currentColor или без цвета', (file) => {
    const svg = read(ASSETS, file).toString('utf8')
    const colours = [...svg.matchAll(/\s(?:fill|stroke)="([^"]+)"/g)].map((m) => m[1])
    const outsideMask = svg.replace(/<mask\b[\s\S]*?<\/mask>/g, '')
    const visible = [...outsideMask.matchAll(/\s(?:fill|stroke)="([^"]+)"/g)].map((m) => m[1])
    expect(colours.length === 0 || svg.includes('currentColor')).toBe(true)
    for (const c of visible) expect(['currentColor', 'none'], `${file}: ${c}`).toContain(c)
  })
})

describe('uniquifyIds', () => {
  it('переименовывает id и ссылки на него', () => {
    const out = uniquifyIds('<mask id="m"/><g mask="url(#m)"/>', '7')
    expect(out).toContain('id="m-7"')
    expect(out).toContain('url(#m-7)')
    expect(out).not.toContain('url(#m)')
  })

  it('href="#x" тоже', () => {
    expect(uniquifyIds('<path id="p"/><use href="#p"/>', '2')).toBe('<path id="p-2"/><use href="#p-2"/>')
  })

  it('без id — как есть', () => {
    expect(uniquifyIds('<svg><path d="M0 0"/></svg>', '1')).toBe('<svg><path d="M0 0"/></svg>')
  })
})

describe('ICONS', () => {
  it('local — null, у остальных есть все три вида', () => {
    expect(ICONS.local).toBeNull()
    for (const s of SERVICES.filter((x) => x.id !== 'local')) {
      const icon = ICONS[s.id]
      expect(icon, s.id).not.toBeNull()
      expect(icon!.badge, s.id).not.toBe('')
      expect(icon!.plain, s.id).not.toBe('')
      expect(icon!.mono, s.id).not.toBe('')
    }
  })

  it('размеры плитки «Лайки»: sc 56, ym 52, остальные 54', () => {
    expect(ICONS.sc?.likeArtSize).toBe(56)
    expect(ICONS.ym?.likeArtSize).toBe(52)
    for (const id of ['yt', 'vk', 'sp'] as const) expect(ICONS[id]?.likeArtSize).toBe(54)
  })

  it('корневой <svg> без width/height и скрыт от скринридера', () => {
    for (const s of SERVICES) {
      const icon = ICONS[s.id]
      if (!icon) continue
      for (const svg of [icon.badge, icon.plain, icon.mono]) {
        const root = /^<svg\b[^>]*>/.exec(svg)?.[0] ?? ''
        expect(root, s.id).not.toMatch(/\s(?:width|height)=/)
        expect(root, s.id).toContain('aria-hidden="true"')
      }
    }
  })

  it('Яндекс Музыка — прежняя разметка', () => {
    expect(ICONS.ym?.badge).toContain('<circle cx="12" cy="12" r="12" fill="#1c1c1e" />')
    expect(ICONS.ym?.badge).toContain('fill="#ffbc0d" transform="translate(2.5 4.62) scale(0.76)"')
    expect(ICONS.ym?.plain).toContain('fill="#ffbc0d" transform="translate(1.25 3.65) scale(0.86)"')
    expect(ICONS.ym?.mono).toContain('fill="currentColor" transform="translate(1.25 3.65) scale(0.86)"')
  })
})
