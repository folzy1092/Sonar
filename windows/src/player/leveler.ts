// Нормализация громкости (Настройки → Плеер → Аудио): треки SoundCloud и Яндекса сведены очень
// по-разному — тихий лоу-фай после громкого фонка приходится докручивать руками. Выравниватель
// слушает сигнал после эквалайзера, держит медленную оценку громкости (RMS в дБ, тишину не считает)
// и плавно подводит усиление к общей цели. Не компрессор: внутри трека динамика не трогается —
// оценка меняется медленно (≈ 6 с), только первые секунды нового трека — быстрее.

/** Цель — средняя громкость RMS, дБFS (≈ −14 LUFS у обычной музыки). */
export const TARGET_DB = -18
/** Тише не делаем больше, чем на 9 дБ, громче — больше, чем на 6 (тихие записи не раздуваем шумом). */
export const MIN_GAIN_DB = -9
export const MAX_GAIN_DB = 6
/** Тише этого — пауза или затухание, в оценку не идёт. */
export const SILENCE_DB = -55

/** Усиление в дБ для оценки громкости `levelDb`. */
export function gainFor(levelDb: number): number {
  return Math.max(MIN_GAIN_DB, Math.min(MAX_GAIN_DB, TARGET_DB - levelDb))
}

/** Сглаживание оценки: за `dtMs` к новому замеру с постоянной времени `tauMs`. */
export function smooth(prev: number, sample: number, dtMs: number, tauMs: number): number {
  const k = 1 - Math.exp(-dtMs / tauMs)
  return prev + (sample - prev) * k
}

/** RMS кадра в дБFS. */
export function rmsDb(frame: Float32Array): number {
  let sum = 0
  for (let i = 0; i < frame.length; i++) sum += frame[i] * frame[i]
  const rms = Math.sqrt(sum / Math.max(1, frame.length))
  return rms > 0 ? 20 * Math.log10(rms) : -Infinity
}

const STEP_MS = 200
const FAST_MS = 1_500
const SLOW_MS = 6_000
const FAST_FOR_MS = 4_000

export class Leveler {
  /** Узел усиления в цепочке: эквалайзер → он → анализатор волны → выход. */
  readonly node: GainNode
  private pre: GainNode
  private meter: AnalyserNode
  private frame: Float32Array<ArrayBuffer>
  private level: number | null = null
  private since = 0
  private timer: ReturnType<typeof setInterval> | null = null
  private on = false

  constructor(private ctx: AudioContext) {
    this.node = ctx.createGain()
    this.pre = ctx.createGain()
    this.meter = ctx.createAnalyser()
    this.meter.fftSize = 2048
    this.frame = new Float32Array(this.meter.fftSize)
    // замер — до усиления (иначе выравниватель гонялся бы за собственным хвостом): вход раздваивается
    this.pre.connect(this.node)
    this.pre.connect(this.meter)
  }

  /** Вход: сюда приходит сигнал после эквалайзера; выход — `node`. */
  get input(): AudioNode {
    return this.pre
  }

  setEnabled(on: boolean) {
    this.on = on
    if (on && !this.timer) this.timer = setInterval(() => this.step(), STEP_MS)
    if (!on) {
      if (this.timer) clearInterval(this.timer)
      this.timer = null
      this.node.gain.setTargetAtTime(1, this.ctx.currentTime, 0.4)
    }
  }

  /** Новый трек — первые секунды оценка догоняет быстрее. */
  trackChanged() {
    this.since = performance.now()
  }

  private step() {
    if (!this.on || this.ctx.state !== 'running') return
    this.meter.getFloatTimeDomainData(this.frame)
    const db = rmsDb(this.frame)
    if (!Number.isFinite(db) || db < SILENCE_DB) return
    const fast = performance.now() - this.since < FAST_FOR_MS
    this.level = this.level === null ? db : smooth(this.level, db, STEP_MS, fast ? FAST_MS : SLOW_MS)
    const gain = 10 ** (gainFor(this.level) / 20)
    this.node.gain.setTargetAtTime(gain, this.ctx.currentTime, fast ? 0.3 : 1.2)
  }
}
