import { describe, expect, it } from 'vitest'
import { clampSpace, SPACE_PRESETS, SPACE_TABLE, SPACE_WORKLET, spaceLabel, spaceParams, withSpaceReverb } from './space'

describe('таблица пространства', () => {
  it('D в пределах 0…16, мусор — выключено', () => {
    expect(clampSpace(-3)).toBe(0)
    expect(clampSpace(40)).toBe(16)
    expect(clampSpace(7.6)).toBe(8)
    expect(clampSpace('8')).toBe(0)
    expect(clampSpace(NaN)).toBe(0)
  })
  it('опорные точки — как в таблице, промежуточные — между соседями', () => {
    for (const [d, p] of SPACE_TABLE) expect(spaceParams(d)).toEqual(p)
    const p5 = spaceParams(5)
    expect(p5.rate).toBeGreaterThan(spaceParams(3).rate)
    expect(p5.rate).toBeLessThan(spaceParams(8).rate)
    expect(p5.rate).toBeCloseTo(0.08 + (0.14 - 0.08) * 0.4, 3)
    expect(spaceParams(0)).toMatchObject({ rate: 0, amp: 0, side: 1, send: 0 })
  })
  it('чем больше D — тем быстрее и больше реверба, без «тошнотворной» скорости', () => {
    let prev = spaceParams(1)
    for (let d = 2; d <= 16; d++) {
      const p = spaceParams(d)
      expect(p.rate).toBeGreaterThanOrEqual(prev.rate)
      expect(p.send).toBeGreaterThanOrEqual(prev.send)
      expect(p.rate).toBeLessThanOrEqual(0.3)
      prev = p
    }
  })
  it('чипы — из таблицы', () => {
    expect([...SPACE_PRESETS]).toEqual(SPACE_TABLE.map(([d]) => d))
  })
  it('подпись и реверб', () => {
    expect(spaceLabel(0)).toBe('')
    expect(spaceLabel(8)).toBe('8D')
    expect(withSpaceReverb(0, 0)).toBe(0)
    expect(withSpaceReverb(0, 8)).toBe(0.22)
    expect(withSpaceReverb(0.5, 16)).toBe(0.7)
    expect(withSpaceReverb(1, 16)).toBe(1)
  })
})

/** Процессор из строки — с заглушками AudioWorklet. */
function makeProcessor(sr = 48000) {
  let Cls: any = null
  class Base {
    port: { onmessage: ((e: { data: unknown }) => void) | null } = { onmessage: null }
  }
  new Function('AudioWorkletProcessor', 'registerProcessor', 'sampleRate', SPACE_WORKLET)(
    Base,
    (_: string, c: unknown) => (Cls = c),
    sr,
  )
  const p = new Cls()
  return {
    send: (on: boolean, d: number) => p.port.onmessage({ data: { on, p: spaceParams(d) } }),
    run(l: Float32Array, r: Float32Array) {
      const out = [new Float32Array(l.length), new Float32Array(l.length)]
      for (let i = 0; i < l.length; i += 128) {
        const o = [out[0].subarray(i, i + 128), out[1].subarray(i, i + 128)]
        p.process([[l.subarray(i, i + 128), r.subarray(i, i + 128)]], [o])
      }
      return out
    },
  }
}

const tone = (n: number, f: number, sr = 48000, phase = 0) => Float32Array.from({ length: n }, (_, i) => 0.5 * Math.sin((2 * Math.PI * f * i) / sr + phase))
const rms = (a: Float32Array) => Math.sqrt(a.reduce((s, x) => s + x * x, 0) / a.length)

describe('процессор пространства', () => {
  it('выключено — сигнал как есть, байт в байт', () => {
    const p = makeProcessor()
    const l = tone(1024, 440)
    const r = tone(1024, 660)
    const [ol, or] = p.run(l, r)
    expect(ol).toEqual(l)
    expect(or).toEqual(r)
  })
  it('8D: звук гуляет между ушами, громкость не прыгает', () => {
    const p = makeProcessor()
    p.send(true, 8)
    const n = 48000 * 8
    const l = tone(n, 300)
    const [ol, or] = p.run(l, l)
    expect(ol.every(Number.isFinite) && or.every(Number.isFinite)).toBe(true)
    // по полсекунды: где-то левое ухо заметно громче правого, где-то наоборот
    const win = 24000
    let leftLouder = false
    let rightLouder = false
    for (let i = win; i + win <= n; i += win) {
      const a = rms(ol.subarray(i, i + win))
      const b = rms(or.subarray(i, i + win))
      if (a > b * 1.4) leftLouder = true
      if (b > a * 1.4) rightLouder = true
    }
    expect(leftLouder && rightLouder).toBe(true)
    // общая громкость — в пределах ±3 дБ от исходной
    const before = rms(l) * Math.SQRT2
    const after = Math.sqrt(rms(ol.subarray(win)) ** 2 + rms(or.subarray(win)) ** 2)
    expect(Math.abs(20 * Math.log10(after / before))).toBeLessThan(3)
    expect(ol.every((x) => Math.abs(x) < 1) && or.every((x) => Math.abs(x) < 1)).toBe(true)
  })
  it('ни на одном D громкость не уходит дальше ±3 дБ', () => {
    for (const d of SPACE_PRESETS) {
      const p = makeProcessor()
      p.send(true, d)
      const n = 48000 * 6
      // «запись»: общий тон посередине + немного своего в каждом канале
      const l = tone(n, 300).map((x, i) => x + 0.15 * Math.sin(i * 0.091))
      const r = tone(n, 300).map((x, i) => x + 0.15 * Math.sin(i * 0.037))
      const [ol, or] = p.run(l, r)
      const before = Math.hypot(rms(l), rms(r))
      const after = Math.hypot(rms(ol.subarray(24000)), rms(or.subarray(24000)))
      expect(Math.abs(20 * Math.log10(after / before)), `${d}D`).toBeLessThan(3)
    }
  })
  it('включение плавное: без скачка на первом сэмпле', () => {
    const p = makeProcessor()
    const l = tone(4800, 200)
    const r = tone(4800, 200, 48000, 1)
    p.send(true, 16)
    const [ol] = p.run(l, r)
    // первые сэмплы почти не отличаются от сухого сигнала
    for (let i = 0; i < 64; i++) expect(Math.abs(ol[i] - l[i])).toBeLessThan(0.02)
  })
  it('выключили — через ~полсекунды снова сухой сигнал', () => {
    const p = makeProcessor()
    p.send(true, 12)
    p.run(tone(48000, 300), tone(48000, 300))
    p.send(false, 0)
    const l = tone(48000, 300)
    const [ol] = p.run(l, l)
    expect(ol.subarray(40000)).toEqual(l.subarray(40000))
  })
})
