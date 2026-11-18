// Схема окна для плиток настроек (NEXT_PROMPT «Этап 0» п. 5): где панель вкладок, где страница,
// мини плеер и очередь. Прямоугольники — в процентах от ширины (x, w) и высоты (y, h) окна.
import type { TabsPosition } from './settings-open'

export type TabsStyle = 'default' | 'compact' | 'full' | 'round' | 'floating'
export type MiniPosition = 'top' | 'bottom' | 'bottom_inset' | 'floating' | 'none'
export type QueuePosition = 'bottom' | 'left' | 'right'

export interface Rect {
  x: number
  y: number
  w: number
  h: number
}

export interface DiagramInput {
  tabs: TabsPosition
  style?: TabsStyle
  mini?: MiniPosition
  queue?: QueuePosition | null
}

export interface Diagram {
  rail: Rect
  page: Rect
  mini: Rect | null
  queue: Rect | null
  /** Вкладки круглыми значками — на схеме точки вместо полос. */
  round: boolean
}

const GX = 3
const GY = 5
const RAIL_V = { default: 9, compact: 6 } as const
const RAIL_H = { default: 12, compact: 9 } as const
const MINI_H = 13
const QUEUE_W = 24
const QUEUE_H = 30

const box = (x: number, y: number, w: number, h: number): Rect => ({ x, y, w, h })

function thickness(style: TabsStyle, vertical: boolean): number {
  const set = vertical ? RAIL_V : RAIL_H
  return style === 'compact' ? set.compact : set.default
}

/** Панель вкладок и место, что остаётся окну. */
function placeRail(tabs: TabsPosition, style: TabsStyle): { rail: Rect; free: Rect } {
  const full = box(GX, GY, 100 - 2 * GX, 100 - 2 * GY)
  if (style === 'floating') return { rail: box(GX + 1, 30, 7, 40), free: full }
  const vertical = tabs === 'left' || tabs === 'right'
  const k = thickness(style, vertical)
  if (vertical) {
    const railX = tabs === 'left' ? GX : 100 - GX - k
    const freeX = tabs === 'left' ? GX + k + GX : GX
    return { rail: box(railX, GY, k, full.h), free: box(freeX, GY, full.w - k - GX, full.h) }
  }
  // сверху/снизу «по умолчанию» — узкий островок по центру, «полный» — во всю ширину
  const w = style === 'full' ? full.w : 44
  const railY = tabs === 'top' ? GY : 100 - GY - k
  const freeY = tabs === 'top' ? GY + k + GY : GY
  return { rail: box(50 - w / 2, railY, w, k), free: box(GX, freeY, full.w, full.h - k - GY) }
}

function placeMini(free: Rect, mini: MiniPosition): { page: Rect; mini: Rect | null } {
  const { x, y, w, h } = free
  switch (mini) {
    case 'top':
      return { mini: box(x, y, w, MINI_H), page: box(x, y + MINI_H + GY, w, h - MINI_H - GY) }
    case 'bottom':
      return { mini: box(x, y + h - MINI_H, w, MINI_H), page: box(x, y, w, h - MINI_H - GY) }
    case 'bottom_inset':
      return { mini: box(x + 4, y + h - MINI_H - 4, w - 8, MINI_H), page: free }
    case 'floating':
      return { mini: box(x + w * 0.45, y + h - MINI_H - 6, w * 0.5, MINI_H), page: free }
    default:
      return { mini: null, page: free }
  }
}

function placeQueue(page: Rect, queue: QueuePosition | null | undefined): Rect | null {
  if (!queue) return null
  const { x, y, w, h } = page
  if (queue === 'bottom') return box(x + 3, y + h - QUEUE_H - 4, w - 6, QUEUE_H)
  const qx = queue === 'left' ? x + 2 : x + w - QUEUE_W - 2
  return box(qx, y + 4, QUEUE_W, h - 8)
}

export function windowDiagram({ tabs, style = 'default', mini = 'bottom', queue = null }: DiagramInput): Diagram {
  const { rail, free } = placeRail(tabs, style)
  const placed = placeMini(free, mini)
  return { rail, page: placed.page, mini: placed.mini, queue: placeQueue(placed.page, queue), round: style === 'round' }
}
