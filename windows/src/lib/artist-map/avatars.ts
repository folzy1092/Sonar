// Аватарки для карты: грузятся только для видимых кругов, не больше нескольких сразу, и один раз
// вырезаются в круг на маленьком холсте — дальше рисуются одним drawImage без клипа на каждом кадре.

/** Сторона заготовки в пикселях: хватает на крупный круг при приближении на ретине. */
const SIZE = 128
/** Одновременных загрузок. */
const PARALLEL = 6
/** Сколько заготовок держим; дальше выбрасываем самые старые. */
const KEEP = 600

type Entry = { state: 'loading' } | { state: 'ready'; img: HTMLCanvasElement } | { state: 'failed' }

export class AvatarCache {
  private entries = new Map<string, Entry>()
  private queue: string[] = []
  private active = 0

  constructor(private onReady: () => void) {}

  /** Готовая круглая заготовка или `null` (тогда рисуем букву); заодно ставит в очередь. */
  get(url: string | null): HTMLCanvasElement | null {
    if (!url) return null
    const e = this.entries.get(url)
    if (e?.state === 'ready') return e.img
    if (!e) this.enqueue(url)
    return null
  }

  private enqueue(url: string) {
    this.entries.set(url, { state: 'loading' })
    this.queue.push(url)
    this.pump()
  }

  private pump() {
    while (this.active < PARALLEL && this.queue.length) {
      const url = this.queue.shift()!
      this.active++
      void this.load(url).finally(() => {
        this.active--
        this.pump()
      })
    }
  }

  private async load(url: string) {
    try {
      const img = new Image()
      img.decoding = 'async'
      img.referrerPolicy = 'no-referrer'
      img.src = url
      await img.decode()
      this.entries.set(url, { state: 'ready', img: cutCircle(img) })
      this.trim()
      this.onReady()
    } catch {
      // нет картинки или битый адрес — останется буква, повторно не грузим
      this.entries.set(url, { state: 'failed' })
    }
  }

  private trim() {
    if (this.entries.size <= KEEP) return
    for (const key of this.entries.keys()) {
      if (this.entries.size <= KEEP) break
      if (this.entries.get(key)?.state !== 'loading') this.entries.delete(key)
    }
  }

  /** Всё забыть (карта закрыта): очередь стоит, готовое отпускаем. */
  clear() {
    this.queue = []
    this.entries.clear()
  }
}

/** Картинка, вписанная в круг по центру (как object-fit: cover). */
function cutCircle(img: HTMLImageElement): HTMLCanvasElement {
  const c = document.createElement('canvas')
  c.width = SIZE
  c.height = SIZE
  const ctx = c.getContext('2d')
  if (!ctx) return c
  const side = Math.min(img.naturalWidth, img.naturalHeight) || 1
  const sx = (img.naturalWidth - side) / 2
  const sy = (img.naturalHeight - side) / 2
  ctx.beginPath()
  ctx.arc(SIZE / 2, SIZE / 2, SIZE / 2, 0, Math.PI * 2)
  ctx.clip()
  ctx.drawImage(img, sx, sy, side, side, 0, 0, SIZE, SIZE)
  return c
}
