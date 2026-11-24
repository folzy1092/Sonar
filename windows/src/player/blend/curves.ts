// Кривые сведения (docs/BLEND.md §8): чем станет каждая ручка обеих цепочек на каждом такте перехода.
// Чистые данные: по плану — ключевые точки по тактам A от начала перехода (такт 0 = `outMs`), между ними —
// линейно, по экспоненте (частоты) или с равной мощностью (громкость). Контроллер только сэмплирует их и
// кладёт рампами в `AudioParam` (§6.3).
//
// Резкие места (свап басов, сухой A на «раз», дроп) — тоже рампы, но короткие: 5–12 мс, не короче 5 мс
// ни при каком темпе перехода.

import { HP_REST_HZ, ISO_MIN_DB } from './deck-chain'
import { ECHO_DRY_FADE_BARS, type TransitionPlan } from './planner'

export const DECK_PARAMS = ['gain', 'low', 'mid', 'high', 'hpHz', 'hpQ', 'lpHz', 'echoSend', 'feedback'] as const
export type DeckParam = (typeof DECK_PARAMS)[number]
export type DeckValues = Record<DeckParam, number>

/** Как прийти к точке от предыдущей: по прямой, по экспоненте (частоты), с равной мощностью (громкость). */
export type Shape = 'lin' | 'exp' | 'eq'
export interface Key {
  bar: number
  v: number
  shape: Shape
}
type Curve = readonly Key[]
type DeckCurves = Partial<Record<DeckParam, Curve>>

export interface BlendCurves {
  a: DeckCurves
  b: DeckCurves
  /** Такт, где A замолк и B становится текущим (`endAMs`). */
  promoteBar: number
  /** Такт, после которого автоматизации нет (у «Эха» — конец хвоста). */
  endBar: number
  /** Задержка эха, с (¾ доли A). */
  echoDelaySec: number
  rest: DeckValues
}

/** «−∞» изолятора. */
const OFF_DB = ISO_MIN_DB
const Q_REST = Math.SQRT1_2
/** Длительности резких мест (§8), с. */
const SWAP_SEC = 0.008
const DROP_SEC = 0.005
/** Бас-свап расписан на 8 тактов; длиннее или короче — те же доли. */
const BASS_GRID = 8
const FILTER_HP_TO = 1200
const FILTER_Q_TO = 3
const FILTER_LP_FROM = 300
const FILTER_B_LOW_DB = -12
/** Пока HPF у A ниже этой частоты, бас B приглушён: два баса не дерутся. */
const FILTER_BASS_HANDOFF_HZ = 150
const ECHO_FEEDBACK = 0.55
const ECHO_FEEDBACK_TAIL = 0.3
/** B у «Эха» выходит в полную громкость за такт, бас — за два: не стена звука на «раз». */
const ECHO_B_IN_BARS = 1
const ECHO_B_BASS_BARS = 2
/** «На дроп»: последний такт разгона A уходит в эхо, хвост звенит поверх дропа B. */
const DROP_ECHO_FEEDBACK = 0.45
const DROP_HP_TO = 800
const DROP_GAIN = 10 ** (-3 / 20)
const DROP_MID_DB = 3
const HP_FROM = 20
/** «Плавный»: басы встречаются на середине по −3 дБ (с громкостью −3 — по −6 каждый). */
const SMOOTH_MEET_DB = -3
const SMOOTH_FADE_DB = -12
const BEAT = 0.25

/** Нейтраль цепочки: всё прозрачно, эхо молчит. */
export function restValues(nyquist: number): DeckValues {
  return { gain: 1, low: 0, mid: 0, high: 0, hpHz: HP_REST_HZ, hpQ: Q_REST, lpHz: nyquist, echoSend: 0, feedback: 0 }
}

const k = (bar: number, v: number, shape: Shape = 'lin'): Key => ({ bar, v, shape })

/** Секунды → такты при самом быстром темпе перехода (резкое место не короче своих мс). */
function barsOf(plan: TransitionPlan, sec: number): number {
  const fastest = Math.max(plan.tempoA, plan.tempoB / (plan.beatRatio || 1))
  return (sec * fastest) / 240
}

/** Шаг за `sec` с центром на `bar`. */
function step(plan: TransitionPlan, bar: number, from: number, to: number, sec: number): Key[] {
  const half = barsOf(plan, sec) / 2
  return [k(bar - half, from), k(bar + half, to)]
}

function bass(plan: TransitionPlan): Pick<BlendCurves, 'a' | 'b'> {
  const f = plan.bars / BASS_GRID
  const swap = plan.bars / 2
  return {
    a: {
      gain: [k(7 * f, 1), k(8 * f, 0, 'eq')],
      low: step(plan, swap, 0, OFF_DB, SWAP_SEC),
      mid: [k(4 * f, 0), k(7 * f, -12)],
      high: [k(2 * f, 0), k(4 * f, -6), k(7 * f, OFF_DB)],
    },
    b: {
      gain: [k(0, 0), k(2 * f, 1, 'eq')],
      low: step(plan, swap, OFF_DB, 0, SWAP_SEC),
      mid: [k(2 * f, -6), k(4 * f, 0)],
    },
  }
}

function filter(plan: TransitionPlan, nyquist: number): Pick<BlendCurves, 'a' | 'b'> {
  const n = plan.bars
  // такт, где экспонента HPF у A проходит 150 Гц (≈ середина), — оттуда бас B за такт выходит в 0 дБ
  const handoff = (n * Math.log(FILTER_BASS_HANDOFF_HZ / HP_FROM)) / Math.log(FILTER_HP_TO / HP_FROM)
  return {
    a: {
      gain: [k(n - 1, 1), k(n, 0, 'eq')],
      hpHz: [k(0, HP_FROM), k(n, FILTER_HP_TO, 'exp')],
      hpQ: [k(n - 2, Q_REST), k(n, FILTER_Q_TO)],
    },
    b: {
      gain: [k(0, 0), k(Math.min(2, n / 2), 1, 'eq')],
      lpHz: [k(0, FILTER_LP_FROM), k(n, nyquist, 'exp')],
      low: [k(handoff, FILTER_B_LOW_DB), k(handoff + 1, 0)],
    },
  }
}

function echo(plan: TransitionPlan): Pick<BlendCurves, 'a' | 'b'> {
  const one = plan.inAtBar
  const lastBeat = one - BEAT
  const dryEnd = one + ECHO_DRY_FADE_BARS
  const open = barsOf(plan, DROP_SEC)
  return {
    a: {
      // эхо набирается от начала перехода до последней доли, сухой A гаснет полтакта после «раз»; эхо питается
      // после громкости дека — новых повторов нет, хвост крутится в петле до конца перехода
      gain: [k(one, 1), k(dryEnd, 0, 'eq')],
      echoSend: [k(0, 0), k(lastBeat, 1), k(plan.bars - open, 1), k(plan.bars, 0)],
      feedback: [k(0, 0), k(lastBeat, ECHO_FEEDBACK), k(dryEnd, ECHO_FEEDBACK), k(plan.bars, ECHO_FEEDBACK_TAIL)],
    },
    b: {
      gain: [k(one, 0), k(one + ECHO_B_IN_BARS, 1, 'eq')],
      low: [k(one, OFF_DB), k(one + ECHO_B_BASS_BARS, 0)],
    },
  }
}

function smooth(plan: TransitionPlan): Pick<BlendCurves, 'a' | 'b'> {
  const n = plan.bars
  return {
    a: {
      gain: [k(0, 1), k(n, 0, 'eq')],
      low: [k((3 * n) / 8, 0), k(n / 2, SMOOTH_MEET_DB), k((3 * n) / 4, OFF_DB)],
      mid: [k(0, 0), k(n, SMOOTH_FADE_DB)],
      high: [k(0, 0), k(n, SMOOTH_FADE_DB)],
    },
    b: {
      gain: [k(0, 0), k(n, 1, 'eq')],
      low: [k(n / 4, OFF_DB), k(n / 2, SMOOTH_MEET_DB), k((5 * n) / 8, 0)],
      mid: [k(0, SMOOTH_FADE_DB), k(n, 0)],
      high: [k(0, SMOOTH_FADE_DB), k(n, 0)],
    },
  }
}

function drop(plan: TransitionPlan): Pick<BlendCurves, 'a' | 'b'> {
  const n = plan.bars
  const cut = barsOf(plan, DROP_SEC)
  const tail = n + 2
  return {
    a: {
      gain: [k(0, 1), k(n, DROP_GAIN), k(n + cut, 0)],
      hpHz: [k(0, HP_FROM), k(n, DROP_HP_TO, 'exp')],
      mid: [k(n - 1, 0), k(n, DROP_MID_DB)],
      // разгон уходит в эхо: A срезается на дропе, а хвост ещё два такта звенит поверх B
      echoSend: [k(n - 1, 0), k(n - BEAT, 1), k(tail - cut, 1), k(tail, 0)],
      feedback: [k(n - 1, 0), k(n - BEAT, DROP_ECHO_FEEDBACK), k(tail, 0)],
    },
    b: { gain: [k(n, 0), k(n + cut, 1)] },
  }
}

export function curvesFor(plan: TransitionPlan, nyquist: number): BlendCurves {
  const byKind = {
    bass: () => bass(plan),
    filter: () => filter(plan, nyquist),
    echo: () => echo(plan),
    smooth: () => smooth(plan),
    drop: () => drop(plan),
  }
  const { a, b } = byKind[plan.kind]()
  const lastKey = Math.max(...[a, b].flatMap((d) => Object.values(d).flatMap((c) => c.map((x) => x.bar))))
  return {
    a,
    b,
    // A играет, пока не замолк: у «Эха» — ещё полтакта затухания после «раз»
    promoteBar: plan.kind === 'echo' ? plan.inAtBar + ECHO_DRY_FADE_BARS : plan.bars,
    endBar: Math.max(plan.bars, lastKey),
    echoDelaySec: (0.75 * 60) / plan.tempoA,
    rest: restValues(nyquist),
  }
}

function between(from: Key, to: Key, x: number): number {
  if (x >= 1) return to.v // cos(π/2) ≠ 0 в плавающей точке
  if (to.shape === 'eq') return from.v * Math.cos((Math.PI / 2) * x) + to.v * Math.sin((Math.PI / 2) * x)
  if (to.shape === 'exp' && from.v > 0 && to.v > 0) return from.v * (to.v / from.v) ** x
  return from.v + (to.v - from.v) * x
}

/** Значение кривой на такте: до первой точки — её значение, после последней — последней, пусто — нейтраль. */
export function valueAt(curve: Curve | undefined, rest: number, bar: number): number {
  if (!curve?.length) return rest
  if (bar <= curve[0].bar) return curve[0].v
  for (let i = 1; i < curve.length; i++) {
    const to = curve[i]
    if (bar > to.bar) continue
    const from = curve[i - 1]
    const span = to.bar - from.bar
    return span > 0 ? between(from, to, (bar - from.bar) / span) : to.v
  }
  return curve[curve.length - 1].v
}

function deckAt(d: DeckCurves, rest: DeckValues, bar: number): DeckValues {
  const out = { ...rest }
  for (const p of DECK_PARAMS) out[p] = valueAt(d[p], rest[p], bar)
  return out
}

/** Значения обеих цепочек на такте перехода. */
export function paramsAt(c: BlendCurves, bar: number): { a: DeckValues; b: DeckValues } {
  return { a: deckAt(c.a, c.rest, bar), b: deckAt(c.b, c.rest, bar) }
}

/** Такты ключевых точек в (from, to]: на них контроллер ставит точку рампы точно. */
export function keyBars(c: BlendCurves, from: number, to: number): number[] {
  const bars = new Set<number>()
  for (const d of [c.a, c.b])
    for (const curve of Object.values(d)) for (const x of curve) if (x.bar > from && x.bar <= to) bars.add(x.bar)
  return [...bars].sort((x, y) => x - y)
}

/** Соседние точки с разными значениями — по ним тест ловит резкие места короче 5 мс. */
export function steps(c: BlendCurves): { deck: 'a' | 'b'; param: DeckParam; bars: number }[] {
  const out: { deck: 'a' | 'b'; param: DeckParam; bars: number }[] = []
  for (const deck of ['a', 'b'] as const)
    for (const p of DECK_PARAMS) {
      const curve = c[deck][p] ?? []
      for (let i = 1; i < curve.length; i++)
        if (curve[i].v !== curve[i - 1].v) out.push({ deck, param: p, bars: curve[i].bar - curve[i - 1].bar })
    }
  return out
}

const smoothstep = (x: number) => x * x * (3 - 2 * x)

/**
 * Общий темп перехода в сетке A, уд/мин (§6.3): из `TA` в `TB / beatRatio` по smoothstep за всю длину.
 * `null` — без синка, каждый дек на своей скорости.
 */
export function tempoAt(plan: TransitionPlan, bar: number): number | null {
  if (!plan.sync) return null
  const x = Math.min(1, Math.max(0, bar / plan.bars))
  const to = plan.tempoB / plan.beatRatio
  return plan.tempoA + (to - plan.tempoA) * smoothstep(x)
}
