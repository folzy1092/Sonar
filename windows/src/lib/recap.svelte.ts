// Открытые итоги (RecapViewer): какие, загруженные данные, карточки, текущая карточка и цвета из обложки.
import { api, errorText, type Recap } from './api'
import { buildCards, coverOf, markSeen, recapColors, recapId, step, type RecapCard, type RecapColors, type RecapRef } from './recap-core'
import { settings } from './settings.svelte'
import { colorOf } from '../theme/theme.svelte'

class RecapStore {
  ref = $state<RecapRef | null>(null)
  data = $state<Recap | null>(null)
  cards = $state<RecapCard[]>([])
  index = $state(0)
  /** Куда листали последний раз: 1 — вперёд, -1 — назад (направление въезда карточки). */
  dir = $state<1 | -1>(1)
  loading = $state(false)
  error = $state<string | null>(null)
  colors = $state<RecapColors>(recapColors(null))
  /** Номер загрузки: ответ на прошлый запрос не перетирает новый. */
  private seq = 0

  get isOpen(): boolean {
    return this.ref !== null
  }

  /** Открыть итоги; заодно они больше не зовут на Главной. */
  async open(ref: RecapRef): Promise<void> {
    const seq = ++this.seq
    this.ref = ref
    this.data = null
    this.cards = []
    this.index = 0
    this.dir = 1
    this.error = null
    this.loading = true
    this.colors = recapColors(null)
    this.remember(ref)
    try {
      const data = await api.recap(ref.kind, ref.year, ref.month)
      if (seq !== this.seq) return
      this.data = data
      this.cards = buildCards(data)
      const cover = coverOf(data)
      if (cover) void this.paint(cover, seq)
    } catch (e) {
      if (seq === this.seq) this.error = errorText(e)
    } finally {
      if (seq === this.seq) this.loading = false
    }
  }

  private async paint(cover: string, seq: number) {
    const rgb = await colorOf(cover)
    if (seq === this.seq) this.colors = recapColors(rgb)
  }

  close() {
    this.seq++
    this.ref = null
    this.data = null
    this.cards = []
    this.loading = false
  }

  /** Листать на `delta` карточек или к первой / последней. */
  go(move: number | 'first' | 'last') {
    const n = this.cards.length
    const next = move === 'first' ? 0 : move === 'last' ? n - 1 : step(this.index, move, n)
    if (next === this.index || next < 0) return
    this.dir = next > this.index ? 1 : -1
    this.index = next
  }

  /** Закрыть приглашение на Главной, не открывая итоги. */
  dismiss(ref: RecapRef) {
    this.remember(ref)
  }

  /** Запомнить в `stats.recap_seen`: эти итоги больше не зовут на Главной. */
  private remember(ref: RecapRef) {
    settings.set('stats.recap_seen', markSeen(settings.get('stats.recap_seen'), recapId(ref)))
  }
}

export const recap = new RecapStore()
