// Порядок «Свести для вечеринки» (docs/BLEND.md §9): старт — случайный из первых 10, дальше из пула
// в 8 случайных треков выбирается лучший по плану перехода и по дуге энергии. Первые 20 минут
// энергия растёт, потом держится с короткими провалами раз в 5–6 треков. Чистый модуль —
// обвязка с плеером и анализом в `party.svelte.ts`.

import type { BlendAnalysis } from './analysis'

export const PARTY_PREFIX = 'party:'
/** Сколько первых треков плейлиста годятся в старт. */
export const PARTY_START_FROM = 10
/** Сколько живых (не сбойных) кандидатов держим в пуле и считаем заранее. */
export const PARTY_POOL = 8
/** Разгон: столько энергия только растёт. */
export const WARMUP_MS = 20 * 60_000

/** На сколько выше текущей целимся в разгон. */
const RISE = 0.08
/** Глубина провала после разгона. */
const DIP = 0.18
/** Провал — на 5-м треке после прошлого, следующий — на 6-м, и так по очереди. */
const DIP_EVERY = [5, 6] as const
/** На таком отличии от цели попадание в дугу — ноль. */
const FIT_SPAN = 0.4
const W_PLAN = 0.6
const W_ARC = 0.4

export const partyContext = (base: string) => PARTY_PREFIX + base
export const isPartyContext = (ctx: string | null | undefined): ctx is string => !!ctx?.startsWith(PARTY_PREFIX)
export const partyBase = (ctx: string) => ctx.slice(PARTY_PREFIX.length)

const clamp01 = (x: number) => Math.min(1, Math.max(0, x))

/** Темп в окно 85…170: половинный и двойной — одно и то же для танцпола. */
function foldBpm(bpm: number): number {
  let b = bpm > 0 ? bpm : 120
  while (b < 85) b *= 2
  while (b >= 170) b /= 2
  return b
}

/** Энергия трека 0…1 для сравнения между треками: громкость (~LUFS) и темп. */
export function trackEnergy(a: BlendAnalysis): number {
  return 0.6 * clamp01((a.loudness + 18) / 12) + 0.4 * clamp01((foldBpm(a.bpm) - 85) / 85)
}

export interface ArcState {
  elapsedMs: number
  /** Треков после разгона с прошлого провала. */
  sinceDip: number
  dips: number
  /** Самая высокая энергия за вечер. */
  peak: number
}

/** Куда вести энергию следующим треком. */
export function arcTarget(s: ArcState, current: number): { target: number; dip: boolean } {
  if (s.elapsedMs < WARMUP_MS) return { target: Math.min(1, current + RISE), dip: false }
  if (s.sinceDip >= DIP_EVERY[s.dips % 2] - 1) return { target: Math.max(0, current - DIP), dip: true }
  return { target: Math.max(current, s.peak), dip: false }
}

const arcFit = (energy: number, target: number) => 1 - Math.min(1, Math.abs(energy - target) / FIT_SPAN)

export interface PartyLook {
  /** Готовый анализ или null — ещё считается / сбой. */
  analysis: BlendAnalysis | null
  failed: boolean
}

export class PartyOrder {
  readonly first: string
  #pool: readonly string[] = []
  #rest: readonly string[]
  #rnd: () => number
  #sinceDip = 0
  #dips = 0
  #peak = 0
  #last: number | null = null

  constructor(refs: readonly string[], rnd: () => number = Math.random) {
    const all = [...new Set(refs)]
    this.#rnd = rnd
    this.first = all[Math.floor(rnd() * Math.min(PARTY_START_FROM, all.length))] ?? ''
    this.#rest = all.filter((r) => r !== this.first)
    this.refill(() => false)
  }

  get pool(): readonly string[] {
    return this.#pool
  }

  /** Все сыграны. */
  get done(): boolean {
    return this.#pool.length === 0 && this.#rest.length === 0
  }

  /** Добирает пул случайными до 8 живых; возвращает новых — их отдают на анализ. */
  refill(isFailed: (ref: string) => boolean): string[] {
    const added: string[] = []
    let alive = this.#pool.filter((r) => !isFailed(r)).length
    while (alive < PARTY_POOL && this.#rest.length > 0) {
      const i = Math.floor(this.#rnd() * this.#rest.length)
      const ref = this.#rest[i]
      this.#rest = [...this.#rest.slice(0, i), ...this.#rest.slice(i + 1)]
      added.push(ref)
      alive++
    }
    this.#pool = [...this.#pool, ...added]
    return added
  }

  /**
   * Лучший следующий, ничего не меняет. Готовые — по плану перехода и дуге; готовых нет — первый
   * ещё считающийся (заиграет кроссфейдом); сбойные — в самый конец. null — играть нечего.
   */
  suggest(elapsedMs: number, look: (ref: string) => PartyLook, planScore: (next: BlendAnalysis) => number): string | null {
    if (this.#pool.length === 0) return null
    const looks = this.#pool.map((ref) => ({ ref, ...look(ref) }))
    const ready = looks.flatMap((l) => (l.analysis ? [{ ref: l.ref, analysis: l.analysis }] : []))
    if (ready.length === 0) return (looks.find((l) => !l.failed) ?? looks[0]).ref
    const { target } = arcTarget(this.#arc(elapsedMs), this.#last ?? trackEnergy(ready[0].analysis))
    const score = (a: BlendAnalysis) => W_PLAN * planScore(a) + W_ARC * arcFit(trackEnergy(a), target)
    return ready.reduce((best, c) => (score(c.analysis) > score(best.analysis) ? c : best)).ref
  }

  /** Трек заиграл: убрать из пула и сдвинуть дугу. energy — null, если анализа нет. */
  commit(ref: string, energy: number | null, elapsedMs: number): void {
    this.#pool = this.#pool.filter((r) => r !== ref)
    this.#rest = this.#rest.filter((r) => r !== ref)
    const hold = elapsedMs >= WARMUP_MS
    if (energy === null) {
      if (hold) this.#sinceDip++
      return
    }
    const wasDip = hold && this.#last !== null && arcTarget(this.#arc(elapsedMs), this.#last).dip
    if (wasDip && energy < this.#last! - DIP / 2) {
      this.#dips++
      this.#sinceDip = 0
    } else if (hold) this.#sinceDip++
    this.#peak = Math.max(this.#peak, energy)
    this.#last = energy
  }

  #arc(elapsedMs: number): ArcState {
    return { elapsedMs, sinceDip: this.#sinceDip, dips: this.#dips, peak: this.#peak }
  }
}
