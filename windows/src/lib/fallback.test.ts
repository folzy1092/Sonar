import { describe, expect, it, vi } from 'vitest'

let lang = 'ru'
vi.mock('./settings.svelte', () => ({ settings: { get: () => lang } }))

const { canBackUp, defaultFallbackOrder, fallbackOrder, fallbackToast, moveItem } = await import('./fallback')
const { SERVICES, byId } = await import('./services')

describe('порядок резервных сервисов', () => {
  it('по умолчанию — реестр без Spotify и локальных файлов', () => {
    // Arrange / Act
    const order = defaultFallbackOrder()
    // Assert
    expect(order).toEqual(SERVICES.filter(canBackUp).map((s) => s.id))
    expect(order).not.toContain('sp')
    expect(order).not.toContain('local')
    expect(order.slice(0, 2)).toEqual(['sc', 'ym'])
  })

  it('Spotify и локальные файлы резервом быть не могут', () => {
    expect(canBackUp(byId('sp')!)).toBe(false)
    expect(canBackUp(byId('local')!)).toBe(false)
    expect(canBackUp(byId('yt')!)).toBe(true)
  })

  it('сохранённый порядок: свой — первым, мусор и повторы — прочь, забытые — в конец', () => {
    const order = fallbackOrder(['yt', 'yt', 'nope', 'sp', 42, 'sc'])
    expect(order[0]).toBe('yt')
    expect(order[1]).toBe('sc')
    expect(new Set(order).size).toBe(order.length)
    expect([...order].sort()).toEqual([...defaultFallbackOrder()].sort())
  })

  it('не список (пусто, null, строка) — порядок по умолчанию', () => {
    for (const v of [undefined, null, '', 'sc', {}]) expect(fallbackOrder(v)).toEqual(defaultFallbackOrder())
  })
})

describe('перестановка', () => {
  it('переносит элемент и не трогает исходный список', () => {
    const list = ['sc', 'ym', 'yt', 'vk'] as const
    expect(moveItem(list, 0, 2)).toEqual(['ym', 'yt', 'sc', 'vk'])
    expect(moveItem(list, 3, 0)).toEqual(['vk', 'sc', 'ym', 'yt'])
    expect(list).toEqual(['sc', 'ym', 'yt', 'vk'])
  })

  it('за границами или на то же место — копия без изменений', () => {
    const list = ['a', 'b']
    const same = moveItem(list, 1, 1)
    expect(same).toEqual(list)
    expect(same).not.toBe(list)
    expect(moveItem(list, -1, 0)).toEqual(list)
    expect(moveItem(list, 0, 5)).toEqual(list)
  })
})

describe('всплывашка резервного сервиса', () => {
  it('по-русски — с предложным падежом сервиса', () => {
    lang = 'ru'
    expect(fallbackToast({ ref: 'yt:1', service: 'yt', from: 'sc', reason: 'unavailable' })).toBe(
      'Играет из YouTube Music — в SoundCloud недоступен',
    )
    expect(fallbackToast({ ref: 'sc:1', service: 'sc', from: 'ym', reason: 'preview' })).toBe(
      'Играет из SoundCloud — в Яндекс Музыке только отрывок',
    )
    expect(fallbackToast({ ref: 'ym:1', service: 'ym', from: 'sp', reason: 'premium' })).toBe(
      'Играет из Яндекс Музыка — в Spotify нужна подписка',
    )
  })

  it('по-английски — перевод из словаря', () => {
    lang = 'en'
    expect(fallbackToast({ ref: 'yt:1', service: 'yt', from: 'ym', reason: 'failed' })).toBe(
      'Playing from YouTube Music — unavailable on Yandex Music',
    )
    lang = 'ru'
  })

  it('«SoundCloud через Яндекс», пусто или чужой сервис — без всплывашки', () => {
    expect(fallbackToast({ ref: 'ym:1', service: 'ym', from: 'sc', reason: 'preferred' })).toBeNull()
    expect(fallbackToast(null)).toBeNull()
    expect(fallbackToast({ ref: 'x:1', service: 'xx' as 'sc', from: 'sc', reason: 'failed' })).toBeNull()
  })
})
