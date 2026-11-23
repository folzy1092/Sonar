// Настройки сведения (docs/BLEND.md §7.3, §10.2): ключи `audio.blend_*` → `BlendSettings` контроллера и выбор
// «Переход между треками» (Обычный · Кроссфейд · Сведение) поверх `audio.blend` и `audio.crossfade`.

import type { BlendSettings } from './controller.svelte'
import { BLEND_KINDS, type BlendType } from './planner'

export const BLEND_TYPES: readonly BlendType[] = ['auto', ...BLEND_KINDS]
export const BLEND_LENGTHS = [6, 10, 16] as const
export const CUT_MAX_SEC = 45
/** Отметка на ползунке «Можно срезать». */
export const CUT_RECOMMENDED_SEC = 16
export const TEMPO_TOL_MAX_PCT = 12
/** Кроссфейд, который включается выбором «Кроссфейд», если длины ещё нет, с. */
export const CROSSFADE_DEFAULT_SEC = 6

export type TransitionMode = 'normal' | 'crossfade' | 'blend'

/** Сырые значения ключей (что лежит в настройках, может быть старым или битым). */
export interface BlendKeys {
  type: unknown
  length: unknown
  cut: unknown
  tempo: unknown
  key: unknown
}

const num = (v: unknown, fallback: number) => (typeof v === 'number' && Number.isFinite(v) ? v : fallback)
const clamp = (x: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, x))

/** Ближайшая из трёх длин. */
function nearestLength(sec: number): number {
  return BLEND_LENGTHS.reduce<number>((best, l) => (Math.abs(l - sec) < Math.abs(best - sec) ? l : best), 10)
}

export function blendSettings(k: BlendKeys): BlendSettings {
  const type = BLEND_TYPES.includes(k.type as BlendType) ? (k.type as BlendType) : 'auto'
  return {
    type,
    lengthSec: nearestLength(num(k.length, 10)),
    cutSec: clamp(Math.round(num(k.cut, CUT_RECOMMENDED_SEC)), 0, CUT_MAX_SEC),
    tempoTolPct: clamp(Math.round(num(k.tempo, 8)), 0, TEMPO_TOL_MAX_PCT),
    keyShift: k.key !== false,
  }
}

export function transitionMode(blend: boolean, crossfadeSec: number): TransitionMode {
  if (blend) return 'blend'
  return crossfadeSec > 0 ? 'crossfade' : 'normal'
}

/** Что записать в `audio.blend` и `audio.crossfade`. Сведение длину кроссфейда не трогает — это подстраховка. */
export function applyMode(mode: TransitionMode, crossfadeSec: number): { blend: boolean; crossfade: number } {
  if (mode === 'blend') return { blend: true, crossfade: crossfadeSec }
  if (mode === 'crossfade') return { blend: false, crossfade: crossfadeSec > 0 ? crossfadeSec : CROSSFADE_DEFAULT_SEC }
  return { blend: false, crossfade: 0 }
}
