// Короткое сообщение внизу окна («Добавлено в плейлист», ошибки). Показывает app/Toast.svelte.
class Toast {
  text = $state<string | null>(null)
  private timer: ReturnType<typeof setTimeout> | null = null

  show(text: string, ms = 2600) {
    this.text = text
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => (this.text = null), ms)
  }
}

export const toast = new Toast()
