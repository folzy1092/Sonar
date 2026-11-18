import { describe, expect, it } from 'vitest'
import {
  MAX_DAYS,
  MAX_LIMIT,
  TEMPLATES,
  blankRules,
  cloneRules,
  defaultCondition,
  isSmartId,
  normalizeRules,
  parseRules,
  rulesProblem,
  type SmartField,
} from './smart'

const SERVICES = ['sc', 'ym', 'yt', 'vk', 'sp', 'local']

describe('умные плейлисты: шаблоны', () => {
  it('пять шаблонов из спеки, все правила корректны', () => {
    expect(TEMPLATES.map((t) => t.id)).toEqual(['forgotten', 'month_top', 'barely', 'worn_out', 'new_liked'])
    for (const tpl of TEMPLATES) expect(rulesProblem(tpl.rules, SERVICES), tpl.id).toBeNull()
  })

  it('пороги шаблонов совпадают со спекой', () => {
    const by = Object.fromEntries(TEMPLATES.map((t) => [t.id, t.rules]))
    expect(by.forgotten.conditions).toEqual([{ field: 'last_played', op: 'before', days: 60 }])
    expect(by.barely.conditions).toEqual([{ field: 'plays', op: 'lte', value: 2 }])
    expect(by.worn_out.conditions).toEqual([{ field: 'plays', days: 30, op: 'gte', value: 10 }])
    expect(by.new_liked.conditions).toEqual([{ field: 'added', days: 14 }])
    expect(by.month_top.source).toEqual({ kind: 'played' })
  })

  it('копия шаблона не меняет сам шаблон', () => {
    const copy = cloneRules(TEMPLATES[0].rules)
    copy.conditions.push(defaultCondition('artist'))
    expect(TEMPLATES[0].rules.conditions).toHaveLength(1)
  })
})

describe('умные плейлисты: нормализация', () => {
  it('числа зажимаются в границы, пробелы срезаются', () => {
    const r = normalizeRules({
      ...blankRules(),
      conditions: [
        { field: 'plays', days: 99999, op: 'gte', value: -3 },
        { field: 'last_played', op: 'after', days: 0 },
        { field: 'artist', op: 'is', value: '  Кино ' },
      ],
      limit: 5000,
    })
    expect(r.conditions[0]).toEqual({ field: 'plays', days: MAX_DAYS, op: 'gte', value: 0 })
    expect(r.conditions[1]).toEqual({ field: 'last_played', op: 'after', days: 1 })
    expect(r.conditions[2]).toEqual({ field: 'artist', op: 'is', value: 'Кино' })
    expect(r.limit).toBe(MAX_LIMIT)
  })

  it('0 дней у прослушиваний — за всё время, 0 в лимите — без лимита', () => {
    const r = normalizeRules({ ...blankRules(), conditions: [{ field: 'plays', days: 0, op: 'lte', value: 2 }], limit: 0 })
    expect(r.conditions[0]).toEqual({ field: 'plays', days: null, op: 'lte', value: 2 })
    expect(r.limit).toBeNull()
  })

  it('окно дней у сортировки остаётся только для прослушиваний', () => {
    expect(normalizeRules({ ...blankRules(), sort: { by: 'title', days: 30, desc: false } }).sort).toEqual({ by: 'title', days: null, desc: false })
    expect(normalizeRules({ ...blankRules(), sort: { by: 'plays', days: 30, desc: true } }).sort?.days).toBe(30)
  })
})

describe('умные плейлисты: проверка и разбор', () => {
  it('ловит пустого исполнителя, чужой сервис и не выбранный плейлист', () => {
    expect(rulesProblem({ ...blankRules(), conditions: [defaultCondition('artist')] }, SERVICES)).toBe('Впиши исполнителя')
    expect(rulesProblem({ ...blankRules(), conditions: [{ field: 'service', op: 'is', value: 'zz' }] }, SERVICES)).toBe('Выбери сервис')
    expect(rulesProblem({ ...blankRules(), source: { kind: 'playlist', id: '' } }, SERVICES)).toBe('Выбери плейлист')
    expect(rulesProblem({ ...blankRules(), v: 2 }, SERVICES)).toBe('Правила из новой версии Sonar')
  })

  it('условие по умолчанию есть у каждого поля', () => {
    const fields: SmartField[] = ['plays', 'last_played', 'added', 'service', 'artist', 'duration']
    for (const f of fields) expect(defaultCondition(f).field).toBe(f)
  })

  it('parseRules принимает свои правила и отвергает чужое', () => {
    expect(parseRules(TEMPLATES[1].rules)).toEqual({ ...TEMPLATES[1].rules, sort: TEMPLATES[1].rules.sort, limit: 50 })
    expect(parseRules({ v: 1, source: { kind: 'liked' } })?.conditions).toEqual([])
    expect(parseRules(null)).toBeNull()
    expect(parseRules({ v: 9, source: { kind: 'liked' }, conditions: [] })).toBeNull()
  })

  it('id умного плейлиста — по префиксу sm_', () => {
    expect(isSmartId('sm_01ABC')).toBe(true)
    expect(isSmartId('pl_01ABC')).toBe(false)
    expect(isSmartId(null)).toBe(false)
  })
})
