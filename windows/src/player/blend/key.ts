// Тональность трека для сведения (docs/BLEND.md §4.3, п. 8): хрома за трек (энергия уже взвешивает
// кадры) и корреляция с профилями Темперли, 24 тональности. `key` 0…11 — мажор (до = 0), 12…23 — минор
// (ля минор = 21). Уверенность — разница лучшей и второй корреляции, умноженная на «чёткость» хромы:
// у шума все классы почти равны, и любая корреляция там случайна.

import { type Frames, frameAt } from './features'

const MAJOR = [5, 2, 3.5, 2, 4.5, 4, 2, 4.5, 2, 3.5, 1.5, 4]
const MINOR = [5, 2, 3.5, 4.5, 2, 4, 2, 4.5, 3.5, 2, 1.5, 4]
/** Ниже — «не знаем». */
export const KEY_CONF_MIN = 0.15
/** Коэффициент вариации хромы, начиная с которого она считается чёткой. */
const CLEAR_CV = 0.5

function pearson(a: number[], b: number[]): number {
  const n = a.length
  const ma = a.reduce((s, x) => s + x, 0) / n
  const mb = b.reduce((s, x) => s + x, 0) / n
  let [ab, aa, bb] = [0, 0, 0]
  for (let i = 0; i < n; i++) {
    ab += (a[i] - ma) * (b[i] - mb)
    aa += (a[i] - ma) ** 2
    bb += (b[i] - mb) ** 2
  }
  return aa > 0 && bb > 0 ? ab / Math.sqrt(aa * bb) : 0
}

/** Профиль, повёрнутый к тонике `tonic`. */
const rotated = (profile: number[], tonic: number) => profile.map((_, i) => profile[(i - tonic + 12) % 12])

/** Тональность по хроме из 12 чисел. */
export function keyOfChroma(chroma: number[]): { key: number | null; keyConf: number } {
  const total = chroma.reduce((s, x) => s + x, 0)
  if (total <= 0) return { key: null, keyConf: 0 }
  const scores: { key: number; r: number }[] = []
  for (let t = 0; t < 12; t++) {
    scores.push({ key: t, r: pearson(chroma, rotated(MAJOR, t)) })
    scores.push({ key: 12 + t, r: pearson(chroma, rotated(MINOR, t)) })
  }
  scores.sort((a, b) => b.r - a.r)
  const mean = total / 12
  const cv = Math.sqrt(chroma.reduce((s, x) => s + (x - mean) ** 2, 0) / 12) / mean
  const keyConf = Math.max(0, Math.min(1, (scores[0].r - scores[1].r) * Math.min(1, cv / CLEAR_CV)))
  return { key: keyConf < KEY_CONF_MIN ? null : scores[0].key, keyConf: Math.round(keyConf * 1000) / 1000 }
}

export function keyOf(f: Frames, startMs: number, endMs: number): { key: number | null; keyConf: number } {
  const chroma = new Array<number>(12).fill(0)
  const a = Math.max(0, Math.round(frameAt(startMs)))
  const b = Math.min(f.count, Math.round(frameAt(endMs)))
  for (let i = a; i < b; i++) for (let c = 0; c < 12; c++) chroma[c] += f.chroma[i * 12 + c]
  return keyOfChroma(chroma)
}
