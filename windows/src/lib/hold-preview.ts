// «Удержи, чтобы послушать»: пока кнопка зажата дольше `delay` — звучит предпросмотр (`onhold`), отпустил —
// всё возвращается (`onrelease`), а клик, которым закончилось удержание, съедается: пресет не применяется.
// Короткий клик проходит как обычно. Эквалайзер: пресет по удержанию (`player/EqButton.svelte`).

export interface HoldOptions {
  /** Сколько держать до предпросмотра, мс. */
  delay?: number
  onhold: () => void
  onrelease: () => void
}

export const HOLD_DELAY = 350

/** Ядро без DOM: таймеры подаются снаружи, чтобы проверять тестами. */
export class HoldGate {
  /** Удержание состоялось — ближайший клик съедается. */
  held = false
  /** Предпросмотр звучит сейчас. */
  private peeking = false
  private timer: ReturnType<typeof setTimeout> | null = null

  constructor(
    private opts: HoldOptions,
    private timers: { set: typeof setTimeout; clear: typeof clearTimeout } = { set: setTimeout, clear: clearTimeout },
  ) {}

  update(opts: HoldOptions) {
    this.opts = opts
  }

  down() {
    this.stop()
    this.held = false
    this.timer = this.timers.set(() => {
      this.timer = null
      this.held = true
      this.peeking = true
      this.opts.onhold()
    }, this.opts.delay ?? HOLD_DELAY)
  }

  /** Отпустил, ушёл с кнопки или отменили касание. */
  up() {
    this.stop()
    // отпускание и уход с кнопки приходят подряд — возвращаем звук один раз
    if (this.peeking) {
      this.peeking = false
      this.opts.onrelease()
    }
  }

  /** Клик после удержания не считается нажатием. Вернёт `true` один раз. */
  consumeClick(): boolean {
    const h = this.held
    this.held = false
    return h
  }

  private stop() {
    if (this.timer !== null) this.timers.clear(this.timer)
    this.timer = null
  }
}

/** Действие Svelte: `use:holdPreview={{ onhold, onrelease }}`. */
export function holdPreview(node: HTMLElement, options: HoldOptions) {
  const gate = new HoldGate(options)
  const down = (e: PointerEvent) => {
    if (e.button === 0) gate.down()
  }
  const up = () => gate.up()
  const click = (e: Event) => {
    if (gate.consumeClick()) {
      e.stopPropagation()
      e.preventDefault()
    }
  }
  node.addEventListener('pointerdown', down)
  node.addEventListener('pointerup', up)
  node.addEventListener('pointercancel', up)
  node.addEventListener('pointerleave', up)
  node.addEventListener('click', click, true)
  return {
    update: (o: HoldOptions) => gate.update(o),
    destroy() {
      gate.up()
      node.removeEventListener('pointerdown', down)
      node.removeEventListener('pointerup', up)
      node.removeEventListener('pointercancel', up)
      node.removeEventListener('pointerleave', up)
      node.removeEventListener('click', click, true)
    },
  }
}
