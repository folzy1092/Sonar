// Сводит звук заставки — аккорд рояля в такт двум волнам сонар-поля (index.html) — в один файл
// public/splash-chord.wav (22 кГц, стерео, ~2 с). Источник — записи рояля Kawai из VCSL
// (Versilian Community Sample Library, CC0, github.com/sgossner/VCSL,
// «Chordophones/Zithers/Grand Piano, Kawai/Sustains/GPiano_sus_<нота>_…_Player.wav»).
// Запуск: node scripts/gen-splash-sound.mjs <папка с этими WAV>  (по умолчанию ../design/splash/samples)
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const src = path.resolve(process.argv[2] ?? path.join(here, '../../design/splash/samples'))
const out = path.join(here, '../public/splash-chord.wav')
const RATE = 22050
const LENGTH = 2.0

// первая волна — нижний аккорд, вторая (через 240 мс) — ответ сверху; пары нот чуть «рукой», с разбежкой
const NOTES = [
  { file: 'GPiano_sus_E3_v1_rr1_Player.wav', at: 0, gain: 0.55, pan: -0.15 },
  { file: 'GPiano_sus_B4_v3_rr1_Player.wav', at: 0.018, gain: 0.28, pan: 0.15 },
  { file: 'GPiano_sus_D4_v1_rr1_Player.wav', at: 0.24, gain: 0.3, pan: 0 },
  { file: 'GPiano_sus_E4_v1_rr1_Player.wav', at: 0.258, gain: 0.24, pan: 0.2 },
]
const HOLD = 0.75, TAU = 0.225 // нота держится 0,75 с, потом гаснет (к 1,5 с ≈ −30 дБ)
const SEND = 0.45, WET = 0.28, IR_SEC = 1.4

function readWav(file) {
  const buf = fs.readFileSync(file)
  let off = 12, fmt, data
  while (off < buf.length - 8) {
    const id = buf.toString('ascii', off, off + 4), size = buf.readUInt32LE(off + 4)
    if (id === 'fmt ') fmt = { ch: buf.readUInt16LE(off + 10), rate: buf.readUInt32LE(off + 12), bits: buf.readUInt16LE(off + 22) }
    if (id === 'data') data = buf.subarray(off + 8, off + 8 + size)
    off += 8 + size + (size & 1)
  }
  const bps = fmt.bits / 8, frames = Math.floor(data.length / (bps * fmt.ch)), mono = new Float32Array(frames)
  for (let i = 0; i < frames; i++) {
    let s = 0
    for (let c = 0; c < fmt.ch; c++) {
      const p = (i * fmt.ch + c) * bps
      s += fmt.bits === 16 ? data.readInt16LE(p) / 32768 : data.readIntLE(p, 3) / 8388608
    }
    mono[i] = s / fmt.ch
  }
  // с атаки (за 3 мс до неё), нормировано по пику
  let peak = 0
  for (const v of mono) peak = Math.max(peak, Math.abs(v))
  const start = Math.max(0, mono.findIndex((v) => Math.abs(v) > peak * 0.02) - Math.round(fmt.rate * 0.003))
  return { rate: fmt.rate, x: mono.subarray(start), peak }
}

// двухполюсный ФНЧ (как BiquadFilter lowpass, Q = 0.707)
function lowpass(x, f) {
  const w = (2 * Math.PI * f) / RATE, a = Math.sin(w) / (2 * Math.SQRT1_2), c = Math.cos(w)
  const b0 = (1 - c) / 2 / (1 + a), b1 = (1 - c) / (1 + a), a1 = (-2 * c) / (1 + a), a2 = (1 - a) / (1 + a)
  const y = new Float32Array(x.length)
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0
  for (let i = 0; i < x.length; i++) {
    const v = b0 * x[i] + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2
    x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v
  }
  return y
}

const N = Math.round(LENGTH * RATE)
const dry = [new Float32Array(N), new Float32Array(N)]
for (const n of NOTES) {
  const { rate, x, peak } = readWav(path.join(src, n.file))
  const mono = new Float32Array(N)
  for (let i = 0; i < N; i++) {
    const t = i / RATE - n.at
    if (t < 0) continue
    const xi = t * rate, i0 = Math.floor(xi), fr = xi - i0
    if (i0 + 1 >= x.length) break
    const env = t < HOLD ? 1 : Math.exp(-(t - HOLD) / TAU)
    mono[i] = ((x[i0] * (1 - fr) + x[i0 + 1] * fr) / peak) * 0.9 * n.gain * env
  }
  const f = lowpass(mono, 2600), p = ((n.pan + 1) / 2) * (Math.PI / 2)
  for (let i = 0; i < N; i++) { dry[0][i] += f[i] * Math.cos(p); dry[1][i] += f[i] * Math.sin(p) }
}

// небольшой зал: стерео-шум с экспоненциальным спадом, предзадержка 18 мс (повторяемый — свой генератор)
let seed = 7
const rnd = () => ((seed = (seed * 1103515245 + 12345) >>> 0) / 2 ** 32) * 2 - 1
const irLen = Math.round(IR_SEC * RATE), pre = Math.round(0.018 * RATE)
const wet = dry.map((ch) => {
  const ir = new Float32Array(irLen)
  for (let i = pre; i < irLen; i++) ir[i] = rnd() * Math.exp((-6.5 * (i - pre)) / irLen)
  const y = new Float32Array(N)
  for (let i = 0; i < N; i++) {
    const v = ch[i] * SEND
    if (!v) continue
    for (let k = 0, m = Math.min(irLen, N - i); k < m; k++) y[i + k] += v * ir[k]
  }
  // Web Audio нормирует импульс свёртки; здесь — тем же порядком величины
  const norm = 1 / Math.sqrt(ir.reduce((s, v) => s + v * v, 0))
  return lowpass(y.map((v) => v * norm), 3800).map((v) => v * WET)
})

const mix = [0, 1].map((c) => dry[c].map((v, i) => v + wet[c][i]))
let peak = 0
for (const ch of mix) for (const v of ch) peak = Math.max(peak, Math.abs(v))
const fade = Math.round(0.3 * RATE)
const pcm = Buffer.alloc(N * 4)
for (let i = 0; i < N; i++) {
  const g = (0.8 / peak) * (i > N - fade ? (N - i) / fade : 1)
  for (let c = 0; c < 2; c++) pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mix[c][i] * g)) * 32767), i * 4 + c * 2)
}
const h = Buffer.alloc(44)
h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVEfmt ', 8)
h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(2, 22)
h.writeUInt32LE(RATE, 24); h.writeUInt32LE(RATE * 4, 28); h.writeUInt16LE(4, 32); h.writeUInt16LE(16, 34)
h.write('data', 36); h.writeUInt32LE(pcm.length, 40)
fs.writeFileSync(out, Buffer.concat([h, pcm]))
console.log(`${path.relative(process.cwd(), out)}: ${Math.round((44 + pcm.length) / 1024)} КБ`)
