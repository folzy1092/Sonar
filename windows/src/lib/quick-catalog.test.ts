import { describe, expect, it, vi } from 'vitest'
import { QUICK_ACTIONS, QUICK_GROUPS, QUICK_HINTS, QUICK_SETTINGS, SETTINGS_KEYWORDS, WAVE_MOOD_TITLE } from './quick-catalog'
import { SUBS, TABS } from '../pages/settings-section.svelte'
import quickOpenSource from '../app/QuickOpen.svelte?raw'
import quickSource from './quick.svelte.ts?raw'
import hotkeysSource from '../pages/settings/Hotkeys.svelte?raw'

vi.mock('./settings.svelte', () => ({ settings: { get: () => 'ru' } }))

const { dictionary } = await import('./i18n.svelte')

type Dict = Record<string, string>
const files = (mods: Record<string, unknown>): Record<string, Dict> =>
  Object.fromEntries(Object.entries(mods).map(([path, m]) => [path, (m as { default: Dict }).default]))

const FILES = {
  en: files(import.meta.glob('../i18n/en/*.ts', { eager: true })),
  uk: files(import.meta.glob('../i18n/uk/*.ts', { eager: true })),
}
const OWN = '/ctrlk.ts'
const CYRILLIC = /[А-Яа-яЁё]/

/** Строки `t('…')`, написанные прямо в исходнике. */
const literals = (source: string) => [...source.matchAll(/\bt\('([^']+)'/g)].map((m) => m[1])

/** Всё русское, что быстрое окно показывает через t(). */
function quickStrings(): string[] {
  const out = [
    ...QUICK_GROUPS.map((g) => g.title),
    ...QUICK_ACTIONS.map((a) => a.title),
    WAVE_MOOD_TITLE,
    ...QUICK_SETTINGS.flatMap((s) => [s.title, ...s.path]),
    ...Object.values(QUICK_HINTS).flatMap((h) => h.map(([, label]) => label)),
    ...[quickOpenSource, quickSource, hotkeysSource].flatMap(literals),
  ]
  return [...new Set(out.filter((x) => CYRILLIC.test(x)))]
}

describe('быстрое окно: данные', () => {
  it('ключевые слова — только у существующих разделов настроек', () => {
    const subs = new Set(TABS.flatMap((tab) => SUBS[tab.id].map((s) => s.id)))
    expect(Object.keys(SETTINGS_KEYWORDS).filter((id) => !subs.has(id))).toEqual([])
  })
  it('ключи строк уникальны, разделы «скоро» не попадают', () => {
    const keys = QUICK_SETTINGS.map((s) => s.key)
    expect(new Set(keys).size).toBe(keys.length)
    const soon = TABS.flatMap((tab) => SUBS[tab.id].filter((s) => s.soon || s.lock).map((s) => s.id))
    expect(QUICK_SETTINGS.filter((s) => soon.includes(s.sub))).toEqual([])
  })
  it('у строки внутри раздела путь — вкладка и раздел', () => {
    const row = QUICK_SETTINGS.find((s) => s.title === 'Быстрое окно')
    expect(row?.sub).toBe('hotkeys')
    expect(row?.path.length).toBeGreaterThan(0)
  })
  it('id действий не повторяются', () => {
    const ids = QUICK_ACTIONS.map((a) => a.id)
    expect(new Set(ids).size).toBe(ids.length)
  })
})

describe('быстрое окно: переводы', () => {
  it.each(['en', 'uk'] as const)('%s: у каждой строки есть перевод', (l) => {
    const dict = dictionary(l)
    expect(quickStrings().filter((k) => !dict[k]?.trim())).toEqual([])
  })

  it.each(['en', 'uk'] as const)('%s: ключи ctrlk.ts не повторяют другие словари', (l) => {
    const entries = Object.entries(FILES[l])
    const own = entries.find(([path]) => path.endsWith(OWN))
    expect(own, 'ctrlk.ts').toBeDefined()
    const others = new Set(entries.filter(([path]) => !path.endsWith(OWN)).flatMap(([, d]) => Object.keys(d)))
    expect(Object.keys(own![1]).filter((k) => others.has(k))).toEqual([])
  })

  it('ctrlk.ts в en и uk — одни и те же ключи', () => {
    const keys = (l: 'en' | 'uk') => Object.keys(Object.entries(FILES[l]).find(([path]) => path.endsWith(OWN))![1]).sort()
    expect(keys('en')).toEqual(keys('uk'))
  })
})
