// Короткое сообщение внизу окна («Добавлено в плейлист», ошибки). Показывает app/Toast.svelte.
// С `action` — кнопка в тосте («Отменить»): срабатывает один раз, только по клику, тост закрывается.

export interface ToastAction {
  label: string
  run: () => unknown
}

class Toast {
  text = $state<string | null>(null)
  action = $state<ToastAction | null>(null)
  private timer: ReturnType<typeof setTimeout> | null = null

  show(text: string, ms = 2600, action: ToastAction | null = null) {
    this.text = text
    this.action = action
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => this.hide(), ms)
  }

  hide() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
    this.text = null
    this.action = null
  }

  /** Кнопка тоста: закрыть и выполнить действие (один раз). */
  act() {
    const action = this.action
    this.hide()
    void action?.run()
  }
}

export const toast = new Toast()
