import { describe, expect, it, vi } from 'vitest'

vi.mock('./api', () => ({ api: {} }))

const { CATALOG, RUST_KEYS, SUB_LEADS, markRanges, normalize, searchSettings, titleMatches } = await import('./settings-catalog')
const { DEFAULTS } = await import('./settings.svelte')
const { SUBS, TABS } = await import('../pages/settings-section.svelte')

const same = (s: string) => s

describe('каталог настроек', () => {
  it('каждый пункт ведёт в существующий раздел и подраздел', () => {
    for (const e of CATALOG) {
      expect(TABS.some((tb) => tb.id === e.tab), e.title).toBe(true)
      expect(SUBS[e.tab].some((s) => s.id === e.sub), `${e.title}: ${e.sub}`).toBe(true)
    }
  })

  it('ключи настроек — те же, что в DEFAULTS (SETTINGS.md), или настройки Rust', () => {
    for (const e of CATALOG) {
      if (!e.key) continue
      const known = e.key in DEFAULTS || RUST_KEYS.includes(e.key)
      expect(known, e.key).toBe(true)
    }
  })

  it('у каждого подраздела есть строка «что это меняет»', () => {
    for (const tab of TABS) for (const s of SUBS[tab.id]) expect(SUB_LEADS[s.id], s.id).toBeTruthy()
  })

  it('пункт с ключом встречается один раз', () => {
    const keys = CATALOG.flatMap((e) => (e.key ? [`${e.sub}:${e.key}`] : []))
    expect(new Set(keys).size).toBe(keys.length)
  })
})

describe('поиск по настройкам', () => {
  it('нормализует регистр и ё', () => {
    expect(normalize('  Тёмная ТЕМА ')).toBe('темная тема')
  })

  it('пустой запрос — пусто', () => {
    expect(searchSettings('', same)).toEqual([])
    expect(searchSettings('   ', same)).toEqual([])
  })

  it('находит по названию и ставит совпадение с начала выше', () => {
    const hits = searchSettings('кроссфейд', same)
    expect(hits[0].entry.key).toBe('audio.crossfade')
    expect(hits.every((h) => h.entry.sub === 'audio')).toBe(true)
  })

  it('находит по подсказке и по словам-синонимам', () => {
    expect(searchSettings('трей', same).some((h) => h.entry.key === 'system.tray')).toBe(true)
    expect(searchSettings('громкость', same).some((h) => h.entry.key === 'audio.normalize')).toBe(true)
  })

  it('все слова запроса должны найтись', () => {
    const hits = searchSettings('позиция вкладок', same)
    expect(hits[0].entry.key).toBe('tabs.position')
    expect(searchSettings('позиция абракадабра', same)).toEqual([])
  })

  it('ищет и по переводу, и по русскому оригиналу', () => {
    const en = (s: string) => (s === 'Кроссфейд' ? 'Crossfade' : s)
    expect(searchSettings('crossf', en)[0].entry.key).toBe('audio.crossfade')
    expect(searchSettings('кроссф', en)[0].entry.key).toBe('audio.crossfade')
  })

  it('ограничивает число результатов', () => {
    expect(searchSettings('а', same, 5).length).toBeLessThanOrEqual(5)
  })
})

describe('подсветка совпадений', () => {
  it('режет текст на куски с отметкой', () => {
    expect(markRanges('Позиция вкладок', 'вкла')).toEqual([
      { text: 'Позиция ', mark: false },
      { text: 'вкла', mark: true },
      { text: 'док', mark: false },
    ])
  })

  it('несколько слов и ё', () => {
    expect(markRanges('Тёмная тема', 'тем')).toEqual([
      { text: 'Тём', mark: true },
      { text: 'ная ', mark: false },
      { text: 'тем', mark: true },
      { text: 'а', mark: false },
    ])
    expect(markRanges('Мини плеер', 'мини плеер').filter((p) => p.mark).map((p) => p.text)).toEqual(['Мини', 'плеер'])
  })

  it('нет совпадения — весь текст без отметки', () => {
    expect(markRanges('Язык', 'zzz')).toEqual([{ text: 'Язык', mark: false }])
  })
})

describe('переход к найденному пункту', () => {
  it('узнаёт заголовок пункта по началу текста элемента', () => {
    expect(titleMatches('Кроссфейд', 'Кроссфейд')).toBe(true)
    expect(titleMatches('  Позиция вкладок\n', 'позиция ВКЛАДОК')).toBe(true)
    expect(titleMatches('Тёмная тема Скоро', 'Темная тема')).toBe(true)
  })

  it('не путает с другим пунктом и с пустым текстом', () => {
    expect(titleMatches('Длительность кроссфейда', 'Кроссфейд')).toBe(false)
    expect(titleMatches('', 'Кроссфейд')).toBe(false)
    expect(titleMatches('Кроссфейд', '')).toBe(false)
  })
})
