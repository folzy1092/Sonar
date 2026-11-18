import { describe, expect, test } from 'vitest'
import { FAQ } from '../content/faq'
import { matches, normalize, parseInline, plainText } from './faq'

describe('parseInline', () => {
  test('splits text and links, marks external ones', () => {
    // Arrange
    const src = 'Смотри [вопросы](/faq#ios) и [канал](https://t.me/SonarUpdates).'

    // Act
    const parts = parseInline(src)

    // Assert
    expect(parts).toEqual([
      { kind: 'text', text: 'Смотри ' },
      { kind: 'link', text: 'вопросы', href: '/faq#ios', external: false },
      { kind: 'text', text: ' и ' },
      { kind: 'link', text: 'канал', href: 'https://t.me/SonarUpdates', external: true },
      { kind: 'text', text: '.' },
    ])
  })

  test('returns plain text when there are no links', () => {
    expect(parseInline('просто текст')).toEqual([{ kind: 'text', text: 'просто текст' }])
  })

  test('plainText drops link syntax but keeps the words', () => {
    expect(plainText('Открой [Releases](https://x.y)')).toBe('Открой Releases')
  })
})

describe('matches', () => {
  test('empty query matches everything', () => {
    expect(matches('что угодно', '  ')).toBe(true)
  })

  test('every query word must appear, case and ё-insensitive', () => {
    expect(matches('Белый экран при запуске', 'экран БЕЛЫЙ')).toBe(true)
    expect(matches('Ещё вопрос', 'еще')).toBe(true)
    expect(matches('Белый экран', 'чёрный экран')).toBe(false)
  })

  test('punctuation in the query is ignored', () => {
    expect(normalize('  SmartScreen, антивирус!  ')).toBe('smartscreen антивирус')
    expect(matches('Предупреждение SmartScreen', 'smartscreen?')).toBe(true)
  })
})

describe('FAQ data', () => {
  const items = FAQ.flatMap((g) => g.items)

  test('anchors are unique and URL-safe', () => {
    const ids = items.map((i) => i.id)
    expect(new Set(ids).size).toBe(ids.length)
    for (const id of ids) expect(id).toMatch(/^[a-z0-9-]+$/)
  })

  test('anchors linked from the site exist', () => {
    const ids = new Set(items.map((i) => i.id))
    for (const id of ['ios', 'smartscreen', 'delete', 'report']) expect(ids.has(id)).toBe(true)
  })

  test('internal links in answers point to faq anchors that exist', () => {
    const ids = new Set(items.map((i) => i.id))
    for (const item of items) {
      for (const p of item.a) {
        for (const part of parseInline(p)) {
          if (part.kind !== 'link') continue
          const m = /^\/faq#(.+)$/.exec(part.href) ?? /^#(.+)$/.exec(part.href)
          if (m) expect(ids.has(m[1])).toBe(true)
        }
      }
    }
  })
})
