// Окно подтверждения по центру экрана (затемнение + размытие, как у настроек) — для необратимого:
// «Очистить Любимые» и т.п. Одно на окно. `ask` ждёт ответа: true — «Да», false — «Нет», Esc, клик мимо.
// `delay` — сколько секунд «Да» недоступна (обратный отсчёт на кнопке).

export interface ConfirmAsk {
  title: string
  text?: string
  yes: string
  no: string
  danger?: boolean
  delay?: number
}

class Confirm {
  current = $state<(ConfirmAsk & { id: number }) | null>(null)
  private resolve: ((v: boolean) => void) | null = null
  private seq = 0

  ask(q: ConfirmAsk): Promise<boolean> {
    this.answer(false)
    this.current = { ...q, id: ++this.seq }
    return new Promise((r) => (this.resolve = r))
  }

  answer(v: boolean) {
    const r = this.resolve
    this.resolve = null
    this.current = null
    r?.(v)
  }
}

export const confirm = new Confirm()
