import { describe, expect, it } from 'vitest'
import { altLayouts, bestScore, cyrToEn, enToRu, enToUk, fuzzyScore, interleave, jumpGroup, normalize, rank, step, uniqueByRef, words } from './quick-core'

describe('раскладка', () => {
  it('английская → русская', () => {
    expect(enToRu('ghbdtn')).toBe('привет')
    expect(enToRu('vjz djkyf')).toBe('моя волна')
    expect(enToRu('nfqvth cyf')).toBe('таймер сна')
    expect(enToRu(',fcc')).toBe('басс')
    expect(enToRu('`krf')).toBe('ёлка')
  })
  it('регистр не важен', () => {
    expect(enToRu('GHBDTN')).toBe('привет')
  })
  it('английская → украинская', () => {
    expect(enToUk('ghbdsn')).toBe('привіт')
    expect(enToUk(']ed')).toBe('їув')
  })
  it('кириллица → английская (русская и украинская)', () => {
    expect(cyrToEn('руддщ')).toBe('hello')
    expect(cyrToEn('ьфтшя')).toBe('maniz')
    expect(cyrToEn('іїє')).toBe("s]'")
  })
  it('цифры и пробелы не трогает', () => {
    expect(enToRu('lj 2077')).toBe('до 2077')
  })
  it('варианты запроса — без самого запроса и без повторов', () => {
    expect(altLayouts('ghbdtn')).toContain('привет')
    expect(altLayouts('привет')).toEqual(['ghbdtn'])
    expect(altLayouts('2077')).toEqual([])
  })
})

describe('нормализация', () => {
  it('регистр, ё и пробелы', () => {
    expect(normalize('  Тёмная   ТЕМА ')).toBe('темная тема')
  })
  it('слова — буквы и цифры любого алфавита', () => {
    expect(words('Kendrick Lamar — HUMBLE.')).toEqual(['kendrick', 'lamar', 'humble'])
    expect(words('Моя волна: «Грустная»')).toEqual(['моя', 'волна', 'грустная'])
  })
})

describe('нечёткий поиск', () => {
  it('пустой запрос подходит всем', () => {
    expect(fuzzyScore('', 'Пауза')).toBe(0)
  })
  it('начало слова', () => {
    expect(fuzzyScore('пау', 'Пауза')).not.toBeNull()
    expect(fuzzyScore('волн', 'Моя волна')).not.toBeNull()
  })
  it('по началам нескольких слов', () => {
    expect(fuzzyScore('мв', 'Моя волна')).not.toBeNull()
    expect(fuzzyScore('мовол', 'Моя волна')).not.toBeNull()
    expect(fuzzyScore('тайм сна', 'Таймер сна')).not.toBeNull()
    expect(fuzzyScore('он', 'Открыть настройки')).not.toBeNull()
  })
  it('слова запроса — в любом порядке', () => {
    expect(fuzzyScore('сна тайм', 'Таймер сна')).not.toBeNull()
  })
  it('ё и е — одно и то же', () => {
    expect(fuzzyScore('темн', 'Тёмная тема')).not.toBeNull()
    expect(fuzzyScore('тёмн', 'Темная тема')).not.toBeNull()
  })
  it('середина слова — только от 3 букв и слабее начала', () => {
    expect(fuzzyScore('ол', 'Моя волна')).toBeNull()
    const mid = fuzzyScore('олна', 'Моя волна')
    const start = fuzzyScore('волна', 'Моя волна')
    expect(mid).not.toBeNull()
    expect(start! > mid!).toBe(true)
  })
  it('нет совпадения — null', () => {
    expect(fuzzyScore('xyz', 'Моя волна')).toBeNull()
    expect(fuzzyScore('пауза таймер', 'Пауза')).toBeNull()
  })
  it('точное и с первого слова — выше', () => {
    expect(fuzzyScore('пауза', 'Пауза')! > fuzzyScore('пауза', 'Пауза после трека')!).toBe(true)
    expect(fuzzyScore('волна', 'Волна офлайн')! > fuzzyScore('волна', 'Моя волна')!).toBe(true)
  })
  it('меньше кусков — выше', () => {
    expect(fuzzyScore('та', 'Таймер сна')! > fuzzyScore('тс', 'Таймер сна')!).toBe(true)
  })
  it('длинные названия не тормозят', () => {
    const long = Array.from({ length: 40 }, () => 'аааа').join(' ')
    const t0 = performance.now()
    expect(fuzzyScore('а'.repeat(30), long)).not.toBeNull()
    expect(performance.now() - t0).toBeLessThan(200)
  })
})

describe('счёт по раскладкам и порядок', () => {
  it('набрано не в той раскладке — находится', () => {
    expect(bestScore('ghbdtn', ['Привет'])).not.toBeNull()
    expect(bestScore('nfqv', ['Таймер сна'])).not.toBeNull()
    expect(bestScore('руддщ', ['Hello'])).not.toBeNull()
  })
  it('раскладка угадана — чуть ниже прямого совпадения', () => {
    expect(bestScore('привет', ['Привет'])! > bestScore('ghbdtn', ['Привет'])!).toBe(true)
  })
  it('лучшая из нескольких строк элемента', () => {
    expect(bestScore('dark', ['Тёмная тема', 'dark', 'тёмный'])).not.toBeNull()
  })
  it('сортирует лучшие первыми, неподходящие убирает', () => {
    const items = ['Моя волна', 'Волна офлайн', 'Пауза', 'Волна']
    expect(rank(items, 'волна', (s) => [s])).toEqual(['Волна', 'Волна офлайн', 'Моя волна'])
    expect(rank(items, 'djkyf', (s) => [s])[0]).toBe('Волна')
  })
  it('пустой запрос — всё как есть, с ограничением', () => {
    expect(rank(['б', 'а', 'в'], ' ', (s) => [s], 2)).toEqual(['б', 'а'])
  })
})

describe('клавиши списка', () => {
  it('стрелки — по кругу', () => {
    expect(step(0, -1, 3)).toBe(2)
    expect(step(2, 1, 3)).toBe(0)
    expect(step(0, 1, 0)).toBe(-1)
  })
  it('Tab — к следующей группе, Shift+Tab — к началу своей или к предыдущей', () => {
    const starts = [0, 3, 5]
    expect(jumpGroup(1, starts, false)).toBe(3)
    expect(jumpGroup(5, starts, false)).toBe(0)
    expect(jumpGroup(4, starts, true)).toBe(3)
    expect(jumpGroup(3, starts, true)).toBe(0)
    expect(jumpGroup(0, starts, true)).toBe(5)
    expect(jumpGroup(0, [], false)).toBe(-1)
  })
})

describe('результаты сервисов', () => {
  it('чередуются: первый из каждого, потом второй', () => {
    expect(interleave([['s1', 's2', 's3'], ['y1'], []])).toEqual(['s1', 'y1', 's2', 's3'])
    expect(interleave([])).toEqual([])
  })
  it('повторы по ref убираются, первый остаётся', () => {
    const list = [{ ref: 'a', n: 1 }, { ref: 'b', n: 2 }, { ref: 'a', n: 3 }]
    expect(uniqueByRef(list)).toEqual([{ ref: 'a', n: 1 }, { ref: 'b', n: 2 }])
  })
})
