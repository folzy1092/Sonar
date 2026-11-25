import { describe, expect, it } from 'vitest'

const { isChosen, sourceChoices, sourceName, sourceValue } = await import('./track-source')
const { qualityLabel, fallbackToast } = await import('./fallback')

describe('«Играть из» — варианты в меню трека', () => {
  it('трек есть и в Яндексе — «Авто», свой и двойник', () => {
    expect(sourceChoices('sc:1', { services: ['sc', 'ym'], pinned: null })).toEqual(['auto', 'sc', 'ym'])
  })

  it('трек только у себя и ничего не закреплено — выбирать не из чего', () => {
    expect(sourceChoices('sc:1', { services: ['sc'], pinned: null })).toEqual([])
    expect(sourceChoices('sc:1', null)).toEqual([])
  })

  it('закреплённый сервис виден, даже если двойник сейчас не нашёлся — его можно снять', () => {
    expect(sourceChoices('sc:1', { services: ['sc', 'ym'], pinned: 'ym' })).toEqual(['auto', 'sc', 'ym'])
    expect(sourceChoices('sc:1', { services: ['sc'], pinned: 'sc' })).toEqual(['auto', 'sc'])
  })

  it('выбранное и значение для Rust', () => {
    expect(isChosen('auto', null)).toBe(true)
    expect(isChosen('sc', null)).toBe(false)
    expect(isChosen('ym', 'ym')).toBe(true)
    expect(sourceValue('auto')).toBeNull()
    expect(sourceValue('yt')).toBe('yt')
    expect(sourceName('ym')).toBe('Яндекс Музыка')
  })
})

describe('плашка с выбранным «Играть из»', () => {
  it('закреплён свой — сервис пишется и у своего', () => {
    expect(qualityLabel('AAC 160', null, 'sc')).toBe('AAC 160 · SoundCloud')
  })

  it('закреплён другой — пишется, откуда реально играет', () => {
    const via = { ref: 'ym:2', service: 'ym', from: 'sc', reason: 'pinned' } as const
    expect(qualityLabel('FLAC', via, 'ym')).toBe('FLAC · Яндекс Музыка')
  })

  it('«Авто» — как раньше', () => {
    expect(qualityLabel('MP3 320', null, null)).toBe('MP3 320')
  })

  it('выбор — не беда: без всплывашки резерва', () => {
    expect(fallbackToast({ ref: 'ym:2', service: 'ym', from: 'sc', reason: 'pinned' })).toBeNull()
  })
})
