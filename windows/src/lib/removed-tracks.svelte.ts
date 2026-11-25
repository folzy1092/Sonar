// Треки, которые SoundCloud удалил (HTTP 404 на потоке) — часто по жалобе правообладателя. Пока трек в
// списке, строка (`TrackRow`) честно подписана, чтобы не думали, что сломался Sonar. Помнится на этом
// устройстве (localStorage); если трек снова заиграл — метка снимается.

const KEY = 'sonar.removed_tracks'
const LIMIT = 500

/** Ошибка потока SoundCloud — «трек удалён» (текст `providers::http_error`, 404). */
export function isRemovedError(ref: string, raw: string): boolean {
  return ref.startsWith('sc:') && /^SoundCloud: .+ \(HTTP 404\)$/.test(raw)
}

function read(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(KEY) ?? '[]')
    return Array.isArray(v) ? v.filter((x) => typeof x === 'string') : []
  } catch {
    return []
  }
}

class RemovedTracks {
  refs = $state<ReadonlySet<string>>(new Set(read()))

  mark(ref: string, on: boolean) {
    if (this.refs.has(ref) === on) return
    const next = new Set(this.refs)
    if (on) next.add(ref)
    else next.delete(ref)
    this.refs = next
    try {
      localStorage.setItem(KEY, JSON.stringify([...next].slice(-LIMIT)))
    } catch {
      // без памяти метка живёт до перезапуска — не страшно
    }
  }
}

export const removedTracks = new RemovedTracks()
