// Схема мониторов в «Оверлей → Положение на экране» — чистая логика без Tauri и DOM. Мониторы приходят
// из Rust (`list_monitors`, monitors.rs) в физических пикселях и расставлены как в «Параметры → Дисплей»;
// здесь их вписываем в рамку, считаем плашку в масштабе и ближайшую клетку, куда она прилипнет.
import type { OverlayAnchor } from './settings.svelte'
import { OVERLAY_ANCHORS, anchorAlign } from './overlay'

/** Монитор из `list_monitors` — поля как в monitors.rs `MonitorInfo`. Координаты — физические пиксели. */
export interface MonitorInfo {
  /** `monitorDevicePath` (не меняется между запусками), без него — имя GDI. */
  id: string
  gdi_name: string
  /** Модель из EDID; пусто — подписываем «Монитор N». */
  name: string
  number: number
  x: number
  y: number
  width: number
  height: number
  /** Рабочая область — без панели задач. */
  work_x: number
  work_y: number
  work_w: number
  work_h: number
  /** Масштаб Windows: 1.25 = 125 %. */
  scale: number
  refresh_hz: number
  primary: boolean
}

export interface Rect {
  x: number
  y: number
  w: number
  h: number
}

export interface Size {
  w: number
  h: number
}

export interface Point {
  x: number
  y: number
}

/** Значение `overlay.monitor` по умолчанию — тот, что в Windows основной. */
export const PRIMARY_MONITOR = 'primary'

/** Без Tauri (npm run dev в браузере) — один обычный монитор 1920×1080 с панелью задач снизу. */
export const BROWSER_MONITOR: MonitorInfo = {
  id: 'browser',
  gdi_name: '',
  name: '',
  number: 1,
  x: 0,
  y: 0,
  width: 1920,
  height: 1080,
  work_x: 0,
  work_y: 0,
  work_w: 1920,
  work_h: 1032,
  scale: 1,
  refresh_hz: 60,
  primary: true,
}

/** Рамка схемы: не шире и не выше этого, пропорции мониторов сохраняются. */
export const SCHEME_MAX: Size = { w: 420, h: 260 }
/** Плашка на схеме не уже этого — иначе её не разглядеть и не схватить. */
export const PLAQUE_MIN_W = 70
/** Отступ плашки от краёв, логические пиксели, — как `MARGIN` в mini.rs. */
const OVERLAY_MARGIN = 20
/** На схеме отступ не меньше этого, чтобы плашка не липла к рамке монитора. */
const SCHEME_MARGIN_MIN = 6
/** Частоты вроде 59.94 показываем с сотыми, 60.001 — округляем. */
const HZ_ROUND_EPS = 0.05

export interface SchemeTile {
  m: MonitorInfo
  /** Весь монитор на схеме, px. */
  rect: Rect
  /** Его рабочая область на схеме, px. */
  work: Rect
}

export interface Scheme {
  width: number
  height: number
  /** Сколько px схемы в одном физическом пикселе. */
  k: number
  tiles: SchemeTile[]
}

/** Какой монитор выбран: `wanted` — значение `overlay.monitor`. Отключён — основной, и `missing`. */
export function pickMonitor(list: readonly MonitorInfo[], wanted: string): { monitor: MonitorInfo | null; missing: boolean } {
  const exact = wanted === PRIMARY_MONITOR ? undefined : list.find((m) => m.id === wanted)
  if (exact) return { monitor: exact, missing: false }
  const fallback = list.find((m) => m.primary) ?? list[0] ?? null
  return { monitor: fallback, missing: wanted !== PRIMARY_MONITOR && list.length > 0 }
}

/** Что сохранить в `overlay.monitor`, когда выбрали монитор: основной — `primary`, иначе его id. */
export const monitorChoice = (m: MonitorInfo) => (m.primary ? PRIMARY_MONITOR : m.id)

/** Вписать все мониторы в рамку `max`, как они стоят на самом деле. */
export function fitScheme(list: readonly MonitorInfo[], max: Size = SCHEME_MAX): Scheme {
  if (list.length === 0 || max.w <= 0 || max.h <= 0) return { width: 0, height: 0, k: 0, tiles: [] }
  const left = Math.min(...list.map((m) => m.x))
  const top = Math.min(...list.map((m) => m.y))
  const right = Math.max(...list.map((m) => m.x + m.width))
  const bottom = Math.max(...list.map((m) => m.y + m.height))
  const k = Math.min(max.w / Math.max(1, right - left), max.h / Math.max(1, bottom - top))
  const map = (x: number, y: number, w: number, h: number): Rect => ({ x: (x - left) * k, y: (y - top) * k, w: w * k, h: h * k })
  return {
    width: (right - left) * k,
    height: (bottom - top) * k,
    k,
    tiles: list.map((m) => ({ m, rect: map(m.x, m.y, m.width, m.height), work: map(m.work_x, m.work_y, m.work_w, m.work_h) })),
  }
}

/** Отступ плашки от краёв рабочей области на схеме, px. */
export const marginPx = (m: MonitorInfo, k: number) => Math.max(SCHEME_MARGIN_MIN, OVERLAY_MARGIN * m.scale * k)

/**
 * Плашка на схеме, px: окно оверлея (`layout` — логические пиксели, масштаб уже учтён) в масштабе схемы
 * с DPI монитора. Не уже `PLAQUE_MIN_W` и не больше рабочей области — пропорции сохраняются.
 */
export function plaqueBox(layout: { width: number; height: number }, m: MonitorInfo, k: number, work: Rect): Size {
  const ratio = layout.height / Math.max(1, layout.width)
  let w = Math.max(PLAQUE_MIN_W, layout.width * m.scale * k)
  const room = Math.max(1, work.w - 2 * marginPx(m, k))
  const roomH = Math.max(1, work.h - 2 * marginPx(m, k))
  w = Math.min(w, room, roomH / ratio)
  return { w, h: w * ratio }
}

/** Где встанет плашка в клетке `anchor` — левый верхний угол, как `anchor_in` в monitors.rs. */
export function anchorBox(work: Rect, size: Size, anchor: OverlayAnchor, margin: number): Point {
  const a = anchorAlign(anchor)
  const x = a.x === 0 ? work.x + margin : a.x === 1 ? work.x + work.w - size.w - margin : work.x + (work.w - size.w) / 2
  const y = a.y === 0 ? work.y + margin : a.y === 1 ? work.y + work.h - size.h - margin : work.y + (work.h - size.h) / 2
  return { x: Math.max(work.x, x), y: Math.max(work.y, y) }
}

/** Центры плашки во всех девяти клетках — к ближайшему и прилипает отпущенная плашка. */
export function anchorCenters(work: Rect, size: Size, margin: number): Record<OverlayAnchor, Point> {
  const entries = OVERLAY_ANCHORS.map((a) => {
    const p = anchorBox(work, size, a, margin)
    return [a, { x: p.x + size.w / 2, y: p.y + size.h / 2 }] as const
  })
  return Object.fromEntries(entries) as Record<OverlayAnchor, Point>
}

/** Точки-клетки на мониторе: сетка 3×3 с отступом `inset` от краёв рабочей области. */
export function anchorDots(work: Rect, inset: number): Record<OverlayAnchor, Point> {
  const entries = OVERLAY_ANCHORS.map((a) => {
    const f = anchorAlign(a)
    return [a, { x: work.x + inset + (work.w - 2 * inset) * f.x, y: work.y + inset + (work.h - 2 * inset) * f.y }] as const
  })
  return Object.fromEntries(entries) as Record<OverlayAnchor, Point>
}

const distToRect = (p: Point, r: Rect) => Math.hypot(Math.max(r.x - p.x, 0, p.x - r.x - r.w), Math.max(r.y - p.y, 0, p.y - r.y - r.h))

/** Монитор под точкой схемы, а если она между ними — ближайший. */
export function tileAt(scheme: Scheme, p: Point): SchemeTile | null {
  let best: SchemeTile | null = null
  let bestD = Infinity
  for (const tile of scheme.tiles) {
    const d = distToRect(p, tile.rect)
    if (d < bestD) {
      best = tile
      bestD = d
    }
  }
  return best
}

/** Куда прилипнет плашка, центр которой отпустили в точке `p`: монитор и ближайшая клетка на нём. */
export function dropTarget(scheme: Scheme, p: Point, sizeFor: (tile: SchemeTile) => Size): { tile: SchemeTile; anchor: OverlayAnchor } | null {
  const tile = tileAt(scheme, p)
  if (!tile) return null
  const centers = anchorCenters(tile.work, sizeFor(tile), marginPx(tile.m, scheme.k))
  let anchor: OverlayAnchor = OVERLAY_ANCHORS[0]
  let bestD = Infinity
  for (const a of OVERLAY_ANCHORS) {
    const d = Math.hypot(centers[a].x - p.x, centers[a].y - p.y)
    if (d < bestD) {
      anchor = a
      bestD = d
    }
  }
  return { tile, anchor }
}

/** Частота для подписи: 60 → «60», 59.94 → «59.94», нет данных — пусто. */
export function hzLabel(hz: number): string {
  if (!(hz > 0)) return ''
  const whole = Math.round(hz)
  if (Math.abs(hz - whole) < HZ_ROUND_EPS) return String(whole)
  return hz.toFixed(2).replace(/0+$/, '').replace(/\.$/, '')
}

/** Сдвиг клетки стрелками: шаг по ряду или столбцу, у края — стоим. */
export function stepAnchor(a: OverlayAnchor, dx: -1 | 0 | 1, dy: -1 | 0 | 1): OverlayAnchor {
  const i = OVERLAY_ANCHORS.indexOf(a)
  const col = Math.min(2, Math.max(0, (i % 3) + dx))
  const row = Math.min(2, Math.max(0, Math.floor(i / 3) + dy))
  return OVERLAY_ANCHORS[row * 3 + col]
}
