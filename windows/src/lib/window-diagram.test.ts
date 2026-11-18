import { describe, expect, it } from 'vitest'
import { windowDiagram, type Rect } from './window-diagram'

const bottom = (r: Rect) => r.y + r.h
const right = (r: Rect) => r.x + r.w
const inside = (r: Rect) => r.x >= 0 && r.y >= 0 && right(r) <= 100 && bottom(r) <= 100

describe('схема окна', () => {
  it('вкладки сверху — панель над страницей', () => {
    const d = windowDiagram({ tabs: 'top' })
    expect(bottom(d.rail)).toBeLessThanOrEqual(d.page.y)
    expect(d.rail.w).toBeGreaterThan(d.rail.h)
  })

  it('вкладки снизу — панель под страницей и мини плеером', () => {
    const d = windowDiagram({ tabs: 'bottom', mini: 'bottom' })
    expect(d.rail.y).toBeGreaterThanOrEqual(bottom(d.page))
    expect(d.rail.y).toBeGreaterThanOrEqual(bottom(d.mini!))
  })

  it('вкладки слева и справа — вертикальная полоса с нужной стороны', () => {
    const l = windowDiagram({ tabs: 'left' })
    const r = windowDiagram({ tabs: 'right' })
    expect(right(l.rail)).toBeLessThanOrEqual(l.page.x)
    expect(r.rail.x).toBeGreaterThanOrEqual(right(r.page))
    expect(l.rail.h).toBeGreaterThan(l.rail.w)
  })

  it('компактная панель тоньше, полная сверху — во всю ширину', () => {
    expect(windowDiagram({ tabs: 'left', style: 'compact' }).rail.w).toBeLessThan(windowDiagram({ tabs: 'left' }).rail.w)
    expect(windowDiagram({ tabs: 'top', style: 'full' }).rail.w).toBeGreaterThan(windowDiagram({ tabs: 'top' }).rail.w)
  })

  it('плавающая панель парит над страницей, круглая — с отметкой', () => {
    const f = windowDiagram({ tabs: 'top', style: 'floating' })
    expect(f.rail.x).toBeGreaterThanOrEqual(f.page.x)
    expect(windowDiagram({ tabs: 'left', style: 'round' }).round).toBe(true)
  })

  it('мини плеер сверху, снизу, внутри и плавающий', () => {
    const top = windowDiagram({ tabs: 'left', mini: 'top' })
    expect(bottom(top.mini!)).toBeLessThanOrEqual(top.page.y)
    const inset = windowDiagram({ tabs: 'left', mini: 'bottom_inset' })
    expect(bottom(inset.mini!)).toBeLessThanOrEqual(bottom(inset.page))
    expect(inset.mini!.x).toBeGreaterThan(inset.page.x)
    const fl = windowDiagram({ tabs: 'left', mini: 'floating' })
    expect(fl.mini!.w).toBeLessThan(fl.page.w)
    expect(windowDiagram({ tabs: 'left', mini: 'none' }).mini).toBeNull()
  })

  it('очередь — на странице с нужной стороны', () => {
    const l = windowDiagram({ tabs: 'left', queue: 'left' })
    const r = windowDiagram({ tabs: 'left', queue: 'right' })
    expect(l.queue!.x).toBeLessThan(r.queue!.x)
    const b = windowDiagram({ tabs: 'left', queue: 'bottom' })
    expect(b.queue!.w).toBeGreaterThan(b.queue!.h)
    expect(windowDiagram({ tabs: 'left' }).queue).toBeNull()
  })

  it('всё помещается в окно', () => {
    for (const tabs of ['top', 'bottom', 'left', 'right'] as const)
      for (const style of ['default', 'compact', 'full', 'round', 'floating'] as const)
        for (const mini of ['top', 'bottom', 'bottom_inset', 'floating'] as const) {
          const d = windowDiagram({ tabs, style, mini, queue: 'right' })
          for (const r of [d.rail, d.page, d.mini!, d.queue!]) expect(inside(r), `${tabs} ${style} ${mini}`).toBe(true)
        }
  })
})
