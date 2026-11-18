import { describe, expect, it } from 'vitest'
import {
  AUDIO_START,
  BEAT_GAP,
  BEAT_START,
  FRONT_SPEED,
  HOVER_PULL,
  HOVER_RADIUS,
  MAX_POKES,
  NO_OFFSET,
  POKE_LIFE,
  SHAKE_LIFE,
  SILENT,
  addPoke,
  approach,
  audioSwell,
  bandLevel,
  bandLevels,
  detectBeat,
  fadePulse,
  fieldValue,
  frameDue,
  hoverPull,
  isQuiet,
  makeGrid,
  normalizeLevel,
  pokeOffset,
  prunePokes,
  shakeOffset,
  stackPokes,
  stepAudio,
  type BeatState,
  type Offset,
  type Poke,
  type PokeKind,
} from './sonar-field'

const size = (o: Offset) => Math.max(Math.abs(o.dx), Math.abs(o.dy), Math.abs(o.scale - 1))
const poke = (kind: PokeKind, x = 0, y = 0, time = 10): Poke => ({ x, y, time, kind })
/** Когда фронт волны доходит до точки на расстоянии d. */
const arrival = (p: Poke, d: number) => p.time + d / FRONT_SPEED

describe('клики: пружина затухает за ~1.3 с', () => {
  for (const kind of [0, 1, 2] as const) {
    it(`эффект ${kind}: заметен сразу после фронта, к концу почти ноль, потом — покой`, () => {
      // Arrange
      const p = poke(kind)
      const d = 60
      const at = (local: number) => pokeOffset(p, d, 0, arrival(p, d) + local)

      // Act
      const early = Math.max(...[0.05, 0.1, 0.15, 0.2].map((l) => size(at(l))))
      const late = Math.max(...[1.2, 1.25, 1.29].map((l) => size(at(l))))
      const after = at(POKE_LIFE + 0.01)

      // Assert
      expect(early).toBeGreaterThan(0.1)
      // меньше пятой доли пикселя и в десятки раз меньше начала
      expect(late).toBeLessThan(0.2)
      expect(late).toBeLessThan(early * 0.03)
      expect(after).toEqual(NO_OFFSET)
    })
  }

  it('до прихода фронта точка не шевелится', () => {
    // Arrange
    const p = poke(0)

    // Act
    const o = pokeOffset(p, 200, 0, arrival(p, 200) - 0.01)

    // Assert
    expect(o).toEqual(NO_OFFSET)
  })

  it('разлёт толкает точку от клика, подскок — вверх', () => {
    // Arrange
    const ring = poke(0)
    const hop = poke(2)

    // Act
    const r = pokeOffset(ring, 50, 0, arrival(ring, 50) + 0.1)
    const h = pokeOffset(hop, 50, 0, arrival(hop, 50) + 0.1)

    // Assert
    expect(r.dx).toBeGreaterThan(0)
    expect(Math.abs(r.dy)).toBeLessThan(1e-9)
    expect(h.dy).toBeLessThan(0)
    expect(h.dx).toBe(0)
  })

  it('вихрь поворачивает точку вокруг клика, не меняя расстояния', () => {
    // Arrange
    const p = poke(1)
    const t = arrival(p, 40) + 0.1

    // Act
    const o = pokeOffset(p, 40, 0, t)

    // Assert
    expect(Math.hypot(40 + o.dx, o.dy)).toBeCloseTo(40, 6)
    expect(Math.abs(o.dy)).toBeGreaterThan(0.1)
  })

  it('несколько кликов складываются', () => {
    // Arrange
    const a = poke(0, 0, 0, 10)
    const b = poke(0, 0, 0, 10)
    const t = arrival(a, 50) + 0.1

    // Act
    const one = pokeOffset(a, 50, 0, t)
    const both = stackPokes([a, b], 50, 0, t)

    // Assert
    expect(both.dx).toBeCloseTo(one.dx * 2, 9)
    expect(both.scale).toBeCloseTo(one.scale * one.scale, 9)
  })

  it('эффекты идут по кругу, отзвучавшие и лишние клики отбрасываются', () => {
    // Arrange
    let pokes: Poke[] = []
    const reach = 400

    // Act
    for (let i = 0; i < 3; i++) pokes = addPoke(pokes, 0, 0, 10 + i * 0.01, i, reach)
    const later = prunePokes(pokes, 10 + POKE_LIFE + reach / FRONT_SPEED + 0.1, reach)
    let many: Poke[] = []
    for (let i = 0; i < MAX_POKES + 4; i++) many = addPoke(many, 0, 0, 20, i, reach)

    // Assert
    expect(pokes.map((p) => p.kind)).toEqual([0, 1, 2])
    expect(later).toEqual([])
    expect(many).toHaveLength(MAX_POKES)
  })

  it('«Меньше движения»: провал прозрачности с нуля до нуля за то же время', () => {
    expect(fadePulse(0)).toBe(0)
    expect(fadePulse(POKE_LIFE / 2)).toBeCloseTo(1, 6)
    expect(fadePulse(POKE_LIFE)).toBe(0)
  })
})

describe('наведение', () => {
  it('тянет точку к курсору не дальше HOVER_PULL и не перетягивает за него', () => {
    // Act
    const near = hoverPull(0, 0, 30, 0, 1)
    const close = hoverPull(0, 0, 2, 0, 1)
    const far = hoverPull(0, 0, HOVER_RADIUS * 4, 0, 1)

    // Assert
    expect(near.dx).toBeGreaterThan(0)
    expect(near.dx).toBeLessThanOrEqual(HOVER_PULL)
    expect(close.dx).toBeLessThan(2)
    expect(size(far)).toBeLessThan(1e-3)
  })

  it('без курсора — покой', () => {
    expect(hoverPull(0, 0, 10, 10, 0)).toEqual(NO_OFFSET)
  })

  it('approach плавно идёт к цели и не зависит от дробления кадров', () => {
    // Act
    const once = approach(0, 1, 0.2, 0.1)
    let split = 0
    for (let i = 0; i < 4; i++) split = approach(split, 1, 0.05, 0.1)

    // Assert
    expect(once).toBeGreaterThan(0.8)
    expect(once).toBeLessThan(1)
    expect(split).toBeCloseTo(once, 9)
    expect(approach(0.3, 1, 0, 0.1)).toBe(0.3)
  })
})

describe('спектр: полосы', () => {
  const binHz = 10
  const spectrum = (fill: (hz: number) => number) => Uint8Array.from({ length: 2048 }, (_, i) => fill(i * binHz))

  it('низы, середина и верха считаются по своим частотам', () => {
    // Arrange
    const onlyLow = spectrum((hz) => (hz < 250 ? 255 : 0))
    const onlyHigh = spectrum((hz) => (hz >= 2000 && hz < 12000 ? 255 : 0))

    // Act
    const a = bandLevels(onlyLow, binHz)
    const b = bandLevels(onlyHigh, binHz)

    // Assert
    expect(a).toEqual({ low: 1, mid: 0, high: 0 })
    expect(b.low).toBe(0)
    expect(b.mid).toBe(0)
    expect(b.high).toBe(1)
  })

  it('уровень полосы — среднее её байтов', () => {
    // Arrange: полоса 100…140 Гц = индексы 10…13, половина по 255, половина по 0
    const data = new Uint8Array(64)
    data[10] = 255
    data[11] = 255

    // Act + Assert
    expect(bandLevel(data, binHz, 100, 140)).toBeCloseTo(0.5, 9)
  })

  it('пустые данные и полоса за краем — ноль', () => {
    expect(bandLevel(new Uint8Array(0), binHz, 30, 250)).toBe(0)
    expect(bandLevel(new Uint8Array(8), binHz, 2000, 12000)).toBe(0)
  })
})

describe('спектр: бит', () => {
  /** Прогнать сигнал кадрами по 1/30 с, вернуть время каждого бита. */
  const run = (signal: (t: number) => number, seconds: number) => {
    let s: BeatState = BEAT_START
    const beats: number[] = []
    for (let i = 0; i <= seconds * 30; i++) {
      const t = i / 30
      const r = detectBeat(s, signal(t), t)
      s = r.state
      if (r.beat) beats.push(t)
    }
    return beats
  }

  it('ровный сигнал — без битов', () => {
    expect(run(() => 0.6, 5)).toEqual([])
  })

  it('медленный подъём — без битов', () => {
    expect(run((t) => 0.3 + 0.05 * t, 6)).toEqual([])
  })

  it('всплеск над средним — бит', () => {
    // Act
    const beats = run((t) => (Math.abs(t - 2) < 0.02 ? 0.9 : 0.6), 3)

    // Assert
    expect(beats).toEqual([2])
  })

  it('повторы чаще BEAT_GAP не считаются', () => {
    // Arrange: всплески каждые 0.1 с
    const signal = (t: number) => (t > 1 && Math.round(t * 30) % 3 === 0 ? 0.95 : 0.55)

    // Act
    const beats = run(signal, 3)

    // Assert
    expect(beats.length).toBeGreaterThan(1)
    for (let i = 1; i < beats.length; i++) expect(beats[i] - beats[i - 1]).toBeGreaterThanOrEqual(BEAT_GAP - 1e-9)
  })

  it('тишина не даёт битов даже при относительном скачке', () => {
    expect(run((t) => (Math.abs(t - 2) < 0.02 ? 0.1 : 0.02), 3)).toEqual([])
  })
})

describe('спектр: уровни для рисования', () => {
  it('автоусиление: ровный уровень — полный, тишина — ноль, пик опадает медленно', () => {
    // Act
    const steady = normalizeLevel(0.3, 0.3, 1 / 30)
    const silent = normalizeLevel(0.3, 0, 1 / 30)
    const tiny = normalizeLevel(0, 0.02, 1 / 30)

    // Assert
    expect(steady.level).toBe(1)
    expect(silent.level).toBe(0)
    expect(silent.peak).toBeGreaterThan(0.29)
    expect(tiny.level).toBe(0)
  })

  it('под музыку уровни растут, на паузе мягко гаснут до тишины', () => {
    // Arrange
    let s = AUDIO_START
    const loud = { low: 0.7, mid: 0.5, high: 0.3 }

    // Act
    for (let i = 0; i < 30; i++) s = stepAudio(s, loud, i / 30, 1 / 30)
    const playing = s.levels
    for (let i = 30; i < 90; i++) s = stepAudio(s, SILENT, i / 30, 1 / 30)

    // Assert
    expect(playing.low).toBeGreaterThan(0.9)
    expect(isQuiet(playing)).toBe(false)
    expect(isQuiet(s.levels)).toBe(true)
  })

  it('stepAudio не меняет прежнее состояние', () => {
    // Arrange
    const before = JSON.stringify(AUDIO_START)

    // Act
    stepAudio(AUDIO_START, { low: 0.8, mid: 0.8, high: 0.8 }, 1, 1 / 30)

    // Assert
    expect(JSON.stringify(AUDIO_START)).toBe(before)
  })

  it('на нулевых уровнях поле дышит как без музыки', () => {
    // Arrange
    const g = makeGrid(300, 200, 10)

    // Act
    const quiet = fieldValue(15, 10, g, null, 3.3, false)
    const zeroAudio = fieldValue(15, 10, g, null, 3.3, false, SILENT)

    // Assert
    expect(zeroAudio).toBeCloseTo(quiet, 9)
  })

  it('низы надувают точки, верха дают рябь', () => {
    // Act
    const calm = audioSwell(SILENT, 0.5, 1)
    const bass = audioSwell({ low: 1, mid: 0, high: 0 }, 0.5, 1)
    const ripple = [0, 0.2, 0.4, 0.6].map((d) => audioSwell({ low: 0, mid: 0, high: 1 }, d, 1))

    // Assert
    expect(bass).toBeGreaterThan(calm + 0.25)
    expect(Math.max(...ripple) - Math.min(...ripple)).toBeGreaterThan(0.05)
  })
})

describe('встряска и кадры', () => {
  it('встряска короткая и затухает', () => {
    expect(size(shakeOffset(3, 4, 0.01))).toBeGreaterThan(0.05)
    expect(size(shakeOffset(3, 4, SHAKE_LIFE - 0.01))).toBeLessThan(0.1)
    expect(shakeOffset(3, 4, SHAKE_LIFE)).toEqual(NO_OFFSET)
  })

  it('не чаще 30 кадров в секунду, в лёгком режиме — 15', () => {
    expect(frameDue(1000 + 1000 / 60, 1000, false)).toBe(false)
    expect(frameDue(1000 + 1000 / 30 - 1, 1000, false)).toBe(true)
    expect(frameDue(1000 + 1000 / 30, 1000, true)).toBe(false)
    expect(frameDue(1000 + 1000 / 15, 1000, true)).toBe(true)
  })
})
