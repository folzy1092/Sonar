/// <reference types="node" />
import { existsSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it, vi } from 'vitest'

vi.mock('./settings.svelte', () => ({ settings: { get: () => 'ru' } }))

const { APP_ICONS, DEFAULT_APP_ICON, appIconOr, appIconSrc, isAppIcon } = await import('./app-icons')
const { dictionary } = await import('./i18n.svelte')

const here = dirname(fileURLToPath(import.meta.url))
const BRAND = resolve(here, '../../../brand/app-icons')
const PUBLIC = resolve(here, '../../public/app-icons')
const RUST = resolve(here, '../../src-tauri')

describe('значки приложения', () => {
  it('основной — «Стекло», он первый, id не повторяются', () => {
    expect(DEFAULT_APP_ICON).toBe('glass')
    expect(APP_ICONS[0].id).toBe(DEFAULT_APP_ICON)
    expect(new Set(APP_ICONS.map((i) => i.id)).size).toBe(APP_ICONS.length)
  })

  it('незнакомый id — основной значок', () => {
    expect(isAppIcon('puff')).toBe(true)
    expect(isAppIcon('nope')).toBe(false)
    expect(appIconOr('nope')).toBe('glass')
    expect(appIconOr(undefined)).toBe('glass')
    expect(appIconOr('echo')).toBe('echo')
    expect(appIconSrc('well')).toBe('/app-icons/well.png')
  })

  it('те же значки, что в генераторе бренда (brand/app-icons/icons.json)', () => {
    const made = JSON.parse(readFileSync(resolve(BRAND, 'icons.json'), 'utf8')) as { default: string; icons: { id: string }[] }
    expect(made.default).toBe(DEFAULT_APP_ICON)
    expect(made.icons.map((i) => i.id)).toEqual(APP_ICONS.map((i) => i.id))
  })

  it('у каждого есть исходник, плитка для настроек и значки для окна и трея', () => {
    for (const { id } of APP_ICONS) {
      for (const f of [resolve(BRAND, `${id}.svg`), resolve(PUBLIC, `${id}.png`), resolve(RUST, `icons/app/${id}-64.png`), resolve(RUST, `icons/app/${id}-32.png`)]) {
        expect(existsSync(f), f).toBe(true)
      }
    }
  })

  it('Rust знает те же id (app_icon.rs держит и свой тест на порядок)', () => {
    const rs = readFileSync(resolve(RUST, 'src/app_icon.rs'), 'utf8')
    const listed = [...rs.matchAll(/icon!\("([a-z]+)"\)/g)].map((m) => m[1])
    expect(listed).toEqual(APP_ICONS.map((i) => i.id))
  })

  it('названия переведены на все языки', () => {
    for (const l of ['en', 'uk', 'es', 'de', 'pl'] as const) {
      const dict = dictionary(l)
      for (const { title } of APP_ICONS) expect(dict[title], `${l}: ${title}`).toBeTruthy()
    }
  })
})
