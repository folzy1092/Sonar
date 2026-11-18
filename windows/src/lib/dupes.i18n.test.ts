import { describe, expect, it } from 'vitest'
import dupesPage from '../pages/DupesPage.svelte?raw'
import library from './library.svelte.ts?raw'
import enDupes from '../i18n/en/dupes'
import ukDupes from '../i18n/uk/dupes'

type Dict = Record<string, string>
/** Все словари языка вместе: общие строки («Любимые», «Назад») лежат в других файлах. */
const merged = (mods: Record<string, unknown>): Dict => Object.assign({}, ...Object.values(mods).map((m) => (m as { default: Dict }).default))
const en = merged(import.meta.glob('../i18n/en/*.ts', { eager: true }))
const uk = merged(import.meta.glob('../i18n/uk/*.ts', { eager: true }))

/** Все `t('…')` экрана дублей и всплывашки «Убрано · Отменить». */
function keys(...sources: string[]): string[] {
  const found = sources.flatMap((s) => [...s.matchAll(/\bt\('((?:[^'\\]|\\.)*)'/g)].map((m) => m[1]))
  return [...new Set(found)]
}

describe('переводы экрана дублей', () => {
  const dupeKeys = keys(dupesPage).concat(['Найти дубли', 'Убрано {tracks}', 'Отменить', 'Вернул {tracks}', 'Нечего возвращать'])

  it('каждая строка экрана есть в en и uk', () => {
    for (const key of dupeKeys) {
      expect(en, `en: ${key}`).toHaveProperty([key])
      expect(uk, `uk: ${key}`).toHaveProperty([key])
    }
  })

  it('строки всплывашки из медиатеки тоже переведены', () => {
    const toast = keys(library).filter((k) => /Убрано|Вернул|Нечего (убирать|возвращать)|Отменить/.test(k))
    expect(toast.length).toBe(5)
    for (const key of toast) expect(en, key).toHaveProperty([key])
  })

  it('подстановки в переводах те же, что в русской строке', () => {
    const slots = (s: string) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort()
    for (const dict of [enDupes, ukDupes]) for (const [ru, tr] of Object.entries(dict)) expect(slots(tr), ru).toEqual(slots(ru))
  })
})
