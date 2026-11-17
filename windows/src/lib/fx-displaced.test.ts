import { describe, expect, it } from 'vitest'
import { ancestorDisplaced, displaced, identityTransform, movingProperty, type AncestorInfo } from './fx-displaced'

const still = (over: Partial<AncestorInfo> = {}): AncestorInfo => ({ away: false, transform: 'none', animations: [], ...over })
const anim = (properties: string[], over: { infinite?: boolean; running?: boolean } = {}) => ({
  properties,
  infinite: false,
  running: true,
  ...over,
})

describe('identityTransform', () => {
  it('none и единичные матрицы — на месте', () => {
    expect(identityTransform('none')).toBe(true)
    expect(identityTransform(undefined)).toBe(true)
    expect(identityTransform('matrix(1, 0, 0, 1, 0, 0)')).toBe(true)
    expect(identityTransform('matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)')).toBe(true)
  })

  it('сдвиг, масштаб, поворот — не на месте', () => {
    expect(identityTransform('matrix(1, 0, 0, 1, 0, 6)')).toBe(false)
    expect(identityTransform('matrix(0.9, 0, 0, 0.9, 0, 0)')).toBe(false)
    // .shell.away: translateX(...) rotateY(-15deg) scale(0.9)
    expect(identityTransform('matrix3d(0.869, 0, 0.233, 0, 0, 0.9, 0, 0, -0.233, 0, 0.869, 0, 384, 0, 0, 1)')).toBe(false)
  })
})

describe('movingProperty', () => {
  it('сдвиг и размер — двигают', () => {
    for (const p of ['transform', 'translate', 'left', 'margin-top', 'marginTop', 'height', 'grid-template-rows', 'gridTemplateRows', 'row-gap', 'all']) {
      expect(movingProperty(p)).toBe(true)
    }
  })

  it('цвет, прозрачность, тень, фильтр — не двигают', () => {
    for (const p of ['opacity', 'color', 'background', 'box-shadow', 'filter', 'border-radius']) {
      expect(movingProperty(p)).toBe(false)
    }
  })
})

describe('ancestorDisplaced', () => {
  it('предок в покое — на месте', () => {
    expect(ancestorDisplaced(still())).toBe(false)
    expect(ancestorDisplaced(still({ translate: 'none', rotate: 'none', scale: 'none' }))).toBe(false)
  })

  it('окно уехало под настройки (.shell.away)', () => {
    expect(ancestorDisplaced(still({ away: true }))).toBe(true)
  })

  it('предок сдвинут или масштабирован', () => {
    expect(ancestorDisplaced(still({ transform: 'matrix(1, 0, 0, 1, 0, 6)' }))).toBe(true)
    expect(ancestorDisplaced(still({ translate: '10px' }))).toBe(true)
    expect(ancestorDisplaced(still({ scale: '0.9' }))).toBe(true)
    expect(ancestorDisplaced(still({ rotate: '15deg' }))).toBe(true)
    expect(ancestorDisplaced(still({ translate: '0px', scale: '1', rotate: '0deg' }))).toBe(false)
  })

  it('идёт переход transform (панель настроек закрывается) — сдвинут', () => {
    expect(ancestorDisplaced(still({ animations: [anim(['transform'])] }))).toBe(true)
  })

  it('появление страницы (WAAPI с transform) — сдвинут, пока идёт', () => {
    expect(ancestorDisplaced(still({ animations: [anim(['opacity', 'transform'])] }))).toBe(true)
    expect(ancestorDisplaced(still({ animations: [anim(['opacity', 'transform'], { running: false })] }))).toBe(false)
  })

  it('только прозрачность или бесконечный пульс — не сдвиг', () => {
    expect(ancestorDisplaced(still({ animations: [anim(['opacity'])] }))).toBe(false)
    expect(ancestorDisplaced(still({ animations: [anim(['transform'], { infinite: true })] }))).toBe(false)
  })
})

describe('displaced', () => {
  it('хоть один предок сдвинут — эффект не рисуем', () => {
    expect(displaced([still(), still(), still()])).toBe(false)
    expect(displaced([still(), still({ away: true })])).toBe(true)
    expect(displaced([])).toBe(false)
  })
})
