// Что показывает кнопка сведения (docs/BLEND.md §10.1): имена видов и длин, карточка «Следующий переход».
// Строки — русские ключи `t()`, переводит компонент; здесь только выбор состояния и числа.

import type { BlendAnalysis } from './analysis'
import type { AnalysisState } from './analyze.svelte'
import { camelotName } from './camelot'
import { barMs, type BlendKind, type BlendType, type TransitionPlan } from './planner'

export const KIND_TEXT: Record<BlendType, { short: string; name: string; about: string }> = {
  auto: { short: 'Авто', name: 'Авто', about: 'Сам выбирает вид под пару треков' },
  bass: { short: 'Бас', name: 'Бас-свап', about: 'Басы меняются местами на сильную долю' },
  filter: { short: 'Фильтр', name: 'Фильтр', about: 'Трек уходит в фильтр, следующий раскрывается из глухого' },
  echo: { short: 'Эхо', name: 'Эхо', about: 'Трек обрывается в эхо, следующий входит на «раз»' },
  smooth: { short: 'Сведение::Плавно', name: 'Плавный', about: 'Длинное наложение без резких мест' },
  drop: { short: 'Дроп', name: 'На дроп', about: 'Короткий разгон и сразу дроп следующего' },
}

export const LENGTH_TEXT: Record<number, string> = { 6: 'Коротко', 10: 'Норм', 16: 'Длинно' }

export interface CardInput {
  on: boolean
  repeatOne: boolean
  /** Играющий и следующий треки. */
  a: string | null
  b: string | null
  stateA: AnalysisState
  stateB: AnalysisState
  /** Для пары не нашлось плана или B не загрузился. */
  failed: boolean
  next: { from: string; to: string; plan: TransitionPlan; rank: number; total: number } | null
  anA: BlendAnalysis | null
  anB: BlendAnalysis | null
  /** Своя скорость A: длина перехода в секундах — уже с ней. */
  rateA: number
}

export interface PlanCard {
  state: 'plan'
  kind: BlendKind
  sync: boolean
  /** Длина перехода, с (одна цифра после запятой). */
  sec: number
  rank: number
  total: number
  /** Где A уходит и откуда входит B, мс файла. */
  outMs: number
  inMs: number
  tempoA: number
  tempoB: number
  keyA: string
  keyB: string
}

export type Card =
  | { state: 'off' | 'idle' | 'repeat' | 'last' | 'counting' | 'no-analysis' | 'no-plan' | 'waiting' }
  | PlanCard

export function cardFor(c: CardInput): Card {
  if (!c.on) return { state: 'off' }
  if (!c.a) return { state: 'idle' }
  if (c.repeatOne) return { state: 'repeat' }
  if (!c.b) return { state: 'last' }
  if (c.failed) return { state: 'no-plan' }
  if (c.stateA === 'failed' || c.stateB === 'failed') return { state: 'no-analysis' }
  const n = c.next
  if (n && n.from === c.a && n.to === c.b && c.anA && c.anB) return planCard(n, c.anA, c.anB, c.rateA)
  if (c.stateA !== 'ready' || c.stateB !== 'ready') return { state: 'counting' }
  return { state: 'waiting' }
}

function planCard(n: NonNullable<CardInput['next']>, anA: BlendAnalysis, anB: BlendAnalysis, rateA: number): PlanCard {
  const p = n.plan
  return {
    state: 'plan',
    kind: p.kind,
    sync: p.sync,
    sec: Math.round((p.bars * barMs(anA)) / Math.max(rateA, 0.01) / 100) / 10,
    rank: n.rank,
    total: n.total,
    outMs: p.outMs,
    inMs: p.inMs,
    tempoA: Math.round(p.tempoA),
    tempoB: Math.round(p.tempoB),
    keyA: camelotName(anA.key),
    keyB: camelotName(anB.key),
  }
}

/** Подпись на самой кнопке: включено — короткое имя вида, иначе пусто (значок). */
export function buttonLabel(on: boolean, type: BlendType): string {
  return on ? KIND_TEXT[type].short : ''
}
