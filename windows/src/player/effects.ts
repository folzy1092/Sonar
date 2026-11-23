// Звуковые эффекты меню скорости: сдвиг тона без смены темпа и реверб.
//
// Тон (сам узел живёт в цепочке дека — `blend/deck-chain.ts`): AudioWorklet с классическим сдвигом на двух линиях задержки — читающая головка едет
// быстрее или медленнее пишущей, две головки со сдвигом в полпериода плавно сменяют друг друга
// (окно sin², сумма весов всегда 1). Темп при этом держит сам <audio> (`preservesPitch`).
// Реверб: свёртка с синтезированным откликом зала (шум с экспоненциальным спадом, стерео
// раздельно), сухой и мокрый сигналы смешиваются по ползунку 0–100 %.

export const PITCH_WORKLET = `
class SonarPitch extends AudioWorkletProcessor {
  static get parameterDescriptors() { return [{ name: 'ratio', defaultValue: 1, minValue: 0.25, maxValue: 4 }] }
  constructor() {
    super()
    this.n = 2048
    this.size = 4096
    this.mask = this.size - 1
    this.buf = [new Float32Array(this.size), new Float32Array(this.size)]
    this.w = 0
    this.phase = 0
  }
  read(b, pos) {
    const i = Math.floor(pos)
    const f = pos - i
    return b[i & this.mask] * (1 - f) + b[(i + 1) & this.mask] * f
  }
  process(inputs, outputs, params) {
    const inp = inputs[0]
    const out = outputs[0]
    if (!inp || !inp.length) return true
    const ratio = params.ratio[0]
    const step = (1 - ratio) / this.n
    const len = out[0].length
    for (let i = 0; i < len; i++) {
      for (let c = 0; c < out.length; c++) this.buf[c & 1][this.w] = (inp[c] || inp[0])[i]
      this.phase += step
      this.phase -= Math.floor(this.phase)
      const p1 = this.phase
      const p2 = (p1 + 0.5) % 1
      const g1 = Math.sin(Math.PI * p1) ** 2
      const g2 = 1 - g1
      const r1 = this.w + this.size - p1 * this.n
      const r2 = this.w + this.size - p2 * this.n
      for (let c = 0; c < out.length; c++) {
        const b = this.buf[c & 1]
        out[c][i] = this.read(b, r1) * g1 + this.read(b, r2) * g2
      }
      this.w = (this.w + 1) & this.mask
    }
    return true
  }
}
registerProcessor('sonar-pitch', SonarPitch)
`

/** Отклик зала: стерео шум со спадом `seconds`, каналы независимы (ширина). */
function impulse(ctx: AudioContext, seconds = 2.6, decay = 3.2): AudioBuffer {
  const len = Math.floor(ctx.sampleRate * seconds)
  const ir = ctx.createBuffer(2, len, ctx.sampleRate)
  const pre = Math.floor(ctx.sampleRate * 0.012)
  for (let c = 0; c < 2; c++) {
    const d = ir.getChannelData(c)
    let lp = 0
    for (let i = pre; i < len; i++) {
      const t = (i - pre) / (len - pre)
      // мягкий фильтр: хвост темнеет, как в настоящем зале
      lp += (Math.random() * 2 - 1 - lp) * (0.6 - 0.45 * t)
      d[i] = lp * Math.pow(1 - t, decay)
    }
  }
  return ir
}

/** Модуль `sonar-pitch` грузится в контекст один раз; узлы из него создают цепочки деков. */
const pitchModules = new WeakMap<BaseAudioContext, Promise<void>>()

export function loadPitchModule(ctx: BaseAudioContext): Promise<void> {
  let p = pitchModules.get(ctx)
  if (!p) {
    p = (async () => {
      const url = URL.createObjectURL(new Blob([PITCH_WORKLET], { type: 'application/javascript' }))
      try {
        await ctx.audioWorklet.addModule(url)
      } finally {
        URL.revokeObjectURL(url)
      }
    })()
    pitchModules.set(ctx, p)
    p.catch(() => pitchModules.delete(ctx))
  }
  return p
}

/** Общий реверб после микса (тон — у каждого дека свой). */
export class Effects {
  readonly input: GainNode
  readonly output: GainNode
  private dry: GainNode
  private wet: GainNode
  private conv: ConvolverNode | null = null

  constructor(private ctx: AudioContext) {
    this.input = ctx.createGain()
    this.dry = ctx.createGain()
    this.wet = ctx.createGain()
    this.output = ctx.createGain()
    this.wet.gain.value = 0
    this.input.connect(this.dry)
    this.dry.connect(this.output)
    this.wet.connect(this.output)
  }

  /** Реверб 0…1: мокрый сигнал растёт, сухой чуть уходит, общая громкость почти не меняется. */
  setReverb(amount: number) {
    const a = Math.min(1, Math.max(0, amount))
    if (a > 0 && !this.conv) {
      this.conv = this.ctx.createConvolver()
      this.conv.buffer = impulse(this.ctx)
      this.input.connect(this.conv)
      this.conv.connect(this.wet)
    }
    const t = this.ctx.currentTime
    this.wet.gain.setTargetAtTime(a * 0.85, t, 0.08)
    this.dry.gain.setTargetAtTime(1 - a * 0.4, t, 0.08)
  }
}
