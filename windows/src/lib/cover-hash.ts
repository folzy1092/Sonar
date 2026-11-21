// Повторы в коллаже по самой картинке (docs/POLISH_PROMPT.md п. 1, «сравнение по пикселям»): на
// SoundCloud одну и ту же обложку часто заливают к каждому треку отдельно — адреса разные, картинка
// одна, и в сетке 2×2 выходят две одинаковые. Отпечаток — dHash 8×8 (яркость 9×8, соседи слева
// направо), похожие отпечатки — повтор. Картинку читаем через локальный `/cover` (CORS и кэш на
// диске), отпечатки помним в памяти и в localStorage — каждую обложку хэшируем один раз.
import { COLLAGE_SIZE, coverKey, distinctCovers, type CoverSource } from './covers'

/** Сколько бит из 64 могут разниться у «той же» картинки (пережатие, другой размер, рамка). */
export const SAME_MAX_BITS = 6
/** Сколько разных по адресу обложек смотрим, чтобы набрать четыре разных по картинке. */
const LOOKAHEAD = 16
const STORE_KEY = 'sonar.cover-hash'
const STORE_MAX = 1500

/** dHash из яркостей 9×8 (по строкам): бит — «левый пиксель ярче правого». 16 hex-символов. */
export function dHash(gray: ArrayLike<number>): string {
  let out = ''
  for (let row = 0; row < 8; row++) {
    let nibble = 0
    for (let col = 0; col < 8; col++) {
      const bit = gray[row * 9 + col] > gray[row * 9 + col + 1] ? 1 : 0
      nibble = (nibble << 1) | bit
      if (col % 4 === 3) {
        out += nibble.toString(16)
        nibble = 0
      }
    }
  }
  return out
}

/** Сколько бит различается у двух отпечатков. */
export function hamming(a: string, b: string): number {
  let n = 0
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    let x = parseInt(a[i], 16) ^ parseInt(b[i], 16)
    while (x) {
      n += x & 1
      x >>= 1
    }
  }
  return n
}

/** Однотонная картинка (заглушка, сплошной цвет) — отпечаток из нулей; такие сравнивать нельзя:
 *  у любых двух однотонных он одинаковый, хотя цвета разные. */
const flat = (h: string) => /^0+$/.test(h)

/** По порядку списка — до `n` обложек, у которых картинки не повторяются. Нет отпечатка — считаем разной. */
export function pickByHash(urls: readonly string[], hashOf: (url: string) => string | null, n = COLLAGE_SIZE): string[] {
  const out: string[] = []
  const seen: string[] = []
  for (const url of urls) {
    if (out.length >= n) break
    const h = hashOf(url)
    if (h && !flat(h) && seen.some((s) => hamming(s, h) <= SAME_MAX_BITS)) continue
    if (h && !flat(h)) seen.push(h)
    out.push(url)
  }
  return out
}

const memory = new Map<string, string>()
const pending = new Map<string, Promise<string | null>>()
let loaded = false

function loadStore() {
  if (loaded) return
  loaded = true
  try {
    const raw = JSON.parse(localStorage.getItem(STORE_KEY) ?? '{}') as Record<string, string>
    for (const [k, v] of Object.entries(raw)) if (typeof v === 'string' && /^[0-9a-f]{16}$/.test(v)) memory.set(k, v)
  } catch {
    // битый кэш — просто посчитаем заново
  }
}

let saveTimer: ReturnType<typeof setTimeout> | undefined
function saveStore() {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(() => {
    try {
      const entries = [...memory.entries()].slice(-STORE_MAX)
      localStorage.setItem(STORE_KEY, JSON.stringify(Object.fromEntries(entries)))
    } catch {
      // нет места — живём с памятью
    }
  }, 1000)
}

/** Отпечаток обложки (null — не прочиталась). `src` — откуда читать пиксели (с CORS). */
export function hashCover(url: string, src: (url: string) => Promise<string>): Promise<string | null> {
  loadStore()
  const key = coverKey(url)
  const known = memory.get(key)
  if (known) return Promise.resolve(known)
  const running = pending.get(key)
  if (running) return running
  const job = (async () => {
    try {
      const img = new Image()
      img.crossOrigin = 'anonymous'
      img.decoding = 'async'
      img.src = await src(url)
      await img.decode()
      const canvas = document.createElement('canvas')
      canvas.width = 9
      canvas.height = 8
      const ctx = canvas.getContext('2d', { willReadFrequently: true })
      if (!ctx) return null
      ctx.drawImage(img, 0, 0, 9, 8)
      const rgba = ctx.getImageData(0, 0, 9, 8).data
      const gray = new Float32Array(72)
      for (let i = 0; i < 72; i++) gray[i] = 0.299 * rgba[i * 4] + 0.587 * rgba[i * 4 + 1] + 0.114 * rgba[i * 4 + 2]
      const h = dHash(gray)
      memory.delete(key)
      memory.set(key, h)
      saveStore()
      return h
    } catch {
      return null
    } finally {
      pending.delete(key)
    }
  })()
  pending.set(key, job)
  return job
}

/** Коллаж без повторов по картинке: 4 разные — сетка, иначе одна первая, или пусто (как `collage`). */
export async function collageByPixels(tracks: readonly CoverSource[], src: (url: string) => Promise<string>): Promise<string[]> {
  const urls = distinctCovers(tracks, LOOKAHEAD)
  const hashes = await Promise.all(urls.map((u) => hashCover(u, src)))
  const byUrl = new Map(urls.map((u, i) => [u, hashes[i]] as const))
  const covers = pickByHash(urls, (u) => byUrl.get(u) ?? null)
  return covers.length >= COLLAGE_SIZE ? covers : covers.slice(0, 1)
}
