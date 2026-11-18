// Пинг сонара на поле точек героя Главной (components/SonarField.svelte): от центра расходится кольцо,
// точки на его фронте вспыхивают и надуваются — даже там, где фигуры нет. Слабое кольцо — на каждый бит
// трека, сильное и широкое — на смену трека. Так видно, что поле слушает именно то, что играет.
// И радиус точки: удар музыки надувает её сверх полного размера (значение поля упирается в 1).

export interface Ping {
  /** Когда кольцо вышло из центра, с. */
  time: number
  /** Сила 0…1: яркость и ширина кольца. */
  strength: number
}

/** Скорость фронта, px/с, и сколько кольцо живёт, с. */
export const PING_SPEED = 300
export const PING_LIFE = 1.6
/** Полуширина кольца при силе 0, px; сильное кольцо вдвое шире. */
export const PING_WIDTH = 18
/** Сила кольца на бит и на смену трека. */
export const BEAT_PING = 0.45
export const TRACK_PING = 1
/** Больше колец одновременно не держим — каждое стоит прохода по всем точкам. */
export const MAX_PINGS = 6

/** Дальше этой доли ширины кольца точку не считаем — там уже ноль. */
const CUTOFF = 3

export function prunePings(pings: readonly Ping[], t: number): Ping[] {
  return pings.filter((p) => t - p.time < PING_LIFE)
}

export function addPing(pings: readonly Ping[], time: number, strength: number): Ping[] {
  return [...prunePings(pings, time), { time, strength }].slice(-MAX_PINGS)
}

/** Вклад одного кольца в точку на расстоянии `d` px от центра в момент `t`: 0…strength. */
export function pingValue(p: Ping, d: number, t: number): number {
  const age = t - p.time
  if (age < 0 || age >= PING_LIFE) return 0
  const width = PING_WIDTH * (1 + p.strength)
  const x = (d - age * PING_SPEED) / width
  if (Math.abs(x) > CUTOFF) return 0
  const fade = 1 - age / PING_LIFE
  return p.strength * fade * fade * Math.exp(-x * x)
}

/** Все кольца в точке: вклады складываются, не больше 1. */
export function stackPings(pings: readonly Ping[], d: number, t: number): number {
  let sum = 0
  for (const p of pings) sum += pingValue(p, d, t)
  return Math.min(1, sum)
}

/** Полный кружок в покое — эта доля шага сетки (соседи не слипаются). */
export const DOT_R = 0.45
/** Насколько удар музыки надувает точку сверх полного размера. */
export const DOT_KICK = 0.3

const clamp01 = (v: number): number => Math.min(1, Math.max(0, v))

/** Радиус точки, px: `v` — значение поля 0…1, `kick` — удар музыки 0…1 (низы и кольца). */
export function dotRadius(step: number, v: number, kick: number): number {
  return step * DOT_R * clamp01(v) * (1 + DOT_KICK * clamp01(kick))
}
