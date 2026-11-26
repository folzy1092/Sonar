// Очередь дозаполнения обложек и длительностей (docs/NOW_ACCURACY_PROMPT.md §2): одна на всё приложение,
// пачки по 20 с паузой, текущий трек — вперёд. Найденное Rust сам кладёт в кэш `tracks` (лайкнутые — в синк),
// а экраны подписываются и вливают свежие карточки в свои списки через `mergeMissing`.
// Правила — `track-backfill.ts`, на iPhone — `ios/Sonar/Core/Library/TrackBackfill.swift`.
import { api, type Track } from './api'
import { offline } from './offline.svelte'
import { BATCH_PAUSE_MS, BATCH_SIZE, planQueue, settledRefs } from './track-backfill'

type Card = Parameters<typeof planQueue>[0][number]
type Listener = (fresh: readonly Track[]) => void

const sleep = (ms: number) => new Promise<void>((done) => setTimeout(done, ms))

class TrackBackfill {
  /** Спрошено и отвечено — до перезапуска не спрашиваем снова. */
  private settled = new Set<string>()
  private inflight = new Set<string>()
  private queue: string[] = []
  private running = false
  private listeners = new Set<Listener>()

  /** Подписка на свежие карточки; вернёт отписку. */
  subscribe(fn: Listener): () => void {
    this.listeners.add(fn)
    return () => this.listeners.delete(fn)
  }

  /** Поставить в очередь недозаполненные треки списка; `current` — вперёд всех. */
  enqueue(tracks: readonly Card[], current?: Card | null): void {
    if (offline.on) return
    const skip = new Set([...this.settled, ...this.inflight])
    const plan = planQueue(tracks, { current, skip })
    if (!plan.length) return
    const planned = new Set(plan)
    this.queue = current
      ? [...plan, ...this.queue.filter((r) => !planned.has(r))]
      : [...this.queue, ...plan.filter((r) => !this.queue.includes(r))]
    void this.run()
  }

  private async run(): Promise<void> {
    if (this.running) return
    this.running = true
    try {
      while (this.queue.length && !offline.on) {
        const batch = this.queue.slice(0, BATCH_SIZE)
        this.queue = this.queue.slice(BATCH_SIZE)
        if (!(await this.ask(batch))) break
        if (this.queue.length) await sleep(BATCH_PAUSE_MS)
      }
    } finally {
      this.running = false
    }
  }

  /** Одна пачка; `false` — вызов упал целиком (офлайн, сбой), остаток очереди бросаем до следующего захода. */
  private async ask(batch: string[]): Promise<boolean> {
    batch.forEach((r) => this.inflight.add(r))
    try {
      const { tracks, failed } = await api.fillTracks(batch)
      settledRefs(batch, failed).forEach((r) => this.settled.add(r))
      if (tracks.length) this.listeners.forEach((fn) => fn(tracks))
      return true
    } catch (e) {
      console.warn('дозаполнение треков не удалось', e)
      this.queue = []
      return false
    } finally {
      batch.forEach((r) => this.inflight.delete(r))
    }
  }
}

export const trackBackfill = new TrackBackfill()
