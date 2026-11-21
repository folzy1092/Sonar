// Поле точек героя Главной (порт iPhone `Features/Home/SonarField.swift`, решение владельца 2026-11-18):
// сетка кружков, размер каждого — «яркость» фигуры в этом месте. Фигуры по кругу перетекают друг в
// друга: живая «слизь» из капель (метаболы) → знак Sonar с бликом → снова слизь → две волны-ленты.
// Точки сами чуть плывут и дышат, когда играет музыка — сильнее и с рябью от центра. Клик — по кругу
// волна-разлёт, вихрь, подскок (как `SonarField.play` на iPhone), наведение — лёгкое притяжение к курсору,
// под музыку — спектр (низы — дыхание и размер капель, бит — встряска, верха — рябь). Чистая математика
// без DOM — рисует `components/SonarField.svelte`.

export interface Grid {
  cols: number
  rows: number
  step: number
  ox: number
  oy: number
}

export function makeGrid(width: number, height: number, step: number): Grid {
  const cols = Math.max(0, Math.floor(width / step))
  const rows = Math.max(0, Math.floor(height / step))
  return { cols, rows, step, ox: (width - cols * step) / 2, oy: (height - rows * step) / 2 }
}

export const smooth = (v: number): number => {
  const x = Math.min(1, Math.max(0, v))
  return x * x * (3 - 2 * x)
}

/** Сколько секунд фигура держится и сколько перетекает в следующую. */
export const HOLD = 7
export const MORPH = 2.8
/** Порядок фигур: слизь чаще всего, знак — время от времени. */
export const SHAPES = ['slime', 'logo', 'slime', 'waves'] as const
export type Shape = (typeof SHAPES)[number]

/** Какая фигура сейчас и насколько она перетекла в следующую (k: 0…1). */
export function phaseAt(t: number): { index: number; k: number } {
  const period = HOLD + MORPH
  const total = period * SHAPES.length
  const phase = ((t % total) + total) % total
  const index = Math.floor(phase / period)
  const local = phase - index * period
  return { index, k: local < HOLD ? 0 : smooth((local - HOLD) / MORPH) }
}

/** Насколько низы музыки надувают капли слизи (на полном басе радиус ×1.4 — капли заметно сливаются). */
export const SLIME_SWELL = 0.4

/** «Слизь»: четыре капли плавают по своим орбитам и сливаются, когда сходятся (метаболы). */
/** `swell` 0…1 — низы музыки: капли надуваются. */
export function slime(x: number, y: number, t: number, halfW: number, swell = 0): number {
  let f = 0
  const blobs = 4
  for (let i = 0; i < blobs; i++) {
    const a = t * (0.21 + i * 0.07) + i * 1.7
    const cx = Math.sin(a) * halfW * 0.42 + Math.sin(a * 0.53 + i) * 0.18
    const cy = Math.cos(a * 0.83 + i * 2.1) * 0.38
    const r = (0.34 + 0.08 * Math.sin(t * 0.6 + i * 1.3)) * (1 + SLIME_SWELL * swell)
    const dx = x - cx
    const dy = y - cy
    f += (r * r) / (dx * dx + dy * dy + 1e-4)
  }
  // порог поверхности ~1: внутри — полная яркость, край мягкий
  return smooth((f - 0.75) / 0.6)
}

/** Две волны-ленты, тоньше к краям. */
export function waves(x: number, y: number, halfW: number, t: number): number {
  const taper = Math.max(0, Math.cos(((x / halfW) * Math.PI) / 2))
  const band = (amp: number, freq: number, speed: number, shift: number, width: number) => {
    const center = amp * Math.sin(x * freq + t * speed + shift) + 0.18 * Math.sin(x * freq * 2.3 - t * speed * 0.7)
    const thick = width * (0.7 + 0.3 * Math.sin(x * 1.3 - t * 0.9 + shift)) * Math.sqrt(taper)
    if (thick <= 0.01) return 0
    const d = Math.abs(y - center) / thick
    return d < 1 ? Math.sqrt(smooth(1 - d)) : 0
  }
  return Math.max(band(0.26, 1.5, 1.1, 0, 0.5), band(0.2, 2.0, -0.8, 1.9, 0.34) * 0.8)
}

/**
 * Значение точки (col, row): 0 — точки нет, 1 — полный кружок. `logo` — маска знака на эту сетку.
 * `audio` — уровни спектра (`stepAudio`): есть — дыхание и рябь идут от музыки, нет — по часам.
 */
export function fieldValue(
  col: number,
  row: number,
  g: Grid,
  logo: Float32Array | null,
  t: number,
  playing: boolean,
  audio: Bands | null = null,
): number {
  const x = (col + 0.5 - g.cols / 2) / (g.rows / 2)
  const y = (row + 0.5 - g.rows / 2) / (g.rows / 2)
  const halfW = g.cols / g.rows
  const shape = (i: number): number => {
    switch (SHAPES[i % SHAPES.length]) {
      case 'logo': {
        const m = logo?.[row * g.cols + col] ?? 0
        return m * (0.8 + 0.2 * Math.sin(x * 2.2 + y * 1.4 - t * 1.6))
      }
      case 'waves':
        return waves(x, y, halfW, t)
      default:
        return slime(x, y, t, halfW, audio?.low ?? 0)
    }
  }
  const { index, k } = phaseAt(t)
  let v = k === 0 ? shape(index) : shape(index) * (1 - k) + shape(index + 1) * k
  if (audio) v *= audioSwell(audio, Math.hypot(x, y), t)
  else {
    const breath = playing ? 0.12 : 0.05
    v *= 1 + breath * Math.sin(t * (playing ? 3.2 : 1.4))
    if (playing) v *= 0.86 + 0.14 * Math.sin(Math.hypot(x, y) * 7 - t * 4.5)
  }
  return Math.min(1, Math.max(0, v * edgeFade(col, row, g)))
}

/** Края поля растворяются: 1 в середине, 0 у самой кромки. */
export function edgeFade(col: number, row: number, g: Grid): number {
  if (!g.rows) return 0
  const x = (col + 0.5 - g.cols / 2) / (g.rows / 2)
  const y = (row + 0.5 - g.rows / 2) / (g.rows / 2)
  const ex = Math.max(0, 1 - Math.pow(Math.abs(x) / (g.cols / g.rows), 6))
  const ey = Math.max(0, 1 - Math.pow(Math.abs(y), 6))
  return ex * ey
}

/** Течение: точка плавает на ~1.5 px и чуть меняет размер; `amp` — размах (середина спектра раскачивает). */
export function drift(col: number, row: number, t: number, amp = 1): { dx: number; dy: number; scale: number } {
  return {
    dx: 1.5 * amp * Math.sin(t * 0.9 + row * 0.32 + col * 0.07),
    dy: 1.5 * amp * Math.cos(t * 0.75 + col * 0.28 - row * 0.05),
    scale: 0.9 + 0.1 * Math.sin(t * 1.1 + col * 0.45 + row * 0.6),
  }
}

// ── Касание и наведение ─────────────────────────────────────────────────────────────────────────────

/** Смещение точки и множитель её размера. */
export interface Offset {
  dx: number
  dy: number
  scale: number
}
export const NO_OFFSET: Offset = Object.freeze({ dx: 0, dy: 0, scale: 1 })

/** Сколько точки шевелятся после того, как до них дошла волна клика, с (как `pokeLife` на iPhone). */
export const POKE_LIFE = 1.3
/** Скорость фронта волны от клика, px/с. */
export const FRONT_SPEED = 420
/** Больше одновременных кликов не держим — каждый стоит прохода по всем точкам. */
export const MAX_POKES = 8

/** Эффект клика по кругу: волна-разлёт → вихрь → подскок. */
export type PokeKind = 0 | 1 | 2
export interface Poke {
  x: number
  y: number
  /** Время клика, с. */
  time: number
  kind: PokeKind
}

/** Живые клики: волна ещё не прошла всё поле (`reach` — его диагональ, px) и не отзвучала. Клик чуть
 *  «из будущего» (время события позже начала кадра) остаётся — он просто ещё не начал играть. */
export function prunePokes(pokes: readonly Poke[], t: number, reach: number): Poke[] {
  const span = POKE_LIFE + reach / FRONT_SPEED
  return pokes.filter((p) => t - p.time < span)
}

/** Добавить клик (`count` — его номер): эффекты идут по кругу, отзвучавшие и лишние отбрасываются. */
export function addPoke(pokes: readonly Poke[], x: number, y: number, time: number, count: number, reach: number): Poke[] {
  const kind = (((count % 3) + 3) % 3) as PokeKind
  return [...prunePokes(pokes, time, reach), { x, y, time, kind }].slice(-MAX_POKES)
}

/**
 * Игра от клика (порт `SonarField.play`): волна идёт от точки клика через всю фигуру; точка «оживает»,
 * когда до неё дошёл фронт, пружинит затухающей синусоидой и успокаивается за `POKE_LIFE`.
 * 0 — разлёт кольцом и обратно; 1 — вихрь вокруг курсора; 2 — подскок вверх с надуванием.
 */
export function pokeOffset(p: Poke, cx: number, cy: number, t: number): Offset {
  const vx = cx - p.x
  const vy = cy - p.y
  const d = Math.max(1, Math.hypot(vx, vy))
  const local = t - p.time - d / FRONT_SPEED
  if (local <= 0 || local >= POKE_LIFE) return NO_OFFSET
  const env = Math.exp(-local * 4.5) * Math.exp(-d / 520)
  switch (p.kind) {
    case 1: {
      const angle = 0.5 * Math.sin(local * 9) * env * Math.min(1, 60 / d + 0.25)
      const ca = Math.cos(angle)
      const sa = Math.sin(angle)
      return {
        dx: vx * ca - vy * sa - vx,
        dy: vx * sa + vy * ca - vy,
        scale: 1 + 0.25 * Math.abs(Math.sin(local * 9)) * env,
      }
    }
    case 2: {
      const hop = Math.abs(Math.sin(local * 10)) * env
      return { dx: 0, dy: -10 * hop, scale: 1 + 0.45 * hop }
    }
    default: {
      const push = 14 * Math.sin(local * 12) * env
      return { dx: (vx / d) * push, dy: (vy / d) * push, scale: 1 + 0.35 * Math.max(0, Math.sin(local * 12)) * env }
    }
  }
}

/** Несколько кликов складываются: сдвиги суммируются, размеры перемножаются. `out` — переиспользуемый
 *  объект для кадра (тысячи точек × каждый кадр — без мусора для сборщика, иначе поле подёргивается). */
export function stackPokes(pokes: readonly Poke[], cx: number, cy: number, t: number, out?: { dx: number; dy: number; scale: number }): Offset {
  let dx = 0
  let dy = 0
  let scale = 1
  for (const p of pokes) {
    const o = pokeOffset(p, cx, cy, t)
    dx += o.dx
    dy += o.dy
    scale *= o.scale
  }
  if (!out) return { dx, dy, scale }
  out.dx = dx
  out.dy = dy
  out.scale = scale
  return out
}

/** Наведение: радиус притяжения и наибольший сдвиг к курсору, px. */
export const HOVER_RADIUS = 90
export const HOVER_PULL = 5

/** Лёгкое притяжение точки к курсору; `amount` 0…1 — насколько курсор «здесь» (плавно входит и уходит). */
export function hoverPull(cx: number, cy: number, hx: number, hy: number, amount: number): Offset {
  if (amount <= 0) return NO_OFFSET
  const vx = hx - cx
  const vy = hy - cy
  const d = Math.hypot(vx, vy)
  if (d < 1e-3) return { dx: 0, dy: 0, scale: 1 + 0.12 * amount }
  const fall = Math.exp(-(d * d) / (HOVER_RADIUS * HOVER_RADIUS))
  const mag = Math.min(HOVER_PULL * amount * fall, d * 0.4)
  return { dx: (vx / d) * mag, dy: (vy / d) * mag, scale: 1 + 0.12 * amount * fall }
}

/** Плавное приближение к цели с постоянной времени `tau`, с (не зависит от частоты кадров). */
export function approach(current: number, target: number, dt: number, tau: number): number {
  if (dt <= 0) return current
  if (tau <= 0) return target
  return current + (target - current) * (1 - Math.exp(-dt / tau))
}

/** «Меньше движения»: клик — только мягкая смена прозрачности, 0 → провал → 0 за `POKE_LIFE`. */
export function fadePulse(age: number): number {
  if (age <= 0 || age >= POKE_LIFE) return 0
  const s = Math.sin((Math.PI * age) / POKE_LIFE)
  return s * s
}

// ── Музыка ───────────────────────────────────────────────────────────────────────────────────────────

/** Уровни трёх полос 0…1. */
export interface Bands {
  low: number
  mid: number
  high: number
}
export const SILENT: Bands = Object.freeze({ low: 0, mid: 0, high: 0 })

/** Границы полос, Гц: низы (бочка, бас) · середина (голос) · верха (тарелки, «воздух»). */
export const BAND_EDGES = { low: [30, 250], mid: [250, 2000], high: [2000, 12000] } as const

/** Средний уровень полосы [fromHz, toHz) по байтам анализатора (0…255) → 0…1. */
export function bandLevel(data: ArrayLike<number>, binHz: number, fromHz: number, toHz: number): number {
  if (binHz <= 0 || !data.length) return 0
  const from = Math.max(1, Math.floor(fromHz / binHz))
  const to = Math.min(data.length, Math.max(from + 1, Math.ceil(toHz / binHz)))
  if (from >= to) return 0
  let sum = 0
  for (let i = from; i < to; i++) sum += data[i]
  return sum / (to - from) / 255
}

export function bandLevels(data: ArrayLike<number>, binHz: number): Bands {
  return {
    low: bandLevel(data, binHz, BAND_EDGES.low[0], BAND_EDGES.low[1]),
    mid: bandLevel(data, binHz, BAND_EDGES.mid[0], BAND_EDGES.mid[1]),
    high: bandLevel(data, binHz, BAND_EDGES.high[0], BAND_EDGES.high[1]),
  }
}

/** Детектор бита по низам: всплеск над скользящим средним, не чаще раза в `BEAT_GAP` с. */
export const BEAT_RATIO = 1.2
export const BEAT_MIN_RISE = 0.05
export const BEAT_FLOOR = 0.15
export const BEAT_GAP = 0.28
export const BEAT_AVG_TAU = 0.6

export interface BeatState {
  /** Скользящее среднее энергии низов. */
  avg: number
  /** Когда был последний бит, с. */
  lastBeat: number
  /** Время прошлого отсчёта, с (NaN — отсчётов ещё не было). */
  lastT: number
}
export const BEAT_START: BeatState = Object.freeze({ avg: 0, lastBeat: -Infinity, lastT: Number.NaN })

export function detectBeat(s: BeatState, energy: number, t: number): { state: BeatState; beat: boolean } {
  if (!Number.isFinite(s.lastT)) return { state: { avg: energy, lastBeat: s.lastBeat, lastT: t }, beat: false }
  const dt = Math.min(0.5, Math.max(0, t - s.lastT))
  const beat =
    energy > BEAT_FLOOR && energy > s.avg * BEAT_RATIO && energy - s.avg > BEAT_MIN_RISE && t - s.lastBeat >= BEAT_GAP
  const avg = approach(s.avg, energy, dt, BEAT_AVG_TAU)
  return { state: { avg, lastBeat: beat ? t : s.lastBeat, lastT: t }, beat }
}

/** Автоусиление: уровень относительно недавнего пика полосы (пик медленно опадает), чтобы тихий трек
 *  или убавленная громкость тоже двигали поле. Пик ниже `GAIN_FLOOR` не растягиваем — это тишина. */
export const PEAK_TAU = 5
export const GAIN_FLOOR = 0.08

export function normalizeLevel(peak: number, value: number, dt: number): { peak: number; level: number } {
  const next = value >= peak ? value : approach(peak, value, dt, PEAK_TAU)
  // байты анализатора — в децибелах, поэтому шкала узкая: 60 % пика и ниже — уже «тихо»
  return { peak: next, level: smooth((value / Math.max(next, GAIN_FLOOR) - 0.6) / 0.4) }
}

/** Всё, что поле помнит о музыке между кадрами. */
export interface AudioState {
  peaks: Bands
  /** Сглаженные уровни для рисования: растут быстро, опадают мягко. */
  levels: Bands
  beat: BeatState
  /** Когда был последний бит (для встряски), с. */
  beatAt: number
}
export const AUDIO_START: AudioState = Object.freeze({
  peaks: SILENT,
  levels: SILENT,
  beat: BEAT_START,
  beatAt: -Infinity,
})

const ATTACK_TAU = 0.05
const RELEASE_TAU = 0.25

function follow(prev: number, target: number, dt: number): number {
  return approach(prev, target, dt, target > prev ? ATTACK_TAU : RELEASE_TAU)
}

/** Кадр музыки: сырые полосы (`bandLevels`; пауза — `SILENT`) → новое состояние. */
export function stepAudio(s: AudioState, raw: Bands, t: number, dt: number): AudioState {
  const low = normalizeLevel(s.peaks.low, raw.low, dt)
  const mid = normalizeLevel(s.peaks.mid, raw.mid, dt)
  const high = normalizeLevel(s.peaks.high, raw.high, dt)
  const { state: beat, beat: hit } = detectBeat(s.beat, raw.low, t)
  return {
    peaks: { low: low.peak, mid: mid.peak, high: high.peak },
    levels: {
      low: follow(s.levels.low, low.level, dt),
      mid: follow(s.levels.mid, mid.level, dt),
      high: follow(s.levels.high, high.level, dt),
    },
    beat,
    beatAt: hit ? t : s.beatAt,
  }
}

/** Музыка совсем стихла — можно вернуться к спокойному дыханию по часам. */
export function isQuiet(levels: Bands): boolean {
  return levels.low < 0.01 && levels.mid < 0.01 && levels.high < 0.01
}

/** Множитель яркости точки от музыки: низы — дыхание, верха — рябь от центра (`d` — расстояние до него).
 *  На нулевых уровнях совпадает с тихим дыханием без музыки — переход незаметен. */
export function audioSwell(a: Bands, d: number, t: number): number {
  const breath = 1 + 0.05 * Math.sin(t * 1.4) + 0.32 * a.low + 0.08 * a.mid
  const ripple = 1 - 0.22 * a.high * (0.5 - 0.5 * Math.sin(d * 9 - t * 6))
  return breath * ripple
}

/** Встряска на бит: короткая, `SHAKE_LIFE` с, у каждой точки своё направление. */
export const SHAKE_LIFE = 0.35
export const SHAKE_PX = 2.4

export function shakeOffset(col: number, row: number, age: number): Offset {
  if (age < 0 || age >= SHAKE_LIFE) return NO_OFFSET
  const env = Math.exp(-age / 0.09)
  const phase = Math.sin(col * 12.9898 + row * 78.233) * 43758.5453
  const a = SHAKE_PX * env * Math.sin(age * 48 + phase)
  return { dx: a * Math.cos(phase), dy: a * Math.sin(phase), scale: 1 + 0.12 * env }
}

// ── Кадры ────────────────────────────────────────────────────────────────────────────────────────────

/** Потолок кадров: обычно 30, при «Меньше движения» и экономии ресурсов — 15. */
export const FIELD_FPS = 30
export const LITE_FPS = 15

/** Пора ли рисовать кадр (2 мс запаса — чтобы дрожь requestAnimationFrame не роняла 30 к/с до 20).
 *  `live` — с полем играют прямо сейчас (волна от клика, курсор над полем): каждый кадр экрана, иначе
 *  пружина клика на 30 к/с идёт рывками по 5–6 px. В «Меньше движения» и экономии — всё равно 15. */
export function frameDue(now: number, last: number, lite: boolean, live = false): boolean {
  if (live && !lite) return true
  return now - last >= 1000 / (lite ? LITE_FPS : FIELD_FPS) - 2
}
