// Стили и анимации текста — формулы из Dotify один в один (владелец, 2026-11-15): прозрачность строк
// по расстоянию от текущей, «Масштаб / Размытие / Кино / Сдвиг», 9 анимаций смены строки и
// проявления слов в караоке. Чистые функции — покрыты тестами.
import type { Line, Word } from './types'

export type TextStyle = 'normal' | 'scale' | 'blur' | 'cinema' | 'shift'
export type TextAnim = 'normal' | 'fade' | 'blur' | 'flip3d' | 'bounce' | 'wave' | 'float' | 'drift' | 'zoom'

export interface LineLook {
  opacity: number
  transform: string
  filter: string
  letterSpacing: string
  transition: string
}

const T_NORMAL = (cur: boolean) => `opacity ${cur ? 870 : 1010}ms cubic-bezier(0.33, 0, 0.2, 1), transform 868ms cubic-bezier(0.22, 1, 0.36, 1)`
const T_SOFT = 'opacity 700ms cubic-bezier(0.22, 1, 0.36, 1), transform 700ms cubic-bezier(0.22, 1, 0.36, 1), filter 560ms cubic-bezier(0.22, 1, 0.36, 1)'
const T_SLOW = 'opacity 1092ms cubic-bezier(0.25, 1, 0.35, 1), transform 1092ms cubic-bezier(0.25, 1, 0.35, 1), filter 840ms cubic-bezier(0.25, 1, 0.35, 1)'

/** Прозрачность строки: текущая 1, следующая 0.58, прошлая 0.42, дальше — тише. */
export function lineOpacity(delta: number, synced: boolean, isBg: boolean): number {
  const d = Math.abs(delta)
  let at = 1
  if (!synced) at = 0.85
  else if (delta < 0) at = delta === -1 ? 0.42 : Math.max(0.16, 0.3 - 0.07 * (d - 2))
  else if (delta > 0) at = delta === 1 ? 0.58 : delta === 2 ? 0.4 : Math.max(0.18, 0.28 - 0.05 * (delta - 3))
  if (delta === 0 && synced) return isBg ? 0.88 : 1
  return isBg ? 0.8 * at : at
}

/** Вид строки: `delta` — индекс минус индекс текущей (0 — текущая). `reduced` — без движения. */
export function lineLook(style: TextStyle, anim: TextAnim, delta: number, synced: boolean, isBg = false, reduced = false): LineLook {
  const cur = delta === 0
  const d = Math.abs(delta)
  const opacity = lineOpacity(delta, synced, isBg)

  let it = 1
  let blurStyle: string | null = null
  let spacing = 'normal'
  let shift = 0
  if (style === 'scale') it = cur ? 1.08 : Math.max(0.74, 1 - 0.07 * d)
  else if (style === 'blur') {
    it = cur ? 1.05 : Math.max(0.82, 1 - 0.05 * d)
    blurStyle = cur ? 'none' : `blur(${Math.min(2.5 * d, 7)}px)`
  } else if (style === 'cinema') {
    spacing = '0.02em'
    it = cur ? 1.04 : 0.95
  } else if (style === 'shift') {
    shift = cur ? 14 : 0
    it = cur ? 1.04 : 0.96
  }

  let ty = 0
  let tz = 0
  let tx = shift
  let rx = 0
  let rz = 0
  let skew = 0
  let k = 1
  let filter = blurStyle ?? 'none'
  if (!blurStyle) {
    if (anim === 'blur') {
      filter = cur ? 'blur(0px)' : d === 1 ? 'blur(2.6px)' : 'blur(5.5px)'
      ty = cur ? 0 : delta === 1 ? 5 : -4
    } else if (anim === 'float') filter = cur || d < 1 ? 'none' : 'blur(1.5px)'
    else if (anim === 'zoom') filter = cur || d < 2 ? 'none' : 'blur(2.2px)'
  }
  const side = (a: number, b: number) => (cur ? 0 : delta === 1 ? a : b)
  switch (anim) {
    case 'flip3d':
      rx = cur ? 0 : delta === 1 ? 10 : delta === -1 ? -8 : delta > 0 ? 16 : -14
      tz = cur ? 8 : -4
      ty = side(3, -3)
      k = cur ? 1.03 : 0.98
      break
    case 'bounce':
      k = cur ? 1.036 : d === 1 ? 0.985 : 0.965
      ty = side(3, -3)
      break
    case 'wave':
      ty = cur ? 0 : delta === 1 ? 3 : delta === -1 ? -3 : delta > 0 ? 6 : -5
      rz = cur ? 0 : delta === 1 ? 0.5 : delta === -1 ? -0.5 : 0
      k = cur ? 1.028 : 0.985
      break
    case 'float':
      ty = cur ? -1 : delta === 1 ? 4 : delta === -1 ? -4 : delta > 0 ? 7 : -6
      k = cur ? 1.032 : 0.985
      break
    case 'drift':
      skew = cur ? 0 : delta === 1 ? -2 : delta === -1 ? 1.5 : 0
      tx = shift + (cur ? 0 : delta === 1 ? 3 : delta === -1 ? -2 : 0)
      ty = side(3, -3)
      k = cur ? 1.028 : 0.985
      break
    case 'zoom':
      k = cur ? 1.042 : d === 1 ? 0.97 : Math.max(0.92, 1 - 0.02 * d)
      ty = side(3, -3)
      break
    case 'blur':
      k = cur ? 1.032 : 0.98
      ty = side(3, -3)
      break
  }
  const scale = style === 'scale' || style === 'blur' ? it : k * it
  const simple = anim === 'normal' || anim === 'fade'

  let transform = 'none'
  if (!(simple && style === 'normal'))
    transform = simple
      ? `translate3d(${shift}px, 0, 0) scale(${it})`
      : `perspective(800px) translate3d(${tx}px, ${ty}px, ${tz}px) scale(${scale}) rotateX(${rx}deg) rotateZ(${rz}deg) skewX(${skew}deg)`

  let transition: string
  if (simple && style !== 'normal') transition = T_SOFT
  else if (anim === 'normal') transition = T_NORMAL(cur)
  else if (anim === 'bounce')
    transition = 'opacity 840ms cubic-bezier(0.22, 1, 0.36, 1), transform 868ms cubic-bezier(0.34, 1.3, 0.64, 1), filter 630ms cubic-bezier(0.22, 1, 0.36, 1)'
  else if (anim === 'float')
    transition = 'opacity 952ms cubic-bezier(0.22, 1, 0.36, 1), transform 952ms cubic-bezier(0.22, 1, 0.36, 1), filter 700ms cubic-bezier(0.22, 1, 0.36, 1)'
  else if (anim === 'fade') transition = 'opacity 924ms cubic-bezier(0.33, 0, 0.2, 1)'
  else transition = T_SLOW

  if (reduced) return { opacity, transform: 'none', filter: 'none', letterSpacing: spacing, transition: 'opacity 420ms linear' }
  return { opacity, transform, filter, letterSpacing: spacing, transition }
}

export interface WordLook {
  opacity?: number
  transform?: string
  filter?: string
  transition?: string
}

/** Слово текущей строки в караоке (кроме «Обычной» — та идёт заливкой). `p` — прогресс слова. */
export function wordLook(anim: TextAnim, p: number, past: boolean, current: boolean): WordLook {
  const op = past ? 1 : current ? 0.5 + 0.5 * p : 0.52
  switch (anim) {
    case 'fade':
      return { opacity: op, transition: 'opacity 220ms cubic-bezier(0.16, 1, 0.3, 1)' }
    case 'blur':
      return {
        opacity: op,
        filter: past ? 'none' : current ? (p > 0.95 ? 'none' : `blur(${(3.5 * (1 - p)).toFixed(2)}px)`) : 'blur(3px)',
        transition: 'filter 120ms cubic-bezier(0.16, 1, 0.3, 1), opacity 90ms cubic-bezier(0.16, 1, 0.3, 1)',
      }
    case 'flip3d':
      return {
        opacity: op,
        transform: `perspective(400px) rotateX(${past ? 0 : current ? 45 * (1 - p) : 45}deg)`,
        transition: 'transform 240ms cubic-bezier(0.16, 1, 0.3, 1), opacity 120ms ease-out',
      }
    case 'bounce':
      return {
        opacity: op,
        transform: past ? 'scale(1) translateY(0px)' : current ? `scale(${0.93 + 0.07 * p}) translateY(${(-2.5 * (1 - p)).toFixed(2)}px)` : 'scale(0.93) translateY(0px)',
        transition: 'transform 200ms cubic-bezier(0.34, 1.45, 0.64, 1), opacity 90ms ease-out',
      }
    case 'wave':
      return {
        opacity: op,
        transform: `translateY(${current ? (-3.2 * Math.sin(p * Math.PI)).toFixed(1) : 0}px)`,
        transition: 'transform 160ms cubic-bezier(0.16, 1, 0.3, 1), opacity 90ms ease-out',
      }
    case 'float':
      return {
        opacity: op,
        transform: `translateY(${(past ? 0 : current ? 4.5 * (1 - p) : 4.5).toFixed(1)}px)`,
        transition: 'transform 200ms cubic-bezier(0.16, 1, 0.3, 1), opacity 100ms ease-out',
      }
    case 'drift':
      return {
        opacity: op,
        transform: `skewX(${(past ? 0 : current ? -6 * (1 - p) : -6).toFixed(1)}deg) scale(${past ? 1 : current ? 0.95 + 0.05 * p : 0.95})`,
        transition: 'transform 180ms cubic-bezier(0.16, 1, 0.3, 1), opacity 80ms ease-out',
      }
    case 'zoom':
      return {
        opacity: op,
        transform: `scale(${(past ? 1 : current ? 0.88 + 0.12 * p : 0.88).toFixed(3)})`,
        transition: 'transform 180ms cubic-bezier(0.16, 1, 0.3, 1), opacity 90ms ease-out',
      }
    default:
      return {}
  }
}

/** «Задержка» на длинном слове (≥ 1,2 с): лёгкая вспышка или покачивание по анимации. */
export function holdLook(anim: TextAnim, p: number, duration: number, current: boolean): { transform?: string; filter?: string } {
  if (!current || duration < 1.2) return {}
  const r = Math.sin(Math.PI * p) ** 2
  switch (anim) {
    case 'fade':
      return { filter: `brightness(${1 + 0.12 * r})` }
    case 'blur':
      return { filter: `brightness(${1 + 0.08 * r})` }
    case 'flip3d':
      return { transform: `perspective(400px) rotateX(${(-3 * r).toFixed(2)}deg)` }
    case 'float':
      return { filter: `brightness(${1 + 0.06 * r})` }
    case 'drift':
      return { transform: `skewX(${(-1.5 * r).toFixed(2)}deg)` }
    case 'bounce':
      return { transform: `scale(${1 + 0.045 * r})` }
    case 'zoom':
      return { transform: `scale(${1 + 0.055 * r})` }
    default:
      return { filter: `brightness(${1 + 0.1 * r})` }
  }
}

/** Строка без пословного тайминга → слова, время делится по длине (как в Dotify). */
export function synthWords(line: Line, next?: Line): Word[] {
  const parts = line.text.split(/\s+/).filter(Boolean)
  if (!parts.length) return []
  const end = next && next.time > line.time ? next.time : line.time + Math.max(2.5, 0.08 * line.text.length)
  const span = Math.max(0.4, Math.min(line.duration > 0 ? line.duration : end - line.time, 8))
  const weights = parts.map((w) => w.length + 1)
  const total = weights.reduce((a, b) => a + b, 0)
  let t = line.time
  return parts.map((text, i) => {
    const duration = (span * weights[i]) / total
    const w: Word = { time: t, duration, text, isBackground: false, hasSpaceAfter: i < parts.length - 1 }
    t += duration
    return w
  })
}
