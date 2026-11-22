// Обрезает CC0-сэмплы VCSL (samples/*.wav) до коротких моно-WAV 32 кГц и кладёт их base64 в samples.js,
// чтобы страница с вариантами работала из file:// без сервера.
import fs from 'node:fs'
import path from 'node:path'

const dir = path.resolve(process.argv[2] ?? 'samples')
const OUT_RATE = 32000
const LEN = { BDrum: 0.7, glass: 2.4, windchimes: 3.2 }
const DEFAULT_LEN = 3.2

function readWav(buf) {
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
  return { rate: fmt.rate, mono }
}

function pack(name) {
  const { rate, mono } = readWav(fs.readFileSync(path.join(dir, name)))
  let peak = 0
  for (const v of mono) peak = Math.max(peak, Math.abs(v))
  let start = mono.findIndex((v) => Math.abs(v) > peak * 0.02)
  start = Math.max(0, start - Math.round(rate * 0.003))         // 3 мс до атаки
  const key = Object.keys(LEN).find((k) => name.startsWith(k))
  const n = Math.round((key ? LEN[key] : DEFAULT_LEN) * OUT_RATE)
  const pcm = Buffer.alloc(n * 2)
  for (let i = 0; i < n; i++) {
    const x = start + (i * rate) / OUT_RATE, i0 = Math.floor(x), fr = x - i0
    let v = ((mono[i0] ?? 0) * (1 - fr) + (mono[i0 + 1] ?? 0) * fr) / peak * 0.9
    const tail = n - i, fade = Math.round(OUT_RATE * 0.4)
    if (tail < fade) v *= tail / fade                             // мягкий хвост, без щелчка
    pcm.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(v * 32767))), i * 2)
  }
  const h = Buffer.alloc(44)
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVEfmt ', 8)
  h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22)
  h.writeUInt32LE(OUT_RATE, 24); h.writeUInt32LE(OUT_RATE * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34)
  h.write('data', 36); h.writeUInt32LE(pcm.length, 40)
  return Buffer.concat([h, pcm]).toString('base64')
}

const files = fs.readdirSync(dir).filter((f) => f.endsWith('.wav'))
const out = Object.fromEntries(files.map((f) => [f.replace(/\.wav$/, ''), pack(f)]))
fs.writeFileSync(path.join(dir, '..', 'samples.js'),
  '// CC0 — Versilian Community Sample Library (github.com/sgossner/VCSL)\nwindow.SAMPLES = ' + JSON.stringify(out) + '\n')
console.log(files.length, 'files,', Math.round(fs.statSync(path.join(dir, '..', 'samples.js')).size / 1024), 'KB')
