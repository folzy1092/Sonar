// Каждая строка интерфейса сайта переведена на en, uk, es, de и pl: тест собирает ключи из `t('…')` / `tn(n, '…')` в
// исходниках и из данных (FAQ, документы, тарифы, скриншоты, статус) и сверяет со словарями.
import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, test } from 'vitest'
import { DICTS } from '.'
import { FAQ } from '../content/faq'
import { LEGAL_DOCS } from '../content/legal'
import { LICENSE_GROUPS } from '../content/licenses'
import { SERVICE_NAMES } from '../lib/services'
import { PERKS } from '../lib/plans'
import { SERVICE_GROUPS, SONAR_ROWS } from '../lib/status'
import shots from '../../data/shots.json'

const SRC = join(__dirname, '..')
const CYRILLIC = /[А-Яа-яЁёІіЇїЄєҐґ]/
const PLACEHOLDER = /\{(\w+)\}/g
const FORMS = { en: 2, uk: 3, es: 2, de: 2, pl: 3 } as const

function sourceFiles(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = join(dir, e.name)
    if (e.isDirectory()) return sourceFiles(p)
    return /\.(astro|ts)$/.test(e.name) && !e.name.endsWith('.test.ts') ? [p] : []
  })
}

const unescape = (s: string) => s.replace(/\\(['"`\\])/g, '$1')

/** Ключи из литералов: `t('…')`, `t("…")`, `tn(x, '…')`. */
function literalKeys(code: string): string[] {
  const keys: string[] = []
  const re = /\b(?:t\(\s*|tn\([^,()]+(?:\([^()]*\))?[^,()]*,\s*)(['"])((?:\\.|(?!\1).)*)\1/g
  for (const m of code.matchAll(re)) keys.push(unescape(m[2]))
  return keys
}

function dataKeys(): string[] {
  const legal = Object.values(LEGAL_DOCS).flatMap((d) => [
    d.title,
    d.lead,
    d.description,
    ...d.sections.flatMap((s) => [s.title, ...s.blocks.flatMap((b) => (typeof b === 'string' ? [b] : b.list))]),
  ])
  return [
    ...FAQ.flatMap((g) => [g.title, ...g.items.flatMap((i) => [i.q, ...i.a])]),
    ...legal,
    ...LICENSE_GROUPS.flatMap((g) => [g.title, ...g.items.flatMap((i) => (i.note ? [i.note] : []))]),
    ...Object.values(SERVICE_NAMES),
    ...PERKS,
    ...shots.shots.map((s) => s.alt),
    ...SONAR_ROWS.map((r) => r.name),
    ...SERVICE_GROUPS.flatMap((g) => [g.title, ...g.rows.map((r) => r.name)]),
  ]
}

const KEYS = [
  ...new Set([...sourceFiles(SRC).flatMap((f) => literalKeys(readFileSync(f, 'utf8'))), ...dataKeys()]),
].filter((k) => CYRILLIC.test(k))

const placeholders = (s: string) => [...new Set([...s.matchAll(PLACEHOLDER)].map((m) => m[1]))].sort()

describe.each(['en', 'uk', 'es', 'de', 'pl'] as const)('словарь %s', (lang) => {
  const dict = DICTS[lang]

  test('сборщик нашёл строки', () => {
    expect(KEYS.length).toBeGreaterThan(300)
  })

  test('все строки переведены', () => {
    expect(KEYS.filter((k) => !(k in dict))).toEqual([])
  })

  test('нет лишних ключей', () => {
    const used = new Set(KEYS)
    expect(Object.keys(dict).filter((k) => !used.has(k))).toEqual([])
  })

  test('подстановки {…} совпадают', () => {
    const bad = KEYS.filter((k) => k in dict).filter(
      (k) => placeholders(k.replace(/^[^:]*::/, '')).join() !== placeholders(dict[k]).join(),
    )
    expect(bad).toEqual([])
  })

  test('у множественного числа нужное число форм', () => {
    const plural = KEYS.filter((k) => k.includes('|') && k in dict)
    expect(plural.filter((k) => dict[k].split('|').length !== FORMS[lang])).toEqual([])
  })

  test('перевод не пустой и без кириллицы (кроме uk)', () => {
    const bad = Object.entries(dict).filter(([, v]) => !v.trim() || (lang !== 'uk' && CYRILLIC.test(v)))
    expect(bad).toEqual([])
  })
})
