import { describe, expect, it } from 'vitest'
import {
  BROWSER_MONITOR,
  PLAQUE_MIN_W,
  PRIMARY_MONITOR,
  anchorBox,
  anchorCenters,
  anchorDots,
  dropTarget,
  fitScheme,
  hzLabel,
  marginPx,
  monitorChoice,
  pickMonitor,
  plaqueBox,
  stepAnchor,
  type MonitorInfo,
} from './monitor-layout'

/** Монитор с рабочей областью во весь экран — поля, которые тесту не важны, по умолчанию. */
function mon(id: string, x: number, y: number, width: number, height: number, extra: Partial<MonitorInfo> = {}): MonitorInfo {
  return { id, gdi_name: '', name: '', number: 1, x, y, width, height, work_x: x, work_y: y, work_w: width, work_h: height, scale: 1, refresh_hz: 60, primary: false, ...extra }
}

const A = mon('path-a', 0, 0, 1920, 1080, { primary: true, number: 1 })
const B = mon('path-b', 1920, -180, 2560, 1440, { scale: 1.5, number: 2 })

describe('схема мониторов: выбор монитора', () => {
  it('primary — основной монитор, не «отключён»', () => {
    // Arrange
    const list = [B, A]
    // Act
    const picked = pickMonitor(list, PRIMARY_MONITOR)
    // Assert
    expect(picked).toEqual({ monitor: A, missing: false })
  })

  it('сохранённый id находит свой монитор', () => {
    expect(pickMonitor([A, B], 'path-b')).toEqual({ monitor: B, missing: false })
  })

  it('отключённый монитор — оверлей на основном, помечаем missing', () => {
    expect(pickMonitor([A, B], 'path-gone')).toEqual({ monitor: A, missing: true })
  })

  it('без основного берём первый, пустой список — ничего', () => {
    expect(pickMonitor([B], PRIMARY_MONITOR).monitor).toBe(B)
    expect(pickMonitor([], 'path-a')).toEqual({ monitor: null, missing: false })
  })

  it('выбрали основной — в настройку уходит primary, другой — его id', () => {
    expect(monitorChoice(A)).toBe(PRIMARY_MONITOR)
    expect(monitorChoice(B)).toBe('path-b')
  })
})

describe('схема мониторов: вписать в рамку', () => {
  it('один монитор 16:9 упирается в ширину 420', () => {
    const s = fitScheme([BROWSER_MONITOR])
    expect(s.width).toBe(420)
    expect(s.height).toBeCloseTo(236.25)
    expect(s.tiles[0].work.h).toBeCloseTo(1032 * s.k)
  })

  it('вертикальный монитор упирается в высоту 260', () => {
    const s = fitScheme([mon('p', 0, 0, 1080, 1920)])
    expect(s.height).toBeCloseTo(260)
    expect(s.width).toBeCloseTo(146.25)
  })

  it('два монитора стоят как на самом деле, отрицательные координаты сдвигаются к нулю', () => {
    // Act
    const s = fitScheme([A, B])
    // Assert
    expect(s.k).toBeCloseTo(420 / 4480)
    expect(s.width).toBeCloseTo(420)
    expect(s.height).toBeCloseTo(135)
    expect(s.tiles[0].rect).toEqual({ x: 0, y: expect.closeTo(16.875), w: expect.closeTo(180), h: expect.closeTo(101.25) })
    expect(s.tiles[1].rect).toEqual({ x: expect.closeTo(180), y: 0, w: expect.closeTo(240), h: expect.closeTo(135) })
  })

  it('узкая рамка — схема уменьшается, пропорции те же', () => {
    const s = fitScheme([BROWSER_MONITOR], { w: 200, h: 260 })
    expect(s.width).toBeCloseTo(200)
    expect(s.width / s.height).toBeCloseTo(1920 / 1080)
  })

  it('пустой список или нулевая рамка — пустая схема', () => {
    expect(fitScheme([]).tiles).toEqual([])
    expect(fitScheme([A], { w: 0, h: 100 }).width).toBe(0)
  })
})

describe('схема мониторов: плашка в масштабе', () => {
  const s = fitScheme([BROWSER_MONITOR])
  const work = s.tiles[0].work

  it('плашка — окно оверлея в масштабе схемы', () => {
    const box = plaqueBox({ width: 340, height: 58 }, BROWSER_MONITOR, s.k, work)
    expect(box.w).toBeCloseTo(74.375)
    expect(box.h).toBeCloseTo((74.375 * 58) / 340)
  })

  it('мелкая плашка не уже минимума, пропорции сохраняются', () => {
    const box = plaqueBox({ width: 340, height: 58 }, BROWSER_MONITOR, 0.05, work)
    expect(box.w).toBe(PLAQUE_MIN_W)
    expect(box.h).toBeCloseTo((PLAQUE_MIN_W * 58) / 340)
  })

  it('DPI монитора увеличивает плашку', () => {
    const hi = plaqueBox({ width: 340, height: 58 }, { ...BROWSER_MONITOR, scale: 1.5 }, s.k, work)
    expect(hi.w).toBeCloseTo(340 * 1.5 * s.k)
  })

  it('плашка не вылезает за рабочую область', () => {
    const box = plaqueBox({ width: 340, height: 58 }, BROWSER_MONITOR, s.k, { x: 0, y: 0, w: 80, h: 50 })
    expect(box.w).toBeCloseTo(80 - 2 * marginPx(BROWSER_MONITOR, s.k))
  })
})

describe('схема мониторов: клетки', () => {
  const work = { x: 0, y: 0, w: 420, h: 225.75 }
  const size = { w: 74.375, h: 12.6875 }

  it('углы и центр — как anchor_in в Rust', () => {
    expect(anchorBox(work, size, 'tl', 6)).toEqual({ x: 6, y: 6 })
    expect(anchorBox(work, size, 'br', 6)).toEqual({ x: expect.closeTo(339.625), y: expect.closeTo(207.0625) })
    expect(anchorBox(work, size, 'mc', 6)).toEqual({ x: expect.closeTo(172.8125), y: expect.closeTo(106.53125) })
  })

  it('плашка шире области прижимается к левому краю', () => {
    expect(anchorBox({ x: 10, y: 0, w: 50, h: 50 }, { w: 80, h: 10 }, 'tr', 6)).toEqual({ x: 10, y: 6 })
  })

  it('центры плашки во всех девяти клетках', () => {
    const c = anchorCenters(work, size, 6)
    expect(Object.keys(c)).toHaveLength(9)
    expect(c.tl).toEqual({ x: 6 + size.w / 2, y: 6 + size.h / 2 })
  })

  it('точки сетки с отступом от краёв', () => {
    const d = anchorDots({ x: 0, y: 0, w: 100, h: 50 }, 10)
    expect(d.tl).toEqual({ x: 10, y: 10 })
    expect(d.mc).toEqual({ x: 50, y: 25 })
    expect(d.br).toEqual({ x: 90, y: 40 })
  })

  it('стрелки двигают клетку, у края стоят', () => {
    expect(stepAnchor('tl', 1, 0)).toBe('tc')
    expect(stepAnchor('tl', -1, 0)).toBe('tl')
    expect(stepAnchor('mc', 0, 1)).toBe('bc')
    expect(stepAnchor('br', 1, 1)).toBe('br')
  })
})

describe('схема мониторов: куда прилипнет плашка', () => {
  const size = () => ({ w: 80, h: 20 })

  it('отпустили у угла — ближайшая клетка этого угла', () => {
    const s = fitScheme([BROWSER_MONITOR])
    expect(dropTarget(s, { x: 410, y: 220 }, size)?.anchor).toBe('br')
    expect(dropTarget(s, { x: 210, y: 110 }, size)?.anchor).toBe('mc')
  })

  it('перетащили на второй монитор — он и клетка на нём', () => {
    // Arrange
    const s = fitScheme([A, B])
    // Act
    const hit = dropTarget(s, { x: 300, y: 60 }, size)
    // Assert
    expect(hit?.tile.m.id).toBe('path-b')
    expect(hit?.anchor).toBe('mc')
  })

  it('отпустили мимо мониторов — ближайший монитор', () => {
    const s = fitScheme([A, B])
    const hit = dropTarget(s, { x: 100, y: 5 }, size)
    expect(hit?.tile.m.id).toBe('path-a')
    expect(hit?.anchor).toBe('tc')
  })

  it('пустая схема — некуда', () => {
    expect(dropTarget(fitScheme([]), { x: 0, y: 0 }, size)).toBeNull()
  })
})

describe('схема мониторов: подписи', () => {
  it('частота: целая без дробей, 59.94 с сотыми', () => {
    expect(hzLabel(60)).toBe('60')
    expect(hzLabel(60.001)).toBe('60')
    expect(hzLabel(59.94)).toBe('59.94')
    expect(hzLabel(143.856)).toBe('143.86')
    expect(hzLabel(74.5)).toBe('74.5')
    expect(hzLabel(0)).toBe('')
  })
})
