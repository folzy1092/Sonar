import { describe, expect, it } from 'vitest'
import { autoMode, effectiveMode, followTrack, knownLyrics, lyricsAvail, sidePane, type PaneState } from './side-pane.svelte'

const at = (mode: PaneState['mode'], ref: PaneState['ref'], manual = false): PaneState => ({ mode, ref, manual })

describe('признак текста у трека', () => {
  it('любой найденный текст — да, не найден — нет', () => {
    expect(lyricsAvail('ready', 'sc:1', 'sc:1')).toBe('yes')
    expect(lyricsAvail('none', 'sc:1', 'sc:1')).toBe('no')
  })

  it('пока ищется или стор ещё на прошлом треке — «ищется»', () => {
    expect(lyricsAvail('loading', 'sc:1', 'sc:1')).toBe('pending')
    expect(lyricsAvail('ready', 'sc:1', 'sc:2')).toBe('pending')
    expect(lyricsAvail('idle', null, null)).toBe('pending')
  })
})

describe('правило переключения панели', () => {
  it('новый трек с текстом — текст', () => {
    expect(followTrack(at('queue', 'sc:1'), 'sc:2', 'yes')).toEqual(at('lyrics', 'sc:2'))
  })

  it('новый трек без текста — очередь', () => {
    expect(followTrack(at('lyrics', 'sc:1'), 'sc:2', 'no')).toEqual(at('queue', 'sc:2'))
  })

  it('выбор руками на этом же треке не перебивается', () => {
    const manual = at('queue', 'sc:1', true)
    expect(followTrack(manual, 'sc:1', 'yes')).toBe(manual)
  })

  it('выбор руками сбрасывается на следующем треке', () => {
    expect(followTrack(at('queue', 'sc:1', true), 'sc:2', 'yes')).toEqual(at('lyrics', 'sc:2'))
  })

  it('текст догрузился позже — переключается, если вид не выбирали руками', () => {
    const loading = followTrack(at('queue', 'sc:1'), 'sc:2', 'pending')
    expect(loading.mode).toBe('queue')
    expect(followTrack(loading, 'sc:2', 'yes')).toEqual(at('lyrics', 'sc:2'))
  })

  it('пока текст ищется — прежний вид, без мигания', () => {
    expect(followTrack(at('lyrics', 'sc:1'), 'sc:2', 'pending')).toEqual(at('lyrics', 'sc:2'))
    expect(autoMode('pending', 'queue')).toBe('queue')
  })

  it('только что открытая панель принимает текущий трек и сохраняет выбор руками', () => {
    expect(followTrack(at('queue', undefined, true), 'sc:5', 'yes')).toEqual(at('queue', 'sc:5', true))
    expect(followTrack(at('queue', undefined), 'sc:5', 'yes')).toEqual(at('lyrics', 'sc:5'))
  })

  it('ничего не поменялось — тот же объект', () => {
    const s = at('lyrics', 'sc:1')
    expect(followTrack(s, 'sc:1', 'yes')).toBe(s)
  })
})

describe('что показывает панель и кнопка', () => {
  it('без текста — очередь, даже если выбран текст; пока ищется — текст остаётся', () => {
    expect(effectiveMode('lyrics', 'no')).toBe('queue')
    expect(effectiveMode('lyrics', 'yes')).toBe('lyrics')
    expect(effectiveMode('lyrics', 'pending')).toBe('lyrics')
    expect(effectiveMode('queue', 'yes')).toBe('queue')
  })

  it('значок кнопки не мигает, пока текст ищется', () => {
    expect(knownLyrics('pending', true)).toBe(true)
    expect(knownLyrics('pending', false)).toBe(false)
    expect(knownLyrics('yes', false)).toBe(true)
    expect(knownLyrics('no', true)).toBe(false)
  })
})

describe('кнопки панели', () => {
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

  it('Ctrl+Q на треке с текстом — очередь держится до смены трека', () => {
    sidePane.close()
    sidePane.toggle('queue', true)
    sidePane.sync('sc:1', 'yes')
    expect(sidePane.mode).toBe('queue')
    sidePane.sync('sc:2', 'yes')
    expect(sidePane.mode).toBe('lyrics')
  })

  it('кнопка мини-плеера открывает вид не руками: текст догрузился — панель на текст', () => {
    sidePane.close()
    sidePane.toggle('queue', false, false)
    sidePane.sync('sc:3', 'pending')
    expect(sidePane.mode).toBe('queue')
    sidePane.sync('sc:3', 'yes')
    expect(sidePane.mode).toBe('lyrics')
  })

  it('капсулы в панели — выбор руками', () => {
    sidePane.close()
    sidePane.toggle('lyrics', true, false)
    sidePane.sync('sc:4', 'yes')
    sidePane.pick('queue')
    sidePane.sync('sc:4', 'yes')
    expect(sidePane.mode).toBe('queue')
  })
})
