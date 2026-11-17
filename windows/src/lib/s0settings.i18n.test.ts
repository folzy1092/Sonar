import { describe, expect, it, vi } from 'vitest'

let current = 'ru'
vi.mock('./settings.svelte', () => ({ settings: { get: () => current } }))
vi.mock('./api', () => ({ api: {} }))

const { dictionary } = await import('./i18n.svelte')
const { CATALOG, SUB_LEADS } = await import('./settings-catalog')

type Dict = Record<string, string>
const own = (mods: Record<string, unknown>): Dict => Object.values(mods).map((m) => (m as { default: Dict }).default)[0] ?? {}
const EN_OWN = own(import.meta.glob('../i18n/en/s0settings.ts', { eager: true }))
const UK_OWN = own(import.meta.glob('../i18n/uk/s0settings.ts', { eager: true }))

/** Строки новых элементов панели настроек (поиск, «Ещё настройки», плитки, превью, шторка). */
const UI = [
  'Ещё настройки',
  'Найти настройку',
  'Поиск по настройкам',
  'Очистить поиск',
  'Ничего не нашлось',
  'Попробуй другое слово — например, «тема», «кроссфейд» или «трей»',
  'Так выглядит мини плеер',
  'Мини плеер выключен',
  'Можно перетащить',
  'Где стоит панель разделов',
  'Как выглядит панель разделов',
  'Где открывается панель очереди',
  'Как звучат треки и стыки между ними',
  'Переходы и звонки',
  'Паузы между треками и музыка во время разговора',
  'Откуда брать звук для треков SoundCloud',
  'Вид визуализатора',
  'Обложка на странице плеера',
  'Что делает Sonar при входе в Windows и по крестику',
  'Плейлисты и лайки на этом компьютере',
  'Ресурсы',
  'Когда упрощать эффекты, чтобы не нагружать компьютер',
]

/** Все строки, которые новая подача настроек показывает пользователю. */
const ALL = [...new Set([...UI, ...CATALOG.flatMap((e) => [e.title, e.hint ?? '']), ...Object.values(SUB_LEADS)].filter(Boolean))]

describe('переводы новой подачи настроек (Этап 0, п. 4–7)', () => {
  for (const l of ['en', 'uk'] as const) {
    it(`у каждой строки есть перевод: ${l}`, () => {
      const dict = dictionary(l)
      const missing = ALL.filter((s) => !dict[s]?.trim())
      expect(missing).toEqual([])
    })
  }

  it('словари s0settings en и uk — с одинаковыми ключами', () => {
    expect(Object.keys(UK_OWN).sort()).toEqual(Object.keys(EN_OWN).sort())
    expect(Object.keys(EN_OWN).length).toBeGreaterThan(0)
  })

  it('перевод не совпадает с русским оригиналом (кроме имён собственных)', () => {
    const same = Object.entries(EN_OWN).filter(([ru, en]) => ru === en)
    expect(same).toEqual([])
  })
})
