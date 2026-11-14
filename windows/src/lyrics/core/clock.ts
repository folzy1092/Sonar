// Часы плеера для текста (LYRICS.md §2): не дёргаются от редкого timeupdate, идут плавно между
// событиями <audio>, не откатываются назад между кадрами (кроме явной перемотки).

/** Расхождение больше — жёсткий перенос якоря, меньше — мягкая подстройка. */
export const HARD_SYNC = 0.35
const SOFT = 0.25

export class Clock {
  anchorTime = 0
  anchorTs = 0
  rate = 1
  last = 0
  mode: 'running' | 'raw' = 'raw'
  /** Время <audio> на последнем событии — им живёт режим `raw`. */
  raw = 0
  duration = Infinity

  /** Секунды трека на момент `ts` (performance.now()), без монотонности. */
  now(ts: number): number {
    if (this.mode === 'raw') return this.raw
    return this.anchorTime + ((ts - this.anchorTs) / 1000) * this.rate
  }

  private anchor(time: number, ts: number) {
    this.anchorTime = time
    this.anchorTs = ts
  }

  /** На каждом timeupdate. */
  sample(audioTime: number, ts: number) {
    this.raw = audioTime
    if (this.mode === 'raw') return
    const diff = audioTime - this.now(ts)
    if (Math.abs(diff) > HARD_SYNC) this.anchor(audioTime, ts)
    else this.anchor(this.now(ts) + diff * SOFT, ts)
  }

  /** `playing`: новый якорь, часы идут. */
  play(audioTime: number, ts: number, rate = this.rate) {
    this.raw = audioTime
    this.rate = rate
    this.anchor(audioTime, ts)
    this.mode = 'running'
  }

  /** `pause`, `waiting`: стоим на времени <audio>. */
  hold(audioTime: number) {
    this.raw = audioTime
    this.mode = 'raw'
  }

  /** `seeking`: стоим и разрешаем откат назад. */
  seek(audioTime: number) {
    this.hold(audioTime)
    this.last = 0
  }

  /** `ratechange`: новый якорь с новой скоростью. */
  setRate(rate: number, audioTime: number, ts: number) {
    this.rate = rate
    this.raw = audioTime
    if (this.mode === 'running') this.anchor(audioTime, ts)
  }

  /** Время для кадра: монотонно и в пределах трека. */
  read(ts: number): number {
    let t = Math.max(this.now(ts), this.last)
    t = Math.min(Math.max(t, 0), this.duration)
    this.last = t
    return t
  }
}
