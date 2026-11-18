// Правая панель «Очередь / Текст» (идея владельца 2026-11-18): крайняя кнопка мини-плеера открывает её на
// пол-экрана справа. Текста нет — очередь; текст найден — кнопка «Т», панель с текстом, внизу «Т» переключает
// на очередь и обратно. Полноэкранный плеер — по клику на обложку мини-плеера.
export type PaneMode = 'queue' | 'lyrics'

class SidePane {
  open = $state(false)
  mode = $state<PaneMode>('queue')

  /** Кнопка мини-плеера: та же панель в том же виде — закрыть, иначе открыть нужный вид. */
  toggle(mode: PaneMode) {
    if (this.open && this.mode === mode) this.open = false
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
