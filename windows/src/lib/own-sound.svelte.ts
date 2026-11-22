// Какие треки со своим звуком («Для этого трека») — значок в списках треков (`TrackRow`). Грузится
// одним запросом (`track_sound_refs`), а не по треку; дальше правится на месте, когда трек получает
// или теряет свой звук (`tempo`).
// shortcut: звук, приехавший синком с другого устройства, появится в списках после перезапуска —
// синк не шлёт событий в интерфейс; когда начнёт, здесь достаточно позвать `reload()`.
import { api } from './api'

class OwnSound {
  refs = $state<ReadonlySet<string>>(new Set())
  private loading: Promise<void> | null = null

  /** Один раз за запуск; повторные вызовы ждут тот же запрос. */
  load(): Promise<void> {
    this.loading ??= this.reload()
    return this.loading
  }

  async reload(): Promise<void> {
    try {
      this.refs = new Set(await api.trackSoundRefs())
    } catch {
      // без значка в списках жить можно: звук трека всё равно играет, а следующая правка его отметит
    }
  }

  mark(ref: string, on: boolean) {
    if (this.refs.has(ref) === on) return
    const next = new Set(this.refs)
    if (on) next.add(ref)
    else next.delete(ref)
    this.refs = next
  }
}

export const ownSound = new OwnSound()
