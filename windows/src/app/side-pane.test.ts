import { describe, expect, it } from 'vitest'
import { effectiveMode, sidePane } from './side-pane.svelte'

describe('правая панель «Очередь / Текст»', () => {
  it('без текста показывает очередь, даже если выбран текст', () => {
    expect(effectiveMode('lyrics', false)).toBe('queue')
    expect(effectiveMode('lyrics', true)).toBe('lyrics')
    expect(effectiveMode('queue', true)).toBe('queue')
  })

  it('кнопка закрывает панель, если она уже показывает очередь вместо текста', () => {
    sidePane.close()
    sidePane.toggle('lyrics', true)
    expect(sidePane.open).toBe(true)
    // у нового трека текста нет: панель показывает очередь, кнопка — значок очереди
    sidePane.toggle('queue', false)
    expect(sidePane.open).toBe(false)
  })

  it('кнопка переключает вид, если открыт другой', () => {
    sidePane.close()
    sidePane.toggle('queue', true)
    sidePane.toggle('lyrics', true)
    expect(sidePane.open).toBe(true)
    expect(sidePane.mode).toBe('lyrics')
  })
})
