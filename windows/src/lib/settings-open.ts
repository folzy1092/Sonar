// Как открываются настройки (NEXT_PROMPT «Этап 0» п. 7, docs/PLATFORMS.md «Открытие настроек»):
// вкладки сверху или снизу — панель опускается (поднимается) шторкой с той же стороны, окно
// остаётся на месте под затемнением; вкладки сбоку — прежний выезд с наклоном окна вглубь.

export type TabsPosition = 'top' | 'bottom' | 'left' | 'right'
export type OpenMode = TabsPosition

/** Длительность шторки: пружина около 350 мс. */
export const SHUTTER_MS = 350

/** Плавающая панель вкладок раскладывает окно как левая (App.svelte `tabs-left`). */
export function openMode(position: TabsPosition, style: string): OpenMode {
  return style === 'floating' ? 'left' : position
}

export const isShutter = (mode: OpenMode) => mode === 'top' || mode === 'bottom'

/** Пружина: затухание 0.7 — перелёт около 4 %, к концу отрезка успокаивается. */
const DAMPING = 0.7
const STIFFNESS = 8
const SAMPLES = 28

function spring(t: number): number {
  const wd = STIFFNESS * Math.sqrt(1 - DAMPING * DAMPING)
  const decay = Math.exp(-DAMPING * STIFFNESS * t)
  return 1 - decay * (Math.cos(wd * t) + ((DAMPING * STIFFNESS) / wd) * Math.sin(wd * t))
}

/** Кривая пружины для `transition-timing-function` — CSS `linear(…)` из точек. */
export function springEasing(): string {
  const points = Array.from({ length: SAMPLES + 1 }, (_, i) => {
    if (i === 0) return '0'
    if (i === SAMPLES) return '1'
    return String(Math.round(spring(i / SAMPLES) * 1000) / 1000)
  })
  return `linear(${points.join(',')})`
}

export interface Box {
  left: number
  top: number
  right: number
  bottom: number
}

/** Вуаль затемняет окно целиком, кроме панели вкладок: шестерёнка остаётся под рукой. */
export function veilClip(rail: Box | null): string {
  if (!rail) return 'none'
  const { left: l, top: tp, right: r, bottom: b } = rail
  const hole = [`${l}px ${tp}px`, `${r}px ${tp}px`, `${r}px ${b}px`, `${l}px ${b}px`, `${l}px ${tp}px`]
  return `polygon(evenodd, 0 0, 100% 0, 100% 100%, 0 100%, 0 0, ${hole.join(', ')})`
}
