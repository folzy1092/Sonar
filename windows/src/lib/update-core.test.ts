import { describe, expect, it } from 'vitest'
import { agoText, compareVersions, noteLines, parseChangelog, sizeText } from './update-core'

describe('compareVersions', () => {
  it('сравнивает Г.О.Ф по частям', () => {
    expect(compareVersions('0.1.0', '0.1.0')).toBe(0)
    expect(compareVersions('0.1.1', '0.1.0')).toBeGreaterThan(0)
    expect(compareVersions('0.2.0', '0.10.0')).toBeLessThan(0)
    expect(compareVersions('v1.0', '0.9.9')).toBeGreaterThan(0)
    expect(compareVersions('1.0', '1.0.0')).toBe(0)
  })
})

describe('parseChangelog', () => {
  it('берёт Windows и общие записи, новые сверху', () => {
    const list = parseChangelog([
      { version: '0.1.0', date: '2026-11-15', changes: ['Первая версия'] },
      { version: '0.2.0', date: '2026-12-01', platform: 'ios', changes: ['iOS'] },
      { version: '0.1.1', date: '2026-11-20', platform: 'windows', changes: ['Фикс', ''] },
      { nope: true },
      null,
    ])
    expect(list.map((e) => e.version)).toEqual(['0.1.1', '0.1.0'])
    expect(list[0].changes).toEqual(['Фикс'])
  })
  it('не массив — пусто', () => {
    expect(parseChangelog({})).toEqual([])
  })
})

describe('noteLines', () => {
  it('режет маркеры списка и пустые строки', () => {
    expect(noteLines('- Раз\n\n• Два\r\n3) Три\nЧетыре')).toEqual(['Раз', 'Два', 'Три', 'Четыре'])
    expect(noteLines(undefined)).toEqual([])
  })
})

describe('agoText и sizeText', () => {
  it('пишет по-человечески', () => {
    const now = 10 * 86_400_000
    expect(agoText(now - 10_000, now)).toBe('только что')
    expect(agoText(now - 5 * 60_000, now)).toBe('5 мин назад')
    expect(agoText(now - 3 * 3_600_000, now)).toBe('3 ч назад')
    expect(agoText(now - 2 * 86_400_000, now)).toBe('2 дн назад')
    expect(sizeText(1_048_576 * 1.5, 1_048_576 * 18)).toBe('1.5 из 18.0 МБ')
    expect(sizeText(0, null)).toBe('0.0 МБ')
  })
})
