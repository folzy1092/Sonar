import { describe, expect, test } from 'vitest'
import { autoplayFromPool, availableOnly, imageSrc, isAvailable, searchOffline, uniqueByRef } from './offline-core'

const tr = (ref: string, title = ref, artist = 'a', album?: string) => ({
  ref,
  title,
  artist,
  album: album ? { title: album } : null,
})

describe('офлайн: фильтры', () => {
  const refs = new Set(['sc:1', 'local:2'])

  test('выключенный режим пропускает всё', () => {
    expect(isAvailable('ym:9', false, refs)).toBe(true)
    expect(availableOnly([tr('ym:9')], false, refs)).toHaveLength(1)
  })

  test('включённый оставляет только доступное, порядок сохраняется', () => {
    expect(isAvailable('ym:9', true, refs)).toBe(false)
    expect(availableOnly([tr('local:2'), tr('ym:9'), tr('sc:1')], true, refs).map((t) => t.ref)).toEqual(['local:2', 'sc:1'])
  })

  test('повторы по ref убираются', () => {
    expect(uniqueByRef([tr('a'), tr('b'), tr('a')]).map((t) => t.ref)).toEqual(['a', 'b'])
  })
})

describe('офлайн: поиск', () => {
  const pool = [tr('1', 'Numb', 'Linkin Park', 'Meteora'), tr('2', 'Кукла колдуна', 'Король и Шут'), tr('1', 'Numb', 'Linkin Park')]

  test('все слова в любом поле, без учёта регистра и без повторов', () => {
    expect(searchOffline(pool, 'linkin  NUMB', 10).map((t) => t.ref)).toEqual(['1'])
    expect(searchOffline(pool, 'meteora', 10).map((t) => t.ref)).toEqual(['1'])
    expect(searchOffline(pool, 'король кукла', 10).map((t) => t.ref)).toEqual(['2'])
  })

  test('пустой запрос и лимит', () => {
    expect(searchOffline(pool, '   ', 10)).toEqual([])
    expect(searchOffline([tr('a', 'x'), tr('b', 'x')], 'x', 1)).toHaveLength(1)
  })
})

describe('офлайн: автопродолжение', () => {
  test('без треков из очереди и «не нравится», не больше n', () => {
    const pool = ['a', 'b', 'c', 'd', 'a'].map((r) => tr(r))
    const got = autoplayFromPool(pool, new Set(['a']), (r) => r === 'b', 5, () => 0)
    expect(got.map((t) => t.ref).sort()).toEqual(['c', 'd'])
    expect(autoplayFromPool(pool, new Set(), () => false, 2, () => 0.5)).toHaveLength(2)
  })

  test('нечего добавить — пусто', () => {
    expect(autoplayFromPool([tr('a')], new Set(['a']), () => false, 3)).toEqual([])
  })
})

describe('офлайн: картинки', () => {
  const cdn = 'https://i1.sndcdn.com/artworks-1-t500x500.jpg'

  test('в сети адрес не трогаем', () => {
    expect(imageSrc(cdn, false, 4242)).toBe(cdn)
  })

  test('в офлайне чужой адрес идёт через локальный /cover', () => {
    expect(imageSrc(cdn, true, 4242)).toBe(`http://127.0.0.1:4242/cover?u=${encodeURIComponent(cdn)}`)
  })

  test('порт ещё не известен — картинки нет, запроса тоже', () => {
    expect(imageSrc(cdn, true, null)).toBeUndefined()
  })

  test('локальное, data:, ресурсы сборки и пустое — как есть', () => {
    expect(imageSrc('http://127.0.0.1:4242/cover?u=x', true, 1)).toBe('http://127.0.0.1:4242/cover?u=x')
    expect(imageSrc('data:image/png;base64,AA', true, 1)).toBe('data:image/png;base64,AA')
    expect(imageSrc('/assets/logo.svg', true, 1)).toBe('/assets/logo.svg')
    expect(imageSrc('', true, 1)).toBeUndefined()
    expect(imageSrc(null, true, 1)).toBeUndefined()
  })
})
