// Кривые сведения → `AudioParam` цепочки дека (docs/BLEND.md §6.3). Контроллер раз в 50 мс отменяет всё
// запланированное и кладёт рампы на ближайшую секунду: ключевые такты (свап басов, «раз») ставятся точно,
// между ними — выборки каждые 100 мс (экспонента частот, равная мощность громкости).

import { type BlendCurves, DECK_PARAMS, type DeckParam, type DeckValues, keyBars, valueAt } from './curves'
import { type Band, MIN_RAMP_SEC } from './deck-chain'

/** Что контроллер трогает в `DeckChain`. Подмножество, чтобы тесты могли подставить игрушечный граф. */
export interface ChainLike {
  gain: { gain: AudioParam }
  bands: Record<Band, { gain: AudioParam }>
  hp: { frequency: AudioParam; Q: AudioParam }
  lp: { frequency: AudioParam }
  echoSend: { gain: AudioParam }
  feedback: { gain: AudioParam }
  delay: { delayTime: AudioParam }
  setUserPitch(ratio: number): Promise<void>
  setShift(ratio: number): Promise<void>
}

export type Side = 'a' | 'b'

/** Шаг выборки кривой между ключевыми тактами, с. */
const SAMPLE_SEC = 0.1

export function paramOf(chain: ChainLike, p: DeckParam): AudioParam {
  switch (p) {
    case 'gain':
      return chain.gain.gain
    case 'low':
    case 'mid':
    case 'high':
      return chain.bands[p].gain
    case 'hpHz':
      return chain.hp.frequency
    case 'hpQ':
      return chain.hp.Q
    case 'lpHz':
      return chain.lp.frequency
    case 'echoSend':
      return chain.echoSend.gain
    case 'feedback':
      return chain.feedback.gain
  }
}

/** Значение ручки дека на такте. A до начала перехода — в нейтрали; громкость B — с поправкой `gainMul`. */
export function deckValue(c: BlendCurves, side: Side, p: DeckParam, bar: number, gainMul = 1): number {
  const rest = c.rest[p]
  if (side === 'a' && bar < 0) return rest
  const v = valueAt(c[side][p], rest, bar)
  return p === 'gain' && side === 'b' ? v * gainMul : v
}

/** Ручки, у которых в этом переходе есть кривая. */
export function curvedParams(c: BlendCurves, side: Side): DeckParam[] {
  return DECK_PARAMS.filter((p) => (c[side][p]?.length ?? 0) > 0)
}

/** Все значения дека на такте (для ручек без кривой — нейтраль). */
export function deckValues(c: BlendCurves, side: Side, bar: number, gainMul = 1): DeckValues {
  const out = { ...c.rest }
  for (const p of DECK_PARAMS) out[p] = deckValue(c, side, p, bar, gainMul)
  return out
}

export interface Span {
  /** Такт сейчас. */
  bar: number
  /** Время контекста сейчас, с. */
  t0: number
  /** Секунд на такт при текущем темпе. */
  secPerBar: number
  /** На сколько секунд вперёд класть рампы. */
  horizonSec: number
}

/** Такты точек рампы в окне: ключевые + равномерные выборки, по порядку, без повторов. */
export function spanBars(c: BlendCurves, s: Span): number[] {
  const to = s.bar + s.horizonSec / s.secPerBar
  const stepBars = SAMPLE_SEC / s.secPerBar
  const bars = new Set(keyBars(c, s.bar, to))
  for (let x = s.bar + stepBars; x < to; x += stepBars) bars.add(x)
  bars.add(to)
  return [...bars].sort((x, y) => x - y)
}

/** Положить кривые одного дека на окно вперёд. */
export function scheduleDeck(chain: ChainLike, c: BlendCurves, side: Side, s: Span, gainMul = 1) {
  const bars = spanBars(c, s)
  for (const p of curvedParams(c, side)) {
    const param = paramOf(chain, p)
    param.cancelScheduledValues(s.t0)
    param.setValueAtTime(deckValue(c, side, p, s.bar, gainMul), s.t0)
    for (const bar of bars)
      param.linearRampToValueAtTime(deckValue(c, side, p, bar, gainMul), s.t0 + (bar - s.bar) * s.secPerBar)
  }
}

/** Сразу выставить значения (дек молчит или стоит — скачок не слышен). */
export function setDeck(chain: ChainLike, values: Partial<DeckValues>, t: number) {
  for (const [p, v] of Object.entries(values) as [DeckParam, number][]) {
    const param = paramOf(chain, p)
    param.cancelScheduledValues(t)
    param.setValueAtTime(v, t)
  }
}

/** Плавно за `sec` привести ручки к значениям (отмена, «Следующий», конец перехода). */
export function rampDeck(chain: ChainLike, values: Partial<DeckValues>, t: number, sec: number) {
  for (const [p, v] of Object.entries(values) as [DeckParam, number][]) {
    const param = paramOf(chain, p)
    param.cancelScheduledValues(t)
    param.setValueAtTime(param.value, t)
    param.linearRampToValueAtTime(v, t + Math.max(MIN_RAMP_SEC, sec))
  }
}

/** Остановить автоматизацию на такте (пауза): значения замирают. */
export function freezeDeck(chain: ChainLike, c: BlendCurves, side: Side, bar: number, t: number, gainMul = 1) {
  const values: Partial<DeckValues> = {}
  for (const p of curvedParams(c, side)) values[p] = deckValue(c, side, p, bar, gainMul)
  setDeck(chain, values, t)
}
