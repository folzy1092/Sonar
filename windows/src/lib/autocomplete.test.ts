import { describe, expect, it } from 'vitest'
import { buildCandidates, canSuggest, decideKey, likedArtists, MAX_CANDIDATE, suggest, type CandidateSources, type FieldState } from './autocomplete'

const track = (title: string, ...artists: string[]) => ({ title, artist: artists.join(', '), artists: artists.map((name) => ({ name })) })
const empty: CandidateSources = { liked: [], history: [], recent: [] }
const atEnd = (value: string): FieldState => ({ value, selectionStart: value.length, selectionEnd: value.length, composing: false })

describe('кандидаты', () => {
  it('артисты Любимых — по числу лайкнутых треков, при равенстве — по порядку', () => {
    const liked = [track('a', 'Onda Andar'), track('b', 'Lil Peep'), track('c', 'Lil Peep', 'Onda Andar'), track('d', 'Lil Peep'), track('e', 'Burial')]
    expect(likedArtists(liked)).toEqual(['Lil Peep', 'Onda Andar', 'Burial'])
  })

  it('без списка артистов — берётся строка artist', () => {
    expect(likedArtists([{ title: 't', artist: 'Mareux' }])).toEqual(['Mareux'])
  })

  it('порядок: Любимые → история → недавнее, без дублей без учёта регистра', () => {
    const list = buildCandidates({
      liked: [track('x', 'Onda Andar')],
      history: [
        { kind: 'query', query: 'onda andar' },
        { kind: 'artist', query: 'on', title: 'Onyx' },
        { kind: 'track', query: 'n', title: 'Night Drive' },
      ],
      recent: [track('Opal', 'Four Tet')],
    })
    expect(list).toEqual(['Onda Andar', 'Onyx', 'Night Drive', 'Four Tet', 'Opal'])
  })

  it('пустые и длиннее 60 символов пропускаются', () => {
    const long = 'L'.repeat(MAX_CANDIDATE + 1)
    const list = buildCandidates({
      ...empty,
      history: [
        { kind: 'query', query: '  ' },
        { kind: 'query', query: long },
        { kind: 'album', query: 'q', title: null },
        { kind: 'query', query: 'Lo' },
      ],
    })
    expect(list).toEqual(['Lo'])
  })

  it('пустая медиатека и история — пустой список и нет подсказки', () => {
    expect(buildCandidates(empty)).toEqual([])
    expect(suggest([], 'onda')).toBeNull()
  })
})

describe('подсказка', () => {
  const list = ['Onda Andar', 'Lil Peep', 'Onyx', 'Лето']

  it('первый подходящий по приоритету выигрывает', () => {
    expect(suggest(list, 'On')?.full).toBe('Onda Andar')
    expect(suggest(list, 'Ony')?.full).toBe('Onyx')
  })

  it('регистр не важен: набранное — как набрал, хвост — в регистре оригинала', () => {
    expect(suggest(list, 'onda')).toEqual({ full: 'Onda Andar', tail: ' Andar', relayout: false })
    expect(suggest(list, 'ONDA A')).toEqual({ full: 'Onda Andar', tail: 'ndar', relayout: false })
  })

  it('только по началу всей строки: по второму слову подсказки нет', () => {
    expect(suggest(list, 'peep')).toBeNull()
  })

  it('меньше двух символов — нет подсказки', () => {
    expect(suggest(list, 'O')).toBeNull()
    expect(suggest(list, ' O')).toBeNull()
  })

  it('набрано целиком — дописывать нечего', () => {
    expect(suggest(list, 'onyx')).toBeNull()
  })

  it('русская раскладка вместо английской: «щтвф» → Onda Andar, заменить весь текст', () => {
    expect(suggest(list, 'щтвф')).toEqual({ full: 'Onda Andar', tail: '', relayout: true })
    expect(suggest(list, 'ЩТВФ')?.full).toBe('Onda Andar')
  })

  it('украинская раскладка: і на месте s', () => {
    expect(suggest(['Sigur Ros'], 'іш')).toEqual({ full: 'Sigur Ros', tail: '', relayout: true })
  })

  it('английская раскладка вместо русской: «ktn» → Лето', () => {
    expect(suggest(list, 'ktn')?.full).toBe('Лето')
  })

  it('прямое совпадение важнее раскладки', () => {
    expect(suggest(['Лил', 'Kto'], 'kt')?.full).toBe('Kto')
  })
})

describe('когда показывать', () => {
  it('курсор в конце, без выделения и IME — можно', () => {
    expect(canSuggest(atEnd('onda'))).toBe(true)
  })
  it('курсор не в конце — нельзя', () => {
    expect(canSuggest({ ...atEnd('onda'), selectionStart: 2, selectionEnd: 2 })).toBe(false)
  })
  it('есть выделение — нельзя', () => {
    expect(canSuggest({ ...atEnd('onda'), selectionStart: 0 })).toBe(false)
  })
  it('идёт ввод через IME — нельзя', () => {
    expect(canSuggest({ ...atEnd('onda'), composing: true })).toBe(false)
  })
})

describe('клавиши', () => {
  const s = suggest(['Onda Andar'], 'onda')
  const f = atEnd('onda')

  it('Tab и → принимают подсказку целиком', () => {
    expect(decideKey('Tab', f, s)).toEqual({ kind: 'accept', value: 'Onda Andar' })
    expect(decideKey('ArrowRight', f, s)).toEqual({ kind: 'accept', value: 'Onda Andar' })
  })

  it('раскладка: принятие заменяет весь текст на правильный', () => {
    expect(decideKey('Tab', atEnd('щтвф'), suggest(['Onda Andar'], 'щтвф'))).toEqual({ kind: 'accept', value: 'Onda Andar' })
  })

  it('Enter ищет набранное, а не подсказку', () => {
    expect(decideKey('Enter', f, s)).toEqual({ kind: 'search', value: 'onda' })
  })

  it('Esc убирает подсказку; без подсказки — как обычно', () => {
    expect(decideKey('Escape', f, s)).toEqual({ kind: 'dismiss' })
    expect(decideKey('Escape', f, null)).toEqual({ kind: 'pass' })
  })

  it('Tab без подсказки, Shift+Tab, Ctrl+→ и Backspace — не наши', () => {
    expect(decideKey('Tab', f, null)).toEqual({ kind: 'pass' })
    expect(decideKey('Tab', f, s, { shift: true })).toEqual({ kind: 'pass' })
    expect(decideKey('ArrowRight', f, s, { ctrl: true })).toEqual({ kind: 'pass' })
    expect(decideKey('Backspace', f, s)).toEqual({ kind: 'pass' })
  })

  it('курсор не в конце — → двигает курсор, подсказка не принимается', () => {
    expect(decideKey('ArrowRight', { ...f, selectionStart: 1, selectionEnd: 1 }, s)).toEqual({ kind: 'pass' })
  })
})
