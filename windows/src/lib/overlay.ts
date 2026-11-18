// Оверлей (SETTINGS_NEXT «Оверлей», 2026-11-18): чистая логика без Tauri — размер окна по режиму и
// масштабу, клетки сетки 3×3, когда появляться и прятаться самому. Окно открывает lib/mini.svelte.ts,
// рисует app/MiniWindow.svelte, ставит на место mini.rs.
import type { OverlayAnchor, OverlayMode } from './settings.svelte'

/** Что отдаём Rust (`overlay_window`): логические пиксели, масштаб уже учтён. */
export interface OverlayLayout {
  width: number
  height: number
  anchor: OverlayAnchor
  fullscreen: boolean
  /** `overlay.monitor`: `primary` или `monitorDevicePath` (lib/monitor-layout.ts, monitors.rs). */
  monitor: string
}

/** Как рисовать оверлей — шлёт главное окно событием `overlay:look`. */
export interface OverlayLook {
  mode: OverlayMode
  shape: 'square' | 'rounded'
  /** Непрозрачность, %. */
  opacity: number
  /** Масштаб, %. */
  scale: number
}

/** Клетки сетки по рядам: сверху, посередине, снизу. */
export const OVERLAY_ANCHORS: readonly OverlayAnchor[] = ['tl', 'tc', 'tr', 'ml', 'mc', 'mr', 'bl', 'bc', 'br']

export const OVERLAY_LIMITS = {
  opacity: { min: 30, max: 100, step: 5 },
  scale: { min: 50, max: 200, step: 5 },
  width: { min: 240, max: 600, step: 10 },
  height: { min: 44, max: 120, step: 2 },
} as const

/** Остров — капсула меньше карточки: доля ширины и высоты, не ниже 34 px. */
const ISLAND = { width: 0.72, height: 0.7, minHeight: 34 }

const clamp = (v: number, min: number, max: number) => Math.min(max, Math.max(min, v))

/** Размер окна оверлея для режима; у полноэкранного размер ставит Rust по монитору. */
export function overlayLayout(mode: OverlayMode, width: number, height: number, scale: number, anchor: OverlayAnchor, monitor = 'primary'): OverlayLayout {
  const k = clamp(scale, OVERLAY_LIMITS.scale.min, OVERLAY_LIMITS.scale.max) / 100
  if (mode === 'island') {
    const h = Math.max(ISLAND.minHeight, height * ISLAND.height)
    return { width: Math.round(width * ISLAND.width * k), height: Math.round(h * k), anchor, fullscreen: false, monitor }
  }
  return { width: Math.round(width * k), height: Math.round(height * k), anchor, fullscreen: mode === 'fullscreen', monitor }
}

/** Выравнивание клетки в долях: 0 — к левому / верхнему краю, 0.5 — по центру, 1 — к правому / нижнему. */
export function anchorAlign(a: OverlayAnchor): { x: number; y: number } {
  const frac = { l: 0, c: 0.5, r: 1, t: 0, m: 0.5, b: 1 } as const
  return { x: frac[a[1] as 'l' | 'c' | 'r'], y: frac[a[0] as 't' | 'm' | 'b'] }
}

/** Ближайшая клетка к точке на макете экрана (доли 0…1) — куда «прилипает» отпущенная плашка. */
export function nearestAnchor(x: number, y: number): OverlayAnchor {
  const col = x < 1 / 3 ? 'l' : x > 2 / 3 ? 'r' : 'c'
  const row = y < 1 / 3 ? 't' : y > 2 / 3 ? 'b' : 'm'
  return `${row}${col}`
}

export interface AutoState {
  /** «Появляться само» включено. */
  auto: boolean
  mode: OverlayMode
  /** Окно Sonar на экране (не свёрнуто и не в трее). */
  mainShown: boolean
  /** Открыто мини-окно — оверлей не нужен, плашка уже есть. */
  miniOpen: boolean
  overlayOpen: boolean
  /** Оверлей открыт самим Sonar, а не клавишей. */
  openedByAuto: boolean
}

/** Что сделать сейчас: открыть оверлей, закрыть его или ничего. Закрываем только открытый «само». */
export function autoStep(s: AutoState): 'open' | 'close' | null {
  if (s.overlayOpen) return s.openedByAuto && (s.mainShown || !s.auto || s.mode === 'off') ? 'close' : null
  return s.auto && s.mode !== 'off' && !s.mainShown && !s.miniOpen ? 'open' : null
}
