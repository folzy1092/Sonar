// Отладочная карточка сведения (docs/BLEND.md §10.3): числа анализа, фаза перехода, баллы плана.
// Строки — русские ключи `t()`, переводит компонент.

import type { BlendAnalysis } from './analysis'
import { camelotName } from './camelot'
import type { BlendPhase } from './controller.svelte'
import { WEIGHTS, type ScorePart } from './planner'

export const PHASE_TEXT: Record<BlendPhase, string> = {
  idle: 'Отладка::нет',
  planned: 'Отладка::готов',
  prerolling: 'Отладка::прогрев',
  running: 'Отладка::идёт',
  promoting: 'Отладка::доводка',
  fallback: 'Отладка::кроссфейд',
}

export const PART_TEXT: Record<ScorePart, string> = {
  tempo: 'Отладка::темп',
  key: 'Отладка::тон',
  energy: 'Отладка::энергия',
  phrases: 'Отладка::фразы',
  cut: 'Отладка::срез',
  vocal: 'Отладка::вокал',
  fit: 'Отладка::уместность',
  rating: 'Отладка::оценки',
}

/** Число с настоящим минусом: «−9.8». */
export function minus(v: number, digits = 0): string {
  const s = Math.abs(v).toFixed(digits)
  return v < 0 && Number(s) !== 0 ? `−${s}` : s
}

/** «128.0 BPM · 0.91 · 8A · 0.34 · −9.8 LUFS» — одни числа, переводить нечего. */
export function analysisLine(a: BlendAnalysis): string {
  const key = a.key === null ? '—' : `${camelotName(a.key)} · ${a.keyConf.toFixed(2)}`
  return `${a.bpm.toFixed(1)} BPM · ${a.bpmConf.toFixed(2)} · ${key} · ${minus(a.loudness, 1)} LUFS`
}

/** Баллы плана с весами, крупные первыми; почти нулевые не показываем. */
export function scoreParts(parts: Record<ScorePart, number>): { part: ScorePart; value: string }[] {
  return (Object.keys(WEIGHTS) as ScorePart[])
    .map((part) => ({ part, w: WEIGHTS[part] * parts[part] }))
    .filter((p) => Math.abs(p.w) >= 0.05)
    .sort((x, y) => y.w - x.w)
    .map(({ part, w }) => ({ part, value: minus(w, 1) }))
}
