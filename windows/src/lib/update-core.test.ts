import { describe, expect, it } from 'vitest'
import { agoText, cleanChange, compareVersions, isBeta, mergeReleases, noteLines, parseChangelog, pendingEntries, releaseNotes, sizeText } from './update-core'

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

describe('бета и ожидающие записи', () => {
  it('узнаёт бета-сборки', () => {
    expect(isBeta('0.2.0-beta.1')).toBe(true)
    expect(isBeta('0.2.0-rc1')).toBe(true)
    expect(isBeta('0.1.25')).toBe(false)
  })
  it('берёт записи между установленной и найденной версией', () => {
    const log = parseChangelog([
      { version: '0.3.0', changes: ['c'] },
      { version: '0.2.0', changes: ['b'] },
      { version: '0.1.1', changes: ['a'] },
    ])
    expect(pendingEntries(log, '0.1.1', '0.2.5').map((e) => e.version)).toEqual(['0.2.0'])
    expect(pendingEntries(log, '0.1.0', '0.3.0').map((e) => e.version)).toEqual(['0.3.0', '0.2.0', '0.1.1'])
  })
})

describe('история версий из релизов', () => {
  it('добавляет авто-патчи, changelog главнее, служебный релиз мимо', () => {
    const log = parseChangelog([{ version: '0.1.1', title: 'Плавнее', changes: ['a'] }])
    const all = mergeReleases(log, [
      { tag_name: 'windows-v0.1.55', published_at: '2026-11-16T20:00:00Z', body: '- windows: эквалайзер\n- вкладки' },
      { tag_name: 'windows-v0.1.1', body: '- дубль' },
      { tag_name: 'windows-latest', body: 'служебный' },
      { tag_name: 'windows-v0.1.42', published_at: '2026-11-16T10:00:00Z', body: '' },
    ])
    expect(all.map((e) => e.version)).toEqual(['0.1.55', '0.1.42', '0.1.1'])
    expect(all[0].changes).toEqual(['Windows: эквалайзер', 'Вкладки'])
    expect(all[0].date).toBe('2026-11-16')
    expect(all[2].title).toBe('Плавнее')
  })
})

describe('пункты для людей', () => {
  it('служебные коммиты мимо, тип коммита снят, первая буква заглавная', () => {
    expect(cleanChange('updates: iOS — объявлена сборка 0.1.0 (655) [skip ci]')).toBeNull()
    expect(cleanChange('docs: сведение отмечено [skip ci]')).toBeNull()
    expect(cleanChange('Merge remote-tracking branch origin/main')).toBeNull()
    expect(cleanChange('chore(deps): обновить зависимости')).toBeNull()
    expect(cleanChange('feat: «Сведение» в составе Sonar Deep — ПК, iPhone, сайт')).toBe('«Сведение» в составе Sonar Deep — ПК, iPhone, сайт')
    expect(cleanChange('fix(ios): сведение анализирует HLS')).toBe('Сведение анализирует HLS')
    expect(cleanChange('feat!: новый плеер')).toBe('Новый плеер')
    expect(cleanChange('feat: ')).toBeNull()
    expect(cleanChange('Плавнее переходы')).toBe('Плавнее переходы')
  })

  it('заметки релиза как на скрине владельца', () => {
    const body = '- feat: «Сведение» в составе Sonar Deep — ПК, iPhone, сайт\n- updates: iOS — объявлена сборка 0.1.0 (655) [skip ci]'
    expect(releaseNotes(body)).toEqual(['«Сведение» в составе Sonar Deep — ПК, iPhone, сайт'])
  })
})
