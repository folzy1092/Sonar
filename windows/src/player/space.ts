// Пространство 1D–16D (docs/SPACE_SHARE_PROMPT.md §2, docs/SETTINGS.md «Пространство»): звук плавно кружит
// вокруг головы, чем больше D — тем шире, глубже и «живее» движение. Не 16 разных режимов, а одна таблица
// опорных точек (1 · 2 · 3 · 8 · 12 · 16), промежуточные D — линейно между ними. Та же таблица и тот же
// алгоритм — на iPhone (`ios/Sonar/Playback/Space.swift`): **менять в обоих местах**, чтобы звучало одинаково.
//
// Как звучит: середина (L+R)/2 ставится в точку на орбите — разница уровней ушей (ILD, равная мощность),
// задержка дальнего уха до 0.66 мс (ITD, дробная), «тень головы» — дальнее ухо темнее; сзади темнее оба
// уха. Боковая часть (L−R)/2 остаётся, только тише — ей держится объём записи. 4D+ — ещё «ближе-дальше»
// (громкость и тембр), 9D+ — плавание по высоте (наклон тембра) и второе «эхо» с другой стороны,
// 13D+ — орбита медленно меняет скорость, объём «дышит». Подмес реверба — через общий реверб (`Effects`).
// Включение, выключение и смена D — плавные (~300 мс): параметры и доля обработки сглаживаются в самом
// процессоре, поэтому щелчков нет. Выключено и доля дошла до нуля — сигнал идёт как есть, байт в байт.

export const SPACE_MAX = 16
/** Чипы в меню: что реально звучит по-разному. Промежуточные D — из таблицы, с телефона или синка. */
export const SPACE_PRESETS = [1, 2, 3, 8, 12, 16] as const
/** Включили без выбора — классическое 8D. */
export const SPACE_DEFAULT = 8

/** Параметры пространства для процессора (одинаковые на ПК и iPhone). */
export interface SpaceParams {
  /** Скорость орбиты, Гц (оборотов в секунду). */
  rate: number
  /** Размах по сторонам 0…1 (1 — до упора вбок). */
  amp: number
  /** 0 — качание лево-право, 1 — полный круг (спереди-сзади). */
  circle: number
  /** Боковая часть записи (L−R): 1 — как есть, больше — шире. */
  side: number
  /** «Ближе-дальше» 0…1. */
  depth: number
  /** Плавание по высоте (наклон тембра) 0…1. */
  height: number
  /** Второе «эхо» с другой стороны 0…1. */
  echo: number
  /** Медленное изменение орбиты и «дыхание» объёма 0…1. */
  drift: number
  /** Подмес реверба 0…1 — складывается с ревербом пользователя (`withSpaceReverb`). */
  send: number
}

const OFF: SpaceParams = { rate: 0, amp: 0, circle: 0, side: 1, depth: 0, height: 0, echo: 0, drift: 0, send: 0 }

/** Опорные точки. Цифры — отправная точка, докручиваются на слух (и в Space.swift тоже). */
export const SPACE_TABLE: readonly (readonly [number, SpaceParams])[] = [
  // 1D — без движения, чуть шире стерео
  [1, { rate: 0, amp: 0, circle: 0, side: 1.25, depth: 0, height: 0, echo: 0, drift: 0, send: 0 }],
  // 2D — качание лево-право
  [2, { rate: 0.05, amp: 0.5, circle: 0, side: 0.8, depth: 0, height: 0, echo: 0, drift: 0, send: 0.05 }],
  // 3D — круг вокруг головы
  [3, { rate: 0.08, amp: 1, circle: 1, side: 0.5, depth: 0, height: 0, echo: 0, drift: 0, send: 0.1 }],
  // 8D — классическое: быстрее, лёгкое «ближе-дальше»
  [8, { rate: 0.14, amp: 1, circle: 1, side: 0.45, depth: 0.35, height: 0, echo: 0, drift: 0, send: 0.22 }],
  // 12D — плавание по высоте и второе эхо
  [12, { rate: 0.2, amp: 1, circle: 1, side: 0.4, depth: 0.6, height: 0.5, echo: 0.22, drift: 0, send: 0.32 }],
  // 16D — орбита гуляет, объём дышит
  [16, { rate: 0.26, amp: 1, circle: 1, side: 0.4, depth: 0.8, height: 0.8, echo: 0.3, drift: 1, send: 0.4 }],
]

/** D в пределах 0…16, целое; мусор — 0 (выключено). */
export function clampSpace(v: unknown): number {
  if (typeof v !== 'number' || !Number.isFinite(v)) return 0
  return Math.min(SPACE_MAX, Math.max(0, Math.round(v)))
}

const round = (v: number) => Math.round(v * 1000) / 1000

/** D → параметры: опорная точка или линейно между соседними; 0 — выключено. */
export function spaceParams(d: number): SpaceParams {
  const n = clampSpace(d)
  if (n === 0) return { ...OFF }
  for (let i = 0; i < SPACE_TABLE.length; i++) {
    const [at, p] = SPACE_TABLE[i]
    if (n === at) return { ...p }
    const next = SPACE_TABLE[i + 1]
    if (next && n > at && n < next[0]) {
      const k = (n - at) / (next[0] - at)
      const q = next[1]
      const out = {} as SpaceParams
      for (const key of Object.keys(p) as (keyof SpaceParams)[]) out[key] = round(p[key] + (q[key] - p[key]) * k)
      return out
    }
  }
  return { ...SPACE_TABLE[SPACE_TABLE.length - 1][1] }
}

/** Реверб, который звучит: свой реверб пользователя + подмес пространства, не больше 1. */
export function withSpaceReverb(reverb: number, space: number): number {
  const send = spaceParams(space).send
  return round(1 - (1 - Math.min(1, Math.max(0, reverb))) * (1 - send))
}

/** «8D» для значка и плашки; выключено — пусто. */
export const spaceLabel = (d: number) => (clampSpace(d) > 0 ? `${clampSpace(d)}D` : '')

/**
 * Процессор пространства (AudioWorklet). Без внешних ссылок: строка грузится в контекст как модуль.
 * Сообщение порта — `{ on, p: SpaceParams }`. Зеркало — `Spatializer` в `ios/Sonar/Playback/Space.swift`.
 */
export const SPACE_WORKLET = `
const TAU = Math.PI * 2
const KEYS = ['rate', 'amp', 'circle', 'side', 'depth', 'height', 'echo', 'drift']
class SonarSpace extends AudioWorkletProcessor {
  constructor() {
    super()
    this.size = 16384
    this.mask = this.size - 1
    this.buf = new Float32Array(this.size)
    this.w = 0
    this.tgt = { rate: 0, amp: 0, circle: 0, side: 1, depth: 0, height: 0, echo: 0, drift: 0 }
    this.cur = Object.assign({}, this.tgt)
    this.mix = 0
    this.mixTgt = 0
    this.ph = 0
    this.ph2 = 0
    this.ph3 = 0
    this.u = 0
    this.lpL = 0
    this.lpR = 0
    // сглаживание параметров: постоянная 0.1 с → почти дошли за ~300 мс
    this.a = 1 - Math.exp(-1 / (0.1 * sampleRate))
    // «тень головы» и тембр — однополюсный НЧ около 1.8 кГц
    this.lpA = 1 - Math.exp(-TAU * 1800 / sampleRate)
    this.itd = 0.00066 * sampleRate
    this.echoDelay = 0.023 * sampleRate
    this.port.onmessage = (e) => {
      const m = e.data || {}
      if (m.p) for (const k of KEYS) if (typeof m.p[k] === 'number') this.tgt[k] = m.p[k]
      this.mixTgt = m.on ? 1 : 0
      if (m.on && this.mix === 0) this.reset()
    }
  }
  reset() {
    this.buf.fill(0)
    this.lpL = 0
    this.lpR = 0
    // включили с нуля — параметры сразу целевые, плавность даёт доля обработки
    Object.assign(this.cur, this.tgt)
  }
  read(d) {
    const pos = this.w - d
    const i = Math.floor(pos)
    const f = pos - i
    return this.buf[i & this.mask] * (1 - f) + this.buf[(i + 1) & this.mask] * f
  }
  process(inputs, outputs) {
    const inp = inputs[0]
    const out = outputs[0]
    if (!out || !out.length) return true
    const n = out[0].length
    const inL = inp && inp.length ? inp[0] : null
    const inR = inp && inp.length > 1 ? inp[1] : inL
    if (!inL) {
      for (const ch of out) ch.fill(0)
      return true
    }
    if (this.mix === 0 && this.mixTgt === 0) {
      out[0].set(inL)
      if (out.length > 1) out[1].set(inR)
      return true
    }
    const c = this.cur, t = this.tgt, a = this.a, sr = sampleRate
    const outL = out[0], outR = out.length > 1 ? out[1] : null
    for (let i = 0; i < n; i++) {
      for (const k of KEYS) c[k] += (t[k] - c[k]) * a
      this.mix += (this.mixTgt - this.mix) * a
      if (this.mixTgt === 0 && this.mix < 0.0005) this.mix = 0
      const l = inL[i], r = inR[i]
      const mid = (l + r) * 0.5
      const side = (l - r) * 0.5
      this.buf[this.w & this.mask] = mid
      // орбита
      this.u += 0.013 / sr
      if (this.u >= 1) this.u -= 1
      const wobble = Math.sin(TAU * this.u)
      this.ph += c.rate * (1 + 0.3 * c.drift * wobble) / sr
      this.ph -= Math.floor(this.ph)
      this.ph2 += c.rate * 0.37 / sr
      this.ph2 -= Math.floor(this.ph2)
      this.ph3 += (c.rate * 0.23 + 0.02) / sr
      this.ph3 -= Math.floor(this.ph3)
      const pan = c.amp * Math.sin(TAU * this.ph)
      const front = 1 - c.circle + c.circle * Math.cos(TAU * this.ph)
      // уровни ушей: равная мощность, дальнее ухо не глохнет совсем
      const k = 0.85
      const gL = Math.sqrt(0.5 * (1 - k * pan))
      const gR = Math.sqrt(0.5 * (1 + k * pan))
      // задержка дальнего уха
      const xL = this.read(pan > 0 ? pan * this.itd : 0)
      const xR = this.read(pan < 0 ? -pan * this.itd : 0)
      // ближе-дальше и высота
      const dist = c.depth * (0.5 + 0.5 * Math.sin(TAU * this.ph2))
      const tilt = c.height * Math.sin(TAU * this.ph3)
      const back = Math.max(0, -front) * 0.35
      const darkL = Math.min(0.9, (pan > 0 ? 0.6 * pan : 0) + back + 0.3 * dist)
      const darkR = Math.min(0.9, (pan < 0 ? -0.6 * pan : 0) + back + 0.3 * dist)
      this.lpL += (xL - this.lpL) * this.lpA
      this.lpR += (xR - this.lpR) * this.lpA
      const bright = 1 + 0.6 * tilt
      let eL = this.lpL + (xL - this.lpL) * (1 - darkL) * bright
      let eR = this.lpR + (xR - this.lpR) * (1 - darkR) * bright
      // эхо — с другой стороны орбиты
      if (c.echo > 0.0005) {
        const e = this.read(this.echoDelay) * c.echo
        eL += e * gR
        eR += e * gL
      }
      const norm = 1 / Math.sqrt(1 + c.echo * c.echo)
      const gd = (1 - 0.3 * dist + 0.15 * c.depth) * norm * Math.SQRT2
      const sg = c.side * (1 + 0.25 * c.drift * Math.sin(TAU * this.ph2 * 0.5 + 1))
      const wL = gL * eL * gd + side * sg
      const wR = gR * eR * gd - side * sg
      const m = this.mix
      outL[i] = l + (wL - l) * m
      if (outR) outR[i] = r + (wR - r) * m
      this.w = (this.w + 1) & this.mask
    }
    return true
  }
}
registerProcessor('sonar-space', SonarSpace)
`

const modules = new WeakMap<BaseAudioContext, Promise<void>>()

/** Модуль `sonar-space` — в контекст один раз. */
export function loadSpaceModule(ctx: BaseAudioContext): Promise<void> {
  let p = modules.get(ctx)
  if (!p) {
    p = (async () => {
      const url = URL.createObjectURL(new Blob([SPACE_WORKLET], { type: 'application/javascript' }))
      try {
        await ctx.audioWorklet.addModule(url)
      } finally {
        URL.revokeObjectURL(url)
      }
    })()
    modules.set(ctx, p)
    p.catch(() => modules.delete(ctx))
  }
  return p
}
