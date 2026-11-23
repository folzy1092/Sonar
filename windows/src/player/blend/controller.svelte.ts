// Контроллер сведения (docs/BLEND.md §6): выбирает план, заранее грузит B во второй дек, раз в 50 мс ведёт
// кривые обеих цепочек, общий темп и фазу B, в нужный такт отдаёт B плееру («принять играющий дек», §6.5).
// Плеер знает о нём только через `BlendHost`, поэтому всё ядро гоняется в тестах на поддельных деках.

import type { BlendAnalysis } from './analysis'
import { type ChainLike, deckValues, freezeDeck, rampDeck, scheduleDeck, setDeck } from './automation'
import { type BlendCurves, curvesFor, tempoAt } from './curves'
import { barMs, type BlendKind, type BlendType, plan as planTransitions, type TransitionPlan } from './planner'

/** То, что контроллер трогает у `<audio>`. */
export interface MediaLike {
  currentTime: number
  playbackRate: number
  preservesPitch: boolean
  paused: boolean
  play(): Promise<void>
  pause(): void
}

export interface BlendDeck {
  el: MediaLike
  chain: ChainLike
}

/** Собственный звук трека («Для этого трека» или 1×). */
export interface OwnSound {
  rate: number
  pitch: number
  linked: boolean
}

export interface BlendSettings {
  type: BlendType
  lengthSec: number
  cutSec: number
  tempoTolPct: number
  keyShift: boolean
  /** Перевес 👍/👎 по видам за 60 дней (§8.6): «Авто» реже берёт вид с минусом. */
  ratings?: Partial<Record<BlendKind, number>>
}

/** Значения по умолчанию из §7.3; ключи `audio.blend_*` разбирает `settings.ts`. */
export const BLEND_DEFAULTS: BlendSettings = { type: 'auto', lengthSec: 10, cutSec: 16, tempoTolPct: 8, keyShift: true }

export interface BlendHost<T extends { ref: string }, D extends BlendDeck> {
  /** Время аудиоконтекста, с. */
  now(): number
  nyquist: number
  settings(): BlendSettings
  /** Готовый анализ или `null` (тогда попросить посчитать). */
  analysis(ref: string): BlendAnalysis | null
  sound(ref: string): Promise<OwnSound>
  /** Загрузить трек во второй дек на паузе с позиции `startSec`; `null` — не вышло. */
  load(track: T, startSec: number): Promise<D | null>
  /** B стал текущим без `load()`; он играет уже `listenedMs`. */
  promote(deck: D, listenedMs: number): void
  /** Дек больше не нужен: остановить элемент (цепочку не рвать — в ней может звенеть хвост эха). */
  release(deck: D): void
  /** Выравниватель громкости не трогает деки, пока идёт переход. */
  hold(on: boolean): void
}

export type BlendPhase = 'idle' | 'planned' | 'prerolling' | 'running' | 'promoting' | 'fallback'

export interface Consider<T, D> {
  a: T
  b: T | null
  deckA: D
  posMs: number
  durMs: number
  enabled: boolean
  /** Своя скорость A («Для этого трека») и связан ли с ней тон. */
  rateA: number
  linkedA: boolean
}

export const TICK_MS = 50
const HORIZON_SEC = 1
const PREROLL_SEC = 8
/** План годится, если до старта B ещё хотя бы столько. */
const MIN_LEAD_SEC = 1.5
const PLAY_LEAD_SEC = 0.15
/** На сколько тактов раньше входа B начинает играть молча (синк успевает сойтись). */
const LEAD_BARS = 2
/** «К переходу»: столько секунд A до начала перехода. */
const PREVIEW_SEC = 8
export const MIN_TRACK_MS = 60_000
const PHASE_OK_MS = 8
export const PHASE_SEEK_MS = 120
const CORR_MIN = 0.005
const CORR_MAX = 0.02
/** Ошибка фазы, при которой поправка скорости достигает потолка, мс. */
const CORR_FULL_MS = 1000
export const CANCEL_SEC = 0.3
const GAIN_SETTLE_SEC = 2
const SHIFT_SETTLE_BARS = 8
const A_REST_SEC = 1
const DIP_SEC = 0.01
const RATE_EPS = 1e-4
const NO_SOUND: OwnSound = { rate: 1, pitch: 0, linked: false }

const ratioOf = (semitones: number) => 2 ** (semitones / 12)
const clamp = (x: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, x))

interface Pair<T, D> {
  a: T
  b: T
  deckA: D
  anA: BlendAnalysis
  anB: BlendAnalysis
  key: string
  rateA: number
  soundB: OwnSound
  plan: TransitionPlan
  curves: BlendCurves
  gainMul: number
  /** С какого такта перехода играет B. */
  bStartBar: number
}

type PairBase<T, D> = Omit<Pair<T, D>, 'plan' | 'curves' | 'gainMul' | 'bStartBar'>

/** Запланированный переход для карточки «Следующий переход»: место плана в топе планировщика. */
export interface NextPlan<T> {
  from: T
  to: T
  plan: TransitionPlan
  /** 1…total. */
  rank: number
  total: number
}

const sameMoment = (x: TransitionPlan, y: TransitionPlan) => x.kind === y.kind && x.outMs === y.outMs && x.inMs === y.inMs

interface Live<D> {
  deckB: D | null
  bPlaying: boolean
  bStartedAt: number
  promoted: boolean
  aReleased: boolean
  bar: number
  lastNow: number
  /** Снятие сдвига тона после перехода: начало, с; `null` — ещё не снимаем. */
  settleFrom: number | null
  paused: boolean
  bWasPlaying: boolean
  dipUntil: number
}

export class BlendController<T extends { ref: string }, D extends BlendDeck> {
  phase = $state<BlendPhase>('idle')
  /** Что сейчас сводим (для кнопки и отладки). */
  current = $state.raw<{ from: T; to: T; plan: TransitionPlan } | null>(null)
  /** Что запланировано (до и во время перехода). */
  next = $state.raw<NextPlan<T> | null>(null)
  /** Последняя ошибка фазы, мс (отладка). */
  phaseErrMs = $state(0)
  /** Последний доведённый переход (B стал текущим) — его просят оценить 👍/👎. Новый объект на каждый переход. */
  done = $state.raw<{ from: T; to: T; kind: BlendKind } | null>(null)

  private pair: Pair<T, D> | null = null
  private live: Live<D> | null = null
  private preparing: string | null = null
  private failed = $state<string | null>(null)
  /** Топ планировщика для текущей пары (по нему ходит «Другой момент»). */
  private options: TransitionPlan[] = []
  /** Момент, выбранный «Другим моментом»: переживает перемотку и пересчёт пары. */
  private prefer: { pairKey: string; plan: TransitionPlan } | null = null
  private token = 0
  private timer: ReturnType<typeof setTimeout> | null = null
  /** Отложенные освобождения дек: новый преролл выполняет их сразу, чтобы старый таймер не убил свежий B. */
  private pending = new Set<{ run: () => void; timer: ReturnType<typeof setTimeout> }>()

  constructor(private readonly host: BlendHost<T, D>) {}

  /** Переход ведёт контроллер (плееру не надо делать кроссфейд)? Зовётся на каждом `timeupdate`. */
  consider(c: Consider<T, D>): boolean {
    if (this.started()) {
      // очередь поменяли, пока B ещё не текущий: B уже не следующий — переход гасим
      if (!this.live?.promoted && c.b?.ref !== this.pair?.b.ref) {
        this.cancel()
        return false
      }
      return true
    }
    if (!c.enabled || !c.b || c.durMs < MIN_TRACK_MS) return this.drop()
    const pairKey = `${c.a.ref}>${c.b.ref}`
    if (this.failed === pairKey) return false
    const key = `${pairKey}|${c.rateA}|${c.linkedA}|${JSON.stringify(this.host.settings())}`
    if ((this.pair && this.pair.key !== key) || (this.preparing && this.preparing !== key)) this.drop()
    if (this.preparing === key) return true
    if (!this.pair) return this.prepare(c, key, pairKey)
    if (this.phase === 'planned' && this.prerollDue(c.posMs)) this.preroll()
    return true
  }

  /** Пауза: деки и часы перехода стоят. */
  pause() {
    const live = this.live
    if (!live || live.paused || live.settleFrom !== null) return
    live.paused = true
    this.stopTimer()
    this.freeze(this.host.now())
    live.bWasPlaying = !!live.deckB && !live.promoted && !live.deckB.el.paused
    if (live.bWasPlaying) live.deckB!.el.pause()
  }

  resume() {
    const live = this.live
    if (!live?.paused) return
    live.paused = false
    live.lastNow = this.host.now()
    const deckB = live.deckB
    if (live.bWasPlaying && deckB) void deckB.el.play().catch(() => this.onDeckError(deckB.el))
    this.loop()
  }

  /** Перемотка, «Предыдущий», клик, новая очередь (§6.4). */
  cancel() {
    const { pair, live } = this
    if (!pair || !live) return this.reset()
    // переход уже свёрнут, идёт только снятие сдвига тона — B и так текущий, трогать нечего
    if (live.settleFrom !== null) return
    if (live.promoted) return this.wrapUp(CANCEL_SEC)
    const t = this.host.now()
    const deckB = live.deckB
    if (deckB) {
      rampDeck(deckB.chain, { gain: 0 }, t, CANCEL_SEC)
      this.later(CANCEL_SEC, () => this.host.release(deckB))
    }
    rampDeck(pair.deckA.chain, pair.curves.rest, t, CANCEL_SEC)
    setRate(pair.deckA.el, pair.rateA)
    this.reset()
  }

  /**
   * «Следующий» или конец A: B уже играет — он сразу текущий. `false` — листать как обычно: B не играет
   * или уже текущий (тогда «Следующий» — про трек после B, его `load()` зовёт `abort()`).
   */
  finishNow(): boolean {
    const live = this.live
    if (live?.promoted) return false
    if (!live?.bPlaying) {
      this.cancel()
      return false
    }
    this.promote()
    this.wrapUp(CANCEL_SEC)
    return true
  }

  /** Плеер грузит другой трек: переход бросить сразу, без хвостов (новый трек играет с чистой цепочки). */
  abort() {
    const { pair, live } = this
    if (!pair || !live?.promoted) return this.cancel()
    const t = this.host.now()
    this.releaseA(live, pair.deckA)
    setDeck(pair.deckA.chain, pair.curves.rest, t)
    const deckB = live.deckB!
    setDeck(deckB.chain, pair.curves.rest, t)
    void deckB.chain.setShift(1)
    this.reset()
  }

  /** Ошибка у одного из дек. `true` — разобрались сами, плееру молчать. */
  onDeckError(el: MediaLike): boolean {
    const { pair, live } = this
    if (!pair || !live) return false
    if (live.deckB?.el === el && !live.promoted) {
      this.failed = `${pair.a.ref}>${pair.b.ref}`
      this.cancel()
      return true
    }
    if (pair.deckA.el === el && live.promoted) {
      this.releaseA(live, pair.deckA)
      return true
    }
    return false
  }

  /** Переход уже звучит (дальше его не отменяет выключение сведения, §6.4). */
  started(): boolean {
    return this.phase === 'running' || this.phase === 'promoting'
  }

  private prepare(c: Consider<T, D>, key: string, pairKey: string): boolean {
    const b = c.b!
    const anA = this.host.analysis(c.a.ref)
    const anB = this.host.analysis(b.ref)
    if (!anA || !anB) return false
    this.preparing = key
    const token = this.token
    void this.host
      .sound(b.ref)
      .catch(() => NO_SOUND)
      .then((soundB) => {
        if (token !== this.token || this.preparing !== key) return
        this.preparing = null
        const pair = this.choose({ ...c, b }, key, anA, anB, soundB)
        this.setPair(pair)
        if (pair) this.phase = 'planned'
        else this.failed = pairKey
      })
    return true
  }

  /** Первый из топа, у которого старт B ещё впереди (§7.1), или момент, выбранный «Другим моментом». */
  private choose(c: Consider<T, D> & { b: T }, key: string, anA: BlendAnalysis, anB: BlendAnalysis, soundB: OwnSound) {
    const plans = planTransitions(anA, anB, {
      ...this.host.settings(),
      rateA: c.rateA,
      rateB: soundB.rate,
      linkedA: c.linkedA,
      linkedB: soundB.linked,
    })
    this.options = plans
    const fits = plans.filter((plan) => ahead(plan, anA, anB, c.posMs, c.rateA))
    const prefer = this.prefer
    const want = prefer?.pairKey === `${c.a.ref}>${c.b.ref}` ? fits.find((plan) => sameMoment(plan, prefer.plan)) : undefined
    const plan = want ?? fits[0]
    if (!plan) return null
    return this.build({ a: c.a, b: c.b, deckA: c.deckA, anA, anB, key, rateA: c.rateA, soundB }, plan)
  }

  private build(base: PairBase<T, D>, plan: TransitionPlan): Pair<T, D> {
    const { a, b, deckA, anA, anB, key, rateA, soundB } = base
    const curves = curvesFor(plan, this.host.nyquist)
    return { a, b, deckA, anA, anB, key, rateA, soundB, plan, curves, gainMul: 10 ** (plan.gainDb / 20), bStartBar: startBar(plan, anB) }
  }

  private setPair(pair: Pair<T, D> | null) {
    this.pair = pair
    this.next = pair && {
      from: pair.a,
      to: pair.b,
      plan: pair.plan,
      rank: this.options.indexOf(pair.plan) + 1,
      total: this.options.length,
    }
  }

  /** «Другой момент»: следующий план из топа (по кругу), у которого старт ещё впереди. Только до перехода. */
  another(): boolean {
    const p = this.pair
    if (!p || this.started()) return false
    const plans = this.options
    const posMs = p.deckA.el.currentTime * 1000
    const from = plans.indexOf(p.plan)
    for (let k = 1; k < plans.length; k++) {
      const plan = plans[(from + k) % plans.length]
      if (!ahead(plan, p.anA, p.anB, posMs, p.rateA)) continue
      this.prefer = { pairKey: `${p.a.ref}>${p.b.ref}`, plan }
      // B уже грузится под прежний момент — забыть пару, следующий `consider` соберёт её с новым
      if (this.live) this.drop()
      else this.setPair(this.build(p, plan))
      return true
    }
    return false
  }

  /** «К переходу»: куда перемотать A (мс файла), чтобы до старта B осталось 8 с. Синк запускает B на
   *  `LEAD_BARS` тактов раньше выхода — на медленном треке это дольше 8 с, считать от выхода нельзя. */
  previewAtMs(): number | null {
    const p = this.pair
    if (!p || this.started()) return null
    const startMs = p.plan.outMs + startBar(p.plan, p.anB) * barMs(p.anA)
    return Math.max(0, startMs - PREVIEW_SEC * 1000 * p.rateA)
  }

  /** Для пары не нашлось плана или B не загрузился — будет кроссфейд. */
  failedFor(a: string, b: string): boolean {
    return this.failed === `${a}>${b}`
  }

  private prerollDue(posMs: number): boolean {
    const p = this.pair!
    return posMs >= p.plan.outMs + p.bStartBar * barMs(p.anA) - PREROLL_SEC * 1000 * p.rateA
  }

  private preroll() {
    const p = this.pair!
    this.flush()
    this.phase = 'prerolling'
    this.current = { from: p.a, to: p.b, plan: p.plan }
    this.live = {
      deckB: null,
      bPlaying: false,
      bStartedAt: 0,
      promoted: false,
      aReleased: false,
      bar: this.barOfA(),
      lastNow: this.host.now(),
      settleFrom: null,
      paused: false,
      bWasPlaying: false,
      dipUntil: 0,
    }
    this.host.hold(true)
    const token = this.token
    void this.host.load(p.b, expectedB(p.plan, p.anB, p.bStartBar) / 1000).then(
      (deck) => this.loaded(token, deck),
      () => this.loaded(token, null),
    )
    this.loop()
  }

  private loaded(token: number, deck: D | null) {
    const p = this.pair
    const live = this.live
    if (token !== this.token || !p || !live) {
      if (deck) this.host.release(deck)
      return
    }
    if (!deck || live.bar > p.bStartBar) {
      // не успел к старту — обычный кроссфейд (§6.2)
      if (deck) this.host.release(deck)
      this.failed = `${p.a.ref}>${p.b.ref}`
      this.reset()
      this.phase = 'fallback'
      return
    }
    live.deckB = deck
    const t = this.host.now()
    setDeck(deck.chain, deckValues(p.curves, 'b', p.bStartBar, p.gainMul), t)
    deck.el.preservesPitch = !p.soundB.linked
    setRate(deck.el, this.rateB(Math.max(0, p.bStartBar)))
    void deck.chain.setUserPitch(p.soundB.linked ? 1 : ratioOf(p.soundB.pitch))
    void deck.chain.setShift(ratioOf(p.plan.shift))
    p.deckA.chain.delay.delayTime.setValueAtTime(p.curves.echoDelaySec, t)
  }

  private loop() {
    this.stopTimer()
    this.timer = setTimeout(() => {
      this.timer = null
      this.tick()
      if (this.live && !this.live.paused) this.loop()
    }, TICK_MS)
  }

  private stopTimer() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
  }

  private tick() {
    const { pair: p, live } = this
    if (!p || !live) return
    const now = this.host.now()
    if (live.settleFrom !== null) return this.settle(now)
    const secPerBar = this.advance(now)
    if (!live.promoted) this.syncA(live.bar)
    const deckB = live.deckB
    if (!deckB) return
    if (!live.bPlaying && (p.bStartBar - live.bar) * secPerBar <= PLAY_LEAD_SEC) this.startB(deckB)
    if (live.bPlaying && this.phase === 'prerolling' && live.bar >= Math.min(0, p.bStartBar)) this.phase = 'running'
    if (live.bPlaying && !live.promoted) this.syncB(deckB, now)
    this.schedule(now, secPerBar)
    if (live.bPlaying && !live.promoted && live.bar >= p.curves.promoteBar) this.promote()
    if (live.promoted && live.bar >= p.curves.endBar) this.wrapUp(A_REST_SEC)
  }

  /** Такт перехода сейчас и секунд на такт: до промоута — по позиции A, после — по часам. */
  private advance(now: number): number {
    const p = this.pair!
    const live = this.live!
    if (!live.promoted) {
      live.bar = this.barOfA()
      live.lastNow = now
      return barMs(p.anA) / 1000 / (p.deckA.el.playbackRate || 1)
    }
    const secPerBar = 240 / (tempoAt(p.plan, live.bar) ?? p.plan.tempoA)
    live.bar += (now - live.lastNow) / secPerBar
    live.lastNow = now
    return secPerBar
  }

  private barOfA(): number {
    const p = this.pair!
    return (p.deckA.el.currentTime * 1000 - p.plan.outMs) / barMs(p.anA)
  }

  private syncA(bar: number) {
    const p = this.pair!
    const tempo = tempoAt(p.plan, bar)
    if (tempo !== null) setRate(p.deckA.el, tempo / p.anA.bpm)
  }

  /** Своя скорость B на такте: с синком — общий темп в его сетке, без — собственная. */
  private rateB(bar: number): number {
    const p = this.pair!
    const tempo = tempoAt(p.plan, bar)
    return tempo === null ? p.soundB.rate : (tempo * p.plan.beatRatio) / p.anB.bpm
  }

  /** B стартует чуть раньше своего такта, сразу с позиции под текущий такт; до начала файла — ждём тик. */
  private startB(deck: D) {
    const p = this.pair!
    const live = this.live!
    const atMs = expectedB(p.plan, p.anB, live.bar)
    if (atMs < 0) return
    deck.el.currentTime = atMs / 1000
    live.bPlaying = true
    live.bStartedAt = this.host.now()
    void deck.el.play().catch(() => this.onDeckError(deck.el))
  }

  /** Фаза B к сетке A (§6.3): мелкая ошибка — поправка скорости, большая — перемотка за 10 мс тишины. */
  private syncB(deck: D, now: number) {
    const p = this.pair!
    const live = this.live!
    const base = this.rateB(live.bar)
    if (!p.plan.sync) return setRate(deck.el, base)
    const wantMs = expectedB(p.plan, p.anB, live.bar)
    const errMs = (deck.el.currentTime * 1000 - wantMs) / (deck.el.playbackRate || 1)
    this.phaseErrMs = errMs
    if (Math.abs(errMs) > PHASE_SEEK_MS && wantMs >= 0) {
      rampDeck(deck.chain, { gain: 0 }, now, DIP_SEC)
      deck.el.currentTime = (wantMs + base * DIP_SEC * 1000) / 1000
      live.dipUntil = now + 2 * DIP_SEC
      return setRate(deck.el, base)
    }
    if (Math.abs(errMs) <= PHASE_OK_MS) return setRate(deck.el, base)
    const corr = clamp(errMs / CORR_FULL_MS, -CORR_MAX, CORR_MAX)
    setRate(deck.el, base * (1 - Math.sign(corr) * Math.max(CORR_MIN, Math.abs(corr))))
  }

  private schedule(now: number, secPerBar: number) {
    const p = this.pair!
    const live = this.live!
    const span = { bar: live.bar, t0: now, secPerBar, horizonSec: HORIZON_SEC }
    if (!live.aReleased && live.bar + HORIZON_SEC / secPerBar >= 0) scheduleDeck(p.deckA.chain, p.curves, 'a', span)
    if (live.deckB && now >= live.dipUntil) scheduleDeck(live.deckB.chain, p.curves, 'b', span, p.gainMul)
  }

  /** B стал текущим: плеер принимает играющий дек; A догорает по кривой и через 300 мс освобождается. */
  private promote() {
    const live = this.live!
    const deckA = this.pair!.deckA
    live.promoted = true
    this.phase = 'promoting'
    this.done = { from: this.pair!.a, to: this.pair!.b, kind: this.pair!.plan.kind }
    this.host.promote(live.deckB!, (this.host.now() - live.bStartedAt) * 1000)
    this.later(CANCEL_SEC, () => this.releaseA(live, deckA))
  }

  private releaseA(live: Live<D>, deckA: D) {
    if (live.aReleased) return
    live.aReleased = true
    this.host.release(deckA)
  }

  /** Конец автоматизации: цепочки в нейтраль, скорость B — своя, громкость B → 1, дальше снимаем сдвиг тона. */
  private wrapUp(sec: number) {
    const p = this.pair!
    const live = this.live!
    const deckB = live.deckB!
    const t = this.host.now()
    rampDeck(p.deckA.chain, { gain: 0 }, t, sec)
    this.later(sec, () => {
      this.releaseA(live, p.deckA)
      setDeck(p.deckA.chain, p.curves.rest, this.host.now())
    })
    rampDeck(deckB.chain, { ...p.curves.rest, gain: p.gainMul }, t, sec)
    deckB.chain.gain.gain.linearRampToValueAtTime(1, t + sec + GAIN_SETTLE_SEC)
    setRate(deckB.el, p.soundB.rate)
    this.host.hold(false)
    live.settleFrom = t
    live.paused = false
    if (!this.timer) this.loop()
  }

  /** Сдвиг тона B уходит в 0 плавно за 8 тактов (§6.3). */
  private settle(now: number) {
    const p = this.pair!
    const live = this.live!
    const sec = (SHIFT_SETTLE_BARS * 240) / p.plan.tempoB
    const x = p.plan.shift ? (now - live.settleFrom!) / sec : 1
    void live.deckB!.chain.setShift(x >= 1 ? 1 : ratioOf(p.plan.shift * (1 - x)))
    if (x >= 1) this.reset()
  }

  private later(sec: number, run: () => void) {
    const job = { run, timer: setTimeout(() => this.runJob(job), sec * 1000) }
    this.pending.add(job)
  }

  private runJob(job: { run: () => void; timer: ReturnType<typeof setTimeout> }) {
    if (!this.pending.delete(job)) return
    clearTimeout(job.timer)
    job.run()
  }

  private flush() {
    for (const job of [...this.pending]) this.runJob(job)
  }

  private freeze(t: number) {
    const p = this.pair!
    const live = this.live!
    if (!live.aReleased) freezeDeck(p.deckA.chain, p.curves, 'a', live.bar, t)
    if (live.deckB) freezeDeck(live.deckB.chain, p.curves, 'b', live.bar, t, p.gainMul)
  }

  /** Тихо забыть план, пока переход не начался (сведение выключили, сменились настройки или пара). */
  private drop(): false {
    if (this.live?.deckB) this.host.release(this.live.deckB)
    this.reset()
    return false
  }

  private reset() {
    const held = !!this.live && this.live.settleFrom === null
    this.token++
    this.stopTimer()
    this.setPair(null)
    this.live = null
    this.preparing = null
    this.current = null
    this.phase = 'idle'
    this.phaseErrMs = 0
    if (held) this.host.hold(false)
  }
}

function setRate(el: MediaLike, rate: number) {
  if (Math.abs(el.playbackRate - rate) > RATE_EPS) el.playbackRate = rate
}

/** Старт B ещё хотя бы за `MIN_LEAD_SEC` от позиции A. */
function ahead(plan: TransitionPlan, anA: BlendAnalysis, anB: BlendAnalysis, posMs: number, rateA: number): boolean {
  const startMs = plan.outMs + startBar(plan, anB) * barMs(anA)
  return startMs - posMs >= MIN_LEAD_SEC * 1000 * rateA
}

/** Где должен быть B (мс файла) на такте перехода. */
export function expectedB(plan: TransitionPlan, anB: BlendAnalysis, bar: number): number {
  return plan.inMs + (bar - plan.inAtBar) * plan.beatRatio * barMs(anB)
}

/** Такт, с которого играет B: у синка — за 2 такта до входа (но не раньше начала файла), у «Эха» — на входе. */
export function startBar(plan: TransitionPlan, anB: BlendAnalysis): number {
  if (!plan.sync) return plan.inAtBar
  const fromFileStart = plan.inAtBar - plan.inMs / (plan.beatRatio * barMs(anB))
  return Math.max(plan.inAtBar - LEAD_BARS, fromFileStart)
}
