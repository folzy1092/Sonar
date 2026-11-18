// Правая панель «Очередь / Текст» (идея владельца 2026-11-18): крайняя кнопка мини-плеера открывает её на
// пол-экрана справа. Текста нет — очередь; текст найден — кнопка «Т», панель с текстом, внизу «Т» переключает
// на очередь и обратно. Полноэкранный плеер — по клику на обложку мини-плеера.
export type PaneMode = 'queue' | 'lyrics'

/** Выбранный вид с поправкой на трек без текста. */
export function effectiveMode(mode: PaneMode, hasLyrics: boolean): PaneMode {
  return mode === 'lyrics' && hasLyrics ? 'lyrics' : 'queue'
}

class SidePane {
  open = $state(false)
  mode = $state<PaneMode>('queue')

  /** Что панель показывает на деле: без текста у трека — очередь, даже если выбран текст. */
  shown(hasLyrics: boolean): PaneMode {
    return effectiveMode(this.mode, hasLyrics)
  }

  /** Кнопка мини-плеера: та же панель в том же виде — закрыть, иначе открыть нужный вид. */
  toggle(mode: PaneMode, hasLyrics = true) {
    if (this.open && this.shown(hasLyrics) === mode) this.open = false
    else {
      this.mode = mode
      this.open = true
    }
  }

  close() {
    this.open = false
  }
}

export const sidePane = new SidePane()
