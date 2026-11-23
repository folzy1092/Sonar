import { describe, expect, it } from 'vitest'
import { listenAction } from './listen'

describe('listenAction', () => {
  it('играет эта подборка — пауза', () => {
    expect(listenAction('playlist:7', { context: 'playlist:7', playing: true, hasCurrent: true })).toBe('pause')
  })

  it('эта подборка на паузе — продолжить с места', () => {
    expect(listenAction('favorites', { context: 'favorites', playing: false, hasCurrent: true })).toBe('resume')
  })

  it('вечеринка из этой подборки — пауза, а не новый старт', () => {
    expect(listenAction('playlist:7', { context: 'party:playlist:7', playing: true, hasCurrent: true })).toBe('pause')
  })

  it('играет другая подборка — начать эту', () => {
    expect(listenAction('album:ym:1', { context: 'playlist:7', playing: true, hasCurrent: true })).toBe('start')
  })

  it('очередь пуста — начать, даже если контекст тот же', () => {
    expect(listenAction('playlist:7', { context: 'playlist:7', playing: false, hasCurrent: false })).toBe('start')
  })

  it('подборка доиграла до конца — начать заново, а не повторить последний трек', () => {
    expect(listenAction('album:ym:1', { context: 'album:ym:1', playing: false, hasCurrent: true, ended: true })).toBe('start')
  })

  it('у страницы нет контекста — всегда начать', () => {
    expect(listenAction(null, { context: null, playing: true, hasCurrent: true })).toBe('start')
    expect(listenAction(undefined, { context: null, playing: false, hasCurrent: true })).toBe('start')
    expect(listenAction('', { context: '', playing: true, hasCurrent: true })).toBe('start')
  })
})
