import { describe, expect, it, vi } from 'vitest'
import { SERVICES } from './services'

let current = 'ru'
vi.mock('./settings.svelte', () => ({ settings: { get: () => current } }))

const { t, dictionary } = await import('./i18n.svelte')

type Dict = Record<string, string>
const files = (mods: Record<string, unknown>): Record<string, Dict> =>
  Object.fromEntries(Object.entries(mods).map(([path, m]) => [path, (m as { default: Dict }).default]))

const FILES = {
  en: files(import.meta.glob('../i18n/en/*.ts', { eager: true })),
  uk: files(import.meta.glob('../i18n/uk/*.ts', { eager: true })),
}

const CYRILLIC = /[А-Яа-яЁё]/

/** Все русские строки, до которых интерфейс доходит из реестра. */
function registryStrings(): string[] {
  const out = SERVICES.flatMap((s) => [
    s.name,
    s.short,
    s.nameIn,
    s.openIn,
    s.status.connectedAs,
    s.status.connected,
    s.status.disconnected,
    s.loginLabel,
    s.loginBusyLabel,
    s.reloginLabel,
    s.keyReplaceLabel,
    ...s.keyFields.flatMap((f) => [f.label, f.placeholder]),
    ...(s.keyHint ?? []).map((p) => ('text' in p ? p.text : null)),
  ])
  return [...new Set(out.filter((x): x is string => typeof x === 'string' && CYRILLIC.test(x)))]
}

describe('переводы реестра сервисов', () => {
  it.each(['en', 'uk'] as const)('%s: у каждой русской строки реестра есть перевод', (l) => {
    const dict = dictionary(l)
    const missing = registryStrings().filter((k) => !dict[k]?.trim())
    expect(missing).toEqual([])
  })

  it('t() переводит строки sc/ym, как раньше', () => {
    current = 'en'
    expect(t('Яндекс Музыка')).toBe('Yandex Music')
    expect(t('SoundCloud')).toBe('SoundCloud')
    expect(t('Подключена как {name}', { name: 'Анна' })).toBe('Connected as Анна')
    current = 'ru'
    expect(t('Яндекс Музыка')).toBe('Яндекс Музыка')
  })

  it('короткая метка «Я» одинакова на всех языках', () => {
    for (const l of ['ru', 'en', 'uk']) {
      current = l
      expect(t('Я')).toBe('Я')
    }
  })

  it.each(['en', 'uk'] as const)('%s: ключи services.ts не повторяют ключи других словарей', (l) => {
    const entries = Object.entries(FILES[l])
    const own = entries.find(([path]) => path.endsWith('/services.ts'))
    expect(own, 'services.ts').toBeDefined()
    const others = new Set(entries.filter(([path]) => !path.endsWith('/services.ts')).flatMap(([, d]) => Object.keys(d)))
    const dup = Object.keys(own![1]).filter((k) => others.has(k))
    expect(dup).toEqual([])
  })

  it('services.ts в en и uk — одни и те же ключи', () => {
    const keys = (l: 'en' | 'uk') =>
      Object.keys(Object.entries(FILES[l]).find(([path]) => path.endsWith('/services.ts'))![1]).sort()
    expect(keys('en')).toEqual(keys('uk'))
  })
})
