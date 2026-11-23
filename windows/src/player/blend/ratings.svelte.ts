// Оценки переходов (docs/BLEND.md §8.6): после каждого перехода 60 с висит «Как прошлый переход?» 👍/👎
// в кнопке сведения и в карточке отладки. Ответ — в `blend_ratings` (Rust), перевес по видам за 60 дней
// уходит в настройки плана (`currentBlendSettings`), и «Авто» реже берёт вид с минусом.

import { untrack } from 'svelte'
import { api } from '../../lib/api'
import type { BlendKind } from './planner'

/** Сколько висит вопрос после перехода. */
export const RATE_WINDOW_MS = 60_000
/** За какой срок считается перевес. */
export const RATE_DAYS = 60
const DAY_MS = 86_400_000

export interface DoneTransition {
  from: { ref: string }
  to: { ref: string }
  kind: BlendKind
}

class BlendRatings {
  /** Перевес по видам, −1…1; вида без оценок нет. */
  balance = $state.raw<Partial<Record<BlendKind, number>>>({})
  /** Переход, который сейчас просим оценить; `null` — вопроса нет. */
  ask = $state.raw<DoneTransition | null>(null)
  /** Что ответили на текущий вопрос. */
  answer = $state<1 | -1 | null>(null)
  #timer: ReturnType<typeof setTimeout> | null = null
  #started = false

  /** `done` — последний доведённый переход контроллера (`player.blend.done`). */
  init(done: () => DoneTransition | null) {
    if (this.#started) return
    this.#started = true
    void this.load()
    $effect.root(() => {
      $effect(() => {
        const d = done()
        if (d) untrack(() => this.open(d))
      })
    })
  }

  /** Новый переход — новый вопрос на {@link RATE_WINDOW_MS}. */
  open(d: DoneTransition) {
    if (this.#timer) clearTimeout(this.#timer)
    this.ask = d
    this.answer = null
    this.#timer = setTimeout(() => this.close(), RATE_WINDOW_MS)
  }

  close() {
    if (this.#timer) clearTimeout(this.#timer)
    this.#timer = null
    this.ask = null
    this.answer = null
  }

  /** Ответ на текущий вопрос; второй ответ на тот же переход не пишется. */
  async rate(score: 1 | -1) {
    const d = this.ask
    if (!d || this.answer !== null) return
    this.answer = score
    try {
      await api.blendRate(d.from.ref, d.to.ref, d.kind, score)
    } catch (e) {
      // не записалось — даём ответить ещё раз
      if (this.ask === d) this.answer = null
      console.warn('сведение: оценка перехода не записалась', e)
      return
    }
    await this.load()
  }

  async load() {
    try {
      this.balance = await api.blendBalance(Date.now() - RATE_DAYS * DAY_MS)
    } catch (e) {
      // без перевеса «Авто» просто выбирает как без оценок
      console.warn('сведение: оценки переходов не прочитались', e)
    }
  }
}

export const blendRatings = new BlendRatings()
