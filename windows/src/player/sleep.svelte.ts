// Таймер сна (кнопка-луна на странице плеера): через N минут или в конце трека музыка плавно
// стихает и встаёт на паузу, громкость возвращается. Таймер на setInterval, а не на кадрах —
// окно может быть спрятано в трей. Пауза рукой таймер не снимает, «Выключить» — снимает.
import { player } from './player.svelte'
import { FADE_MS, FADE_TRACK_MS, fadeK } from './sleep-core'

class Sleep {
  /** Когда встать на паузу (мс, Date.now); `null` — таймер не стоит или «до конца трека». */
  endsAt = $state<number | null>(null)
  /** «До конца трека»: пауза, когда доиграет текущий. */
  endOfTrack = $state(false)
  /** Сколько осталось, мс — для подписи на кнопке (обновляется 4 раза в секунду). */
  left = $state(0)
  active = $derived(this.endsAt !== null || this.endOfTrack)

  private timer: ReturnType<typeof setInterval> | null = null
  private trackRef: string | null = null

  start(minutes: number) {
    this.endOfTrack = false
    this.endsAt = Date.now() + minutes * 60_000
    this.run()
  }

  startEndOfTrack() {
    this.endsAt = null
    this.endOfTrack = true
    this.trackRef = player.current?.ref ?? null
    this.run()
  }

  cancel() {
    this.stop()
    player.setSleepFade(1)
  }

  private run() {
    if (this.timer) clearInterval(this.timer)
    this.timer = setInterval(() => this.tick(), 250)
    this.tick()
  }

  private stop() {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    this.endsAt = null
    this.endOfTrack = false
    this.left = 0
  }

  private tick() {
    let left: number
    let fade: number
    if (this.endOfTrack) {
      // трек сменился (кроссфейд или пропуск) — значит, тот доиграл
      if (this.trackRef && player.current?.ref !== this.trackRef) return this.fire()
      const dur = player.durationMs || player.current?.duration_ms || 0
      left = dur ? Math.max(0, dur - player.positionMs) : Infinity
      fade = FADE_TRACK_MS
    } else {
      left = (this.endsAt ?? 0) - Date.now()
      fade = FADE_MS
    }
    this.left = Number.isFinite(left) ? left : 0
    // на паузе громкость не трогаем — затухание пойдёт, когда музыка снова заиграет
    if (player.playing) player.setSleepFade(fadeK(left, fade))
    if (left <= 300) this.fire()
  }

  private fire() {
    this.stop()
    player.pause()
    // громкость вернуть после паузы, чтобы не было щелчка звука
    setTimeout(() => player.setSleepFade(1), 400)
  }
}

export const sleep = new Sleep()
