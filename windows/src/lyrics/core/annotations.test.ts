import { describe, expect, it } from 'vitest'
import { likeness, mapAnnotations } from './annotations'

describe('аннотации Genius к строкам', () => {
  it('строки совпадают без учёта регистра, знаков и бэк-вокала', () => {
    expect(likeness('Жить этот момент, вокруг меня леса (Леса)', 'жить этот момент вокруг меня леса')).toBe(1)
    expect(likeness('Трясутся мои руки', 'Гуляю по ветру')).toBe(0)
  })

  it('аннотация фрагмента — только на его первой строке', () => {
    const lines = ['Жить этот момент, вокруг меня леса (леса)', 'Трясутся мои руки, трещит голова (а-а)', 'Давай оставим это на старых местах', 'Гуляю по ветру']
    const a = { lines: ['Жить этот момент, вокруг меня леса (Леса)', 'Трясутся мои руки, трещит голова (А-а)', 'Давай оставим это на старых местах'], body: 'Вся строфа', reviewed: false }
    const m = mapAnnotations(lines, [a])
    expect([...m.keys()]).toEqual([0])
    expect(m.get(0)?.body).toBe('Вся строфа')
  })

  it('первая строка занята другой аннотацией — встаёт на следующую строку фрагмента', () => {
    const lines = ['Раз два три', 'Четыре пять шесть', 'Семь восемь девять']
    const one = { lines: ['Раз два три'], body: 'Первая', reviewed: false }
    const two = { lines: ['Раз два три', 'Четыре пять шесть'], body: 'Вторая', reviewed: false }
    const m = mapAnnotations(lines, [one, two])
    expect(m.get(0)?.body).toBe('Первая')
    expect(m.get(1)?.body).toBe('Вторая')
    expect(m.get(2)).toBeUndefined()
  })
})
