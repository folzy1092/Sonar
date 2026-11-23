// Своя цепочка звука у каждого дека (docs/BLEND.md §3):
//
//   gain → low → mid → high → hp → lp ─┬──────────────────────────→ post → (тон) → output
//                                      └→ echoSend → delay ─┬→ post
//                                                  ↑         └→ echoHp → feedback ┐
//                                                  └──────────────────────────────┘
//
// В покое каждый узел нейтрален и стоит в цепочке всегда (переподключение на ходу щёлкает):
// полосы изолятора 0 дБ, hp на 10 Гц, lp на Найквисте, эхо без посыла. Тон — исключение: при
// тоне 1 и без сдвига перехода worklet отключён (экономия CPU), включение и выключение идут
// перекрытием громкости 30 мс. Тон пользователя живёт здесь, а не после микса: во время перехода
// у каждого трека свой.

import { loadPitchModule } from '../effects'

export const LOW_HZ = 180
export const MID_HZ = 1000
export const MID_Q = 0.7
export const HIGH_HZ = 3200
/** Пределы полосы изолятора: −40 дБ — полоса выключена. */
export const ISO_MIN_DB = -40
export const ISO_MAX_DB = 6
/** hp в покое — ниже слышимого; lp в покое стоит на Найквисте, где он по спецификации Web Audio
 *  пропускает всё без изменений. */
export const HP_REST_HZ = 10
export const ECHO_HP_HZ = 300
export const ECHO_MAX_SEC = 4
/** Перекрытие при включении и выключении тона. */
export const PITCH_XFADE_SEC = 0.03
/** Самый короткий ход параметра — короче щёлкает. */
export const MIN_RAMP_SEC = 0.005
/** Отличие от 1, меньше которого тон считаем выключенным. */
const PITCH_EPS = 0.001
/** Плавность хода тона, как было в меню скорости. */
const PITCH_GLIDE_SEC = 0.05

export type Band = 'low' | 'mid' | 'high'

/** Уровень полосы изолятора в допустимых пределах. */
export function clampIso(db: number): number {
  if (!Number.isFinite(db)) return 0
  return Math.min(ISO_MAX_DB, Math.max(ISO_MIN_DB, db))
}

/** Итоговый множитель частоты: тон пользователя × сдвиг перехода. */
export function pitchRatioOf(user: number, shift: number): number {
  const r = user * shift
  return Number.isFinite(r) && r > 0 ? r : 1
}

/** Нужен ли worklet тона для такого множителя. */
export function pitchWanted(ratio: number): boolean {
  return Math.abs(ratio - 1) > PITCH_EPS
}

/** Плавный ход параметра от текущего значения (без скачка, не короче 5 мс). */
export function ramp(p: AudioParam, v: number, t: number, sec: number) {
  p.cancelScheduledValues(t)
  p.setValueAtTime(p.value, t)
  p.linearRampToValueAtTime(v, t + Math.max(MIN_RAMP_SEC, sec))
}

export class DeckChain {
  /** Вход цепочки — громкость дека (кроссфейд, переход, выравнивание громкости перехода). */
  readonly gain: GainNode
  readonly bands: Record<Band, BiquadFilterNode>
  readonly hp: BiquadFilterNode
  readonly lp: BiquadFilterNode
  readonly echoSend: GainNode
  readonly delay: DelayNode
  readonly feedback: GainNode
  readonly output: GainNode
  private post: GainNode
  private direct: GainNode
  private pitchGain: GainNode
  private pitch: AudioWorkletNode | null = null
  private pitched = false
  private user = 1
  private shift = 1
  /** Номер последнего переключения тона: старый таймер отключения не трогает новое включение. */
  private pitchGen = 0

  constructor(private ctx: BaseAudioContext) {
    this.gain = ctx.createGain()
    this.bands = {
      low: biquad(ctx, 'lowshelf', LOW_HZ),
      mid: biquad(ctx, 'peaking', MID_HZ, MID_Q),
      high: biquad(ctx, 'highshelf', HIGH_HZ),
    }
    this.hp = biquad(ctx, 'highpass', HP_REST_HZ, Math.SQRT1_2)
    this.lp = biquad(ctx, 'lowpass', lpRest(ctx), Math.SQRT1_2)
    this.echoSend = ctx.createGain()
    this.echoSend.gain.value = 0
    this.delay = ctx.createDelay(ECHO_MAX_SEC)
    this.delay.delayTime.value = 0.5
    const echoHp = biquad(ctx, 'highpass', ECHO_HP_HZ, Math.SQRT1_2)
    this.feedback = ctx.createGain()
    this.feedback.gain.value = 0
    this.post = ctx.createGain()
    this.direct = ctx.createGain()
    this.pitchGain = ctx.createGain()
    this.pitchGain.gain.value = 0
    this.output = ctx.createGain()

    this.gain.connect(this.bands.low)
    this.bands.low.connect(this.bands.mid)
    this.bands.mid.connect(this.bands.high)
    this.bands.high.connect(this.hp)
    this.hp.connect(this.lp)
    this.lp.connect(this.post)
    this.lp.connect(this.echoSend)
    this.echoSend.connect(this.delay)
    this.delay.connect(this.post)
    this.delay.connect(echoHp)
    echoHp.connect(this.feedback)
    this.feedback.connect(this.delay)
    this.post.connect(this.direct)
    this.direct.connect(this.output)
    this.pitchGain.connect(this.output)
  }

  /** Тон пользователя для трека этого дека (множитель частоты, 1 — без сдвига). */
  setUserPitch(ratio: number): Promise<void> {
    this.user = ratio
    return this.applyPitch()
  }

  /** Сдвиг тона на время перехода (1 — нет сдвига). */
  setShift(ratio: number): Promise<void> {
    this.shift = ratio
    return this.applyPitch()
  }

  private async applyPitch() {
    if (pitchWanted(pitchRatioOf(this.user, this.shift)) && !this.pitch) {
      try {
        await loadPitchModule(this.ctx)
        this.pitch ??= new AudioWorkletNode(this.ctx, 'sonar-pitch', { outputChannelCount: [2] })
      } catch {
        return // нет AudioWorklet — тон не трогаем, звук идёт как есть
      }
    }
    // за время загрузки значения могли смениться — берём последние
    const ratio = pitchRatioOf(this.user, this.shift)
    const want = pitchWanted(ratio)
    const p = this.pitch
    if (!p) return
    const t = this.ctx.currentTime
    p.parameters.get('ratio')?.setTargetAtTime(ratio, t, PITCH_GLIDE_SEC)
    if (want === this.pitched) return
    this.pitched = want
    const gen = ++this.pitchGen
    if (want) this.post.connect(p).connect(this.pitchGain)
    ramp(this.direct.gain, want ? 0 : 1, t, PITCH_XFADE_SEC)
    ramp(this.pitchGain.gain, want ? 1 : 0, t, PITCH_XFADE_SEC)
    if (want) return
    setTimeout(() => {
      if (gen !== this.pitchGen || this.pitched) return
      try {
        this.post.disconnect(p)
        p.disconnect()
      } catch {
        // уже отключён
      }
    }, PITCH_XFADE_SEC * 2000)
  }
}

function biquad(ctx: BaseAudioContext, type: BiquadFilterType, hz: number, q?: number): BiquadFilterNode {
  const f = ctx.createBiquadFilter()
  f.type = type
  f.frequency.value = hz
  f.gain.value = 0
  if (q !== undefined) f.Q.value = q
  return f
}

/** lp в покое — Найквист: фильтр прозрачен. */
export function lpRest(ctx: BaseAudioContext): number {
  return ctx.sampleRate / 2
}
