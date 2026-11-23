// Планировщик сведения (docs/BLEND.md §7): по анализу A и B и настройкам — где выйти из A, где войти в B и
// каким видом. Чистая детерминированная функция `plan(a, b, opts)`: перебирает такты конца A, такты входа B
// и виды, оценивает каждую тройку суммой весов (§7.2) и отдаёт топ-8 («Другой момент» берёт следующий).
//
// Время везде — позиция в самом треке (мс). Такт A номер k начинается в
// `firstBeatMs + (downbeat + 4k)·beatMs`; такты можно брать и за концом музыки (там тишина или затухание).
// «Якорь» — такт A, на котором A замолкает: для бас-свапа, фильтра и плавного — конец наложения, для эха —
// «раз» после последней доли фразы (сухой A гаснет, хвост эха идёт дальше), для «На дроп» — вход дропа B.

import type { BlendAnalysis } from './analysis'
import { BEATS_PER_BAR, type PhraseKind } from './structure'
import { SILENT_LUFS } from './loudness'
import { type KeyMatch, keyMatch } from './camelot'

export const BLEND_KINDS = ['bass', 'filter', 'echo', 'smooth', 'drop'] as const
export type BlendKind = (typeof BLEND_KINDS)[number]
export type BlendType = 'auto' | BlendKind

/** Без бит-синка эти виды не звучат: вне допуска темпа — «Эхо» (§6.3). */
const SYNC_KINDS: ReadonlySet<BlendKind> = new Set(['bass', 'filter', 'drop'])
/** Долгое наложение двух треков — тут важна тональность и вокал. */
const OVERLAP_KINDS: ReadonlySet<BlendKind> = new Set(['bass', 'filter', 'smooth'])

export const TOP_PLANS = 8
const LENGTH_BARS = [4, 8, 16]
const SMOOTH_MIN_BARS = 16
/** Короткие виды («Эхо» — хвост, «На дроп» — разгон): 4 такта при длинном переходе, иначе 2. */
const SHORT_BARS = 2
const LONG_SHORT_BARS = 4
const MAX_GAIN_DB = 9
/** Тактов по краям наложения для энергии. */
const EDGE_BARS = 2
const CALM = 0.4
const LOUD = 0.6
const SPECTRUM_GAP = 0.35
const VOCAL_FROM = 0.5
/** Сколько теряет вид при несовместимой тональности (§7.4). */
const CLASH_FIT = 0.5
const BEAT_RATIOS = [0.5, 1, 2] as const

/** Веса слагаемых оценки (§7.2). */
export const WEIGHTS = { tempo: 3, key: 2, energy: 2, phrases: 1.5, cut: 1, vocal: 1, fit: 1, rating: 0.5 } as const
export type ScorePart = keyof typeof WEIGHTS
const WEIGHT_SUM = Object.values(WEIGHTS).reduce((s, w) => s + w, 0)

export interface PlanOpts {
  /** `audio.blend_type`. */
  type: BlendType
  /** `audio.blend_length`, с. */
  lengthSec: number
  /** `audio.blend_cut`: сколько можно срезать с конца A и с начала B, с. */
  cutSec: number
  /** `audio.blend_tempo`: допуск темпа, %. */
  tempoTolPct: number
  /** `audio.blend_key`: можно сдвигать тон B. */
  keyShift: boolean
  /** Собственные скорости треков (§6.3) и связана ли с ней высота тона. */
  rateA: number
  rateB: number
  linkedA: boolean
  linkedB: boolean
  /** Перевес 👍/👎 по видам за 60 дней, −1…1 (§8.6). */
  ratings?: Partial<Record<BlendKind, number>>
}

export interface TransitionPlan {
  kind: BlendKind
  /** Темп сводится и доли совпадают. */
  sync: boolean
  /** Длина перехода в тактах A. */
  bars: number
  /** Позиция A в начале перехода (начало такта). */
  outMs: number
  /** Позиция A, где он замолкает (конец полосы прогресса, §6.5). */
  endAMs: number
  /** Позиция B, с которой он стартует (начало такта). */
  inMs: number
  /** На каком такте перехода стартует B: 0 — сразу, у «Эха» — 1, у «На дроп» — в конце разгона. */
  inAtBar: number
  /** Эффективные темпы с собственными скоростями, уд/мин. */
  tempoA: number
  tempoB: number
  /** B считается в удвоенной (2) или половинной (0.5) сетке. */
  beatRatio: number
  /** Сдвиг тона B на время перехода, полутонов. */
  shift: number
  /** Поправка громкости B под A, дБ. */
  gainDb: number
  /** Срезано с конца A и с начала B, мс. */
  cutOutMs: number
  cutInMs: number
  /** 0…1. */
  score: number
  parts: Record<ScorePart, number>
}

interface Shape {
  bars: number
  /** Тактов A до якоря. */
  lead: number
  inAtBar: number
}

interface Pair {
  a: BlendAnalysis
  b: BlendAnalysis
  opts: PlanOpts
  tempoA: number
  tempoB: number
  beatRatio: number
  syncOk: boolean
  tempoScore: number
  base: number
  keySync: KeyMatch
  keyFree: KeyMatch
  keyFixed: KeyMatch
  phrasesA: Map<number, PhraseKind>
  phrasesB: Map<number, PhraseKind>
  gainDb: number
}

interface Candidate {
  kind: BlendKind
  anchor: number
  entry: number
}

const clamp = (x: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, x))
const round = (x: number, digits: number) => Math.round(x * 10 ** digits) / 10 ** digits

export const barMs = (t: BlendAnalysis) => BEATS_PER_BAR * t.beatMs
export const barTime = (t: BlendAnalysis, bar: number) => t.firstBeatMs + (t.downbeat + BEATS_PER_BAR * bar) * t.beatMs

function mean(xs: number[], from: number, to: number): number {
  let sum = 0
  let n = 0
  for (let i = Math.max(0, from); i < to; i++, n++) sum += xs[i] ?? 0
  return n > 0 ? sum / n : 0
}

/** Длина перехода в тактах: секунды при темпе A, ближайшее из 4 / 8 / 16 (по отношению, не по разнице). */
export function lengthBars(lengthSec: number, tempo: number): number {
  const bars = (lengthSec * tempo) / 60 / BEATS_PER_BAR
  return LENGTH_BARS.reduce((best, n) => (Math.abs(Math.log2(bars / n)) < Math.abs(Math.log2(bars / best)) ? n : best))
}

/** B ближе к удвоенному или половинному темпу A, чем к тому же, — считаем его в такой сетке. */
function beatRatioOf(ratio: number): number {
  return BEAT_RATIOS.reduce((best, k) => (Math.abs(Math.log2(ratio / k)) < Math.abs(Math.log2(ratio / best)) ? k : best))
}

const drift = (linked: boolean, rate: number) => (linked && rate > 0 ? 12 * Math.log2(rate) : 0)

function pairOf(a: BlendAnalysis, b: BlendAnalysis, opts: PlanOpts): Pair {
  const tempoA = a.bpm * opts.rateA
  const tempoB = b.bpm * opts.rateB
  const beatRatio = beatRatioOf(tempoB / tempoA)
  const diff = Math.abs(tempoB / beatRatio / tempoA - 1)
  const tol = Math.max(0, opts.tempoTolPct) / 100
  const tempoScore = tol > 0 ? clamp(1 - diff / tol, 0, 1) : diff < 1e-6 ? 1 : 0
  const syncOk = diff <= tol + 1e-9 && a.gridStable && b.gridStable
  const driftA = drift(opts.linkedA, opts.rateA)
  // в синке B играет со скоростью, при которой его доли совпадают с долями A
  const syncRateB = (tempoA * beatRatio) / b.bpm
  const keyOpts = (rateB: number, allowShift: boolean) => ({ driftA, driftB: drift(opts.linkedB, rateB), allowShift })
  const silent = a.loudness <= SILENT_LUFS || b.loudness <= SILENT_LUFS
  return {
    a,
    b,
    opts,
    tempoA,
    tempoB,
    beatRatio,
    syncOk,
    tempoScore,
    base: lengthBars(opts.lengthSec, tempoA),
    keySync: keyMatch(a.key, b.key, keyOpts(syncRateB, opts.keyShift)),
    keyFree: keyMatch(a.key, b.key, keyOpts(opts.rateB, opts.keyShift)),
    keyFixed: keyMatch(a.key, b.key, keyOpts(opts.rateB, false)),
    phrasesA: new Map(a.phrases.map((p) => [p.bar, p.kind])),
    phrasesB: new Map(b.phrases.map((p) => [p.bar, p.kind])),
    gainDb: silent ? 0 : round(clamp(a.loudness - b.loudness, -MAX_GAIN_DB, MAX_GAIN_DB), 1),
  }
}

function shapeOf(kind: BlendKind, base: number): Shape {
  const short = base >= 8 ? LONG_SHORT_BARS : SHORT_BARS
  if (kind === 'echo') return { bars: 1 + short, lead: 1, inAtBar: 1 }
  if (kind === 'drop') return { bars: short, lead: short, inAtBar: short }
  const bars = kind === 'smooth' ? Math.max(SMOOTH_MIN_BARS, base) : base
  return { bars, lead: bars, inAtBar: 0 }
}

/** Какие виды пробовать: ручной вид без синка откатывается на «Эхо», «Плавный» идёт без синка (§6.3). */
export function kindsFor(type: BlendType, syncOk: boolean): BlendKind[] {
  if (type === 'auto') return syncOk ? [...BLEND_KINDS] : ['echo', 'smooth']
  if (SYNC_KINDS.has(type) && !syncOk) return ['echo']
  return [type]
}

/** Такты A, где он может замолкнуть: от `endMs − cut` до конца файла (или такт за концом музыки). */
function anchorsOf(a: BlendAnalysis, cutMs: number): number[] {
  const from = a.endMs - cutMs
  const to = Math.max(a.durationMs, a.endMs + barMs(a))
  const out: number[] = []
  for (let k = 0; barTime(a, k) <= to; k++) if (barTime(a, k) >= from) out.push(k)
  return out
}

/** Такты B, с которых он может стартовать: не дальше `startMs + cut` и в пределах музыки. */
function entriesOf(b: BlendAnalysis, cutMs: number): number[] {
  const out: number[] = []
  for (let j = 0; j < b.bars.energy.length && barTime(b, j) <= b.startMs + cutMs; j++) {
    if (barTime(b, j) >= 0) out.push(j)
  }
  return out
}

function startScore(phrases: Map<number, PhraseKind>, bar: number): number {
  if (phrases.get(bar) === 'outro') return 1
  if (phrases.has(bar)) return 0.8
  return bar % 4 === 0 ? 0.4 : 0.1
}

function endScore(phrases: Map<number, PhraseKind>, nBars: number, bar: number): number {
  if (bar === nBars) return 1
  if (bar > nBars) return 0.6
  if (phrases.has(bar)) return 0.9
  return bar % 4 === 0 ? 0.4 : 0.1
}

function inScore(phrases: Map<number, PhraseKind>, bar: number, kind: BlendKind): number {
  const at = phrases.get(bar)
  if (kind === 'drop' ? at === 'drop' : bar === 0 || at === 'intro') return 1
  if (at) return 0.8
  return bar % 4 === 0 ? 0.4 : 0.1
}

/** Вид фразы, в которой лежит такт. */
function phraseAt(t: BlendAnalysis, bar: number): PhraseKind | null {
  let kind: PhraseKind | null = null
  for (const p of t.phrases) if (p.bar <= bar) kind = p.kind
  return kind
}

interface Facts {
  syncOk: boolean
  clash: boolean
  calm: boolean
  loud: boolean
  outroA: boolean
  introB: boolean
  dropB: boolean
  spectrumGap: boolean
}

/** Насколько вид подходит паре (§7.5): не правило, а бонус. */
function kindFit(kind: BlendKind, f: Facts): number {
  let fit: number
  if (kind === 'echo') fit = !f.syncOk || f.clash ? 1 : 0.3
  else if (kind === 'smooth') fit = f.calm ? 1 : 0.4
  else if (kind === 'bass') fit = f.outroA && f.introB ? 1 : 0.5
  else if (kind === 'drop') fit = f.dropB ? (f.loud ? 1 : 0.6) : 0.1
  else fit = f.spectrumGap ? 1 : 0.5
  return OVERLAP_KINDS.has(kind) && f.clash ? fit * CLASH_FIT : fit
}

function keyFor(p: Pair, kind: BlendKind, sync: boolean): { term: number; match: KeyMatch } {
  if (!OVERLAP_KINDS.has(kind)) {
    // наложения нет или оно — хвост эха: тон не сдвигаем, а несовместимость почти не слышна
    return { term: Math.max(0.5, p.keyFixed.score), match: { ...p.keyFixed, shift: 0 } }
  }
  const match = sync ? p.keySync : p.keyFree
  return { term: match.score, match }
}

function evaluate(p: Pair, c: Candidate): TransitionPlan | null {
  const { a, b, opts } = p
  const shape = shapeOf(c.kind, p.base)
  const outBar = c.anchor - shape.lead
  const outMs = barTime(a, outBar)
  if (outBar < 0 || outMs < a.startMs) return null
  const sync = c.kind === 'echo' ? false : p.syncOk
  const nA = a.bars.energy.length
  const overlapB = Math.max(1, Math.round(shape.bars * p.beatRatio))
  const energyA = mean(a.bars.energy, c.anchor - EDGE_BARS, c.anchor)
  const energyB = mean(b.bars.energy, c.entry, c.entry + EDGE_BARS)
  const midA = mean(a.bars.mid, outBar, c.anchor)
  const midB = mean(b.bars.mid, c.entry, c.entry + overlapB)
  const key = keyFor(p, c.kind, sync)
  const endAMs = barTime(a, c.anchor)
  const inMs = barTime(b, c.entry)
  const cutOutMs = Math.max(0, a.endMs - endAMs)
  const cutInMs = Math.max(0, inMs - b.startMs)
  const cutMs = opts.cutSec * 1000
  const phraseA =
    shape.inAtBar === 0
      ? (startScore(p.phrasesA, outBar) + endScore(p.phrasesA, nA, c.anchor)) / 2
      : endScore(p.phrasesA, nA, c.anchor)
  const facts: Facts = {
    syncOk: p.syncOk,
    clash: p.keySync.clash,
    calm: energyA < CALM && energyB < CALM,
    loud: energyA > LOUD,
    outroA: phraseAt(a, outBar) === 'outro',
    introB: c.entry === 0 || phraseAt(b, c.entry) === 'intro',
    dropB: p.phrasesB.get(c.entry) === 'drop',
    spectrumGap: Math.abs(mean(a.bars.low, outBar, c.anchor) - mean(b.bars.low, c.entry, c.entry + overlapB)) > SPECTRUM_GAP,
  }
  const parts: Record<ScorePart, number> = {
    tempo: p.tempoScore,
    key: key.term,
    energy: 1 - Math.abs(energyA - energyB),
    phrases: (phraseA + inScore(p.phrasesB, c.entry, c.kind)) / 2,
    cut: cutMs > 0 ? 1 - (cutOutMs + cutInMs) / (2 * cutMs) : 1,
    vocal: OVERLAP_KINDS.has(c.kind) ? 1 - clamp((Math.min(midA, midB) - VOCAL_FROM) * 2, 0, 1) : 1,
    fit: kindFit(c.kind, facts),
    rating: 1 + Math.min(0, clamp(opts.ratings?.[c.kind] ?? 0, -1, 1)),
  }
  const total = (Object.keys(WEIGHTS) as ScorePart[]).reduce((s, k) => s + WEIGHTS[k] * parts[k], 0)
  return {
    kind: c.kind,
    sync,
    bars: shape.bars,
    outMs: round(outMs, 1),
    endAMs: round(endAMs, 1),
    inMs: round(inMs, 1),
    inAtBar: shape.inAtBar,
    tempoA: round(p.tempoA, 2),
    tempoB: round(p.tempoB, 2),
    beatRatio: p.beatRatio,
    shift: key.match.shift,
    gainDb: p.gainDb,
    cutOutMs: Math.round(cutOutMs),
    cutInMs: Math.round(cutInMs),
    score: round(total / WEIGHT_SUM, 4),
    parts,
  }
}

const KIND_ORDER = new Map(BLEND_KINDS.map((k, i) => [k, i]))

function byScore(x: TransitionPlan, y: TransitionPlan): number {
  return (
    y.score - x.score ||
    (KIND_ORDER.get(x.kind) ?? 0) - (KIND_ORDER.get(y.kind) ?? 0) ||
    y.outMs - x.outMs ||
    x.inMs - y.inMs
  )
}

/** Лучшие варианты перехода A → B, лучший первым; пусто — свести нечем (обычный кроссфейд). */
export function plan(a: BlendAnalysis, b: BlendAnalysis, opts: PlanOpts): TransitionPlan[] {
  if (!(a.bpm > 0) || !(b.bpm > 0) || !(opts.rateA > 0) || !(opts.rateB > 0)) return []
  const p = pairOf(a, b, opts)
  const cutMs = Math.max(0, opts.cutSec) * 1000
  const anchors = anchorsOf(a, cutMs)
  const entries = entriesOf(b, cutMs)
  const seen = new Set<string>()
  const out: TransitionPlan[] = []
  for (const kind of kindsFor(opts.type, p.syncOk)) {
    for (const anchor of anchors) {
      for (const entry of entries) {
        const t = evaluate(p, { kind, anchor, entry })
        const id = t && `${t.kind}:${t.outMs}:${t.inMs}`
        if (!t || !id || seen.has(id)) continue
        seen.add(id)
        out.push(t)
      }
    }
  }
  return out.sort(byScore).slice(0, TOP_PLANS)
}
