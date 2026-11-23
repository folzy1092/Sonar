// Очередь анализа сведения (docs/BLEND.md §4.1, §4.5): не больше двух треков одновременно, текущий и
// следующий — раньше пула вечеринки, один трек не считается дважды. Сначала смотрим в базу (готовый анализ
// той же версии), нет — считаем и сохраняем. Не вышло — помним причину до `forgetFailures` (сеть
// вернулась, кэш почистили), чтобы не долбить один и тот же трек на каждом переключении.
// Чистая логика: загрузка, расчёт и сохранение приходят снаружи (`analyze.svelte.ts`, тесты).

import { ANALYSIS_VERSION, type BlendAnalysis } from './analysis'

export const ANALYZE_CONCURRENCY = 2

/** `now` — играет или следующий, `party` — пул «Свести для вечеринки». */
export type AnalyzePriority = 'now' | 'party'

export interface AnalyzeDeps {
  /** Готовые анализы из базы — любой версии, отбор здесь. */
  load(refs: string[]): Promise<Record<string, BlendAnalysis>>
  /** Скачать, декодировать и посчитать. */
  compute(ref: string): Promise<BlendAnalysis>
  save(a: BlendAnalysis): Promise<void>
}

interface Job {
  ref: string
  priority: AnalyzePriority
  promise: Promise<BlendAnalysis | null>
  resolve: (a: BlendAnalysis | null) => void
}

const fresh = (a: BlendAnalysis | undefined): a is BlendAnalysis => a?.version === ANALYSIS_VERSION

export class AnalyzeQueue {
  private readonly ready = new Map<string, BlendAnalysis>()
  private readonly failed = new Map<string, string>()
  private readonly waiting: Job[] = []
  private readonly running = new Map<string, Job>()
  /** Растёт на `reset`: задачи старого поколения результат не записывают. */
  private generation = 0

  constructor(
    private readonly deps: AnalyzeDeps,
    private readonly onChange: () => void = () => {},
    private readonly concurrency = ANALYZE_CONCURRENCY,
  ) {}

  /** Готовый анализ из памяти, без ожидания. */
  peek(ref: string): BlendAnalysis | undefined {
    return this.ready.get(ref)
  }

  /** Почему анализа нет (или `undefined`, если не падал). */
  failure(ref: string): string | undefined {
    return this.failed.get(ref)
  }

  pending(ref: string): boolean {
    return this.running.has(ref) || this.waiting.some((j) => j.ref === ref)
  }

  /** Анализ трека: из памяти, базы или посчитать. `null` — не вышло (причина — `failure`). */
  request(ref: string, priority: AnalyzePriority = 'now'): Promise<BlendAnalysis | null> {
    const hit = this.ready.get(ref)
    if (hit) return Promise.resolve(hit)
    if (this.failed.has(ref)) return Promise.resolve(null)
    const live = this.running.get(ref)
    if (live) return live.promise
    const queued = this.waiting.find((j) => j.ref === ref)
    if (queued) {
      if (priority === 'now' && queued.priority === 'party') this.promote(queued)
      return queued.promise
    }
    let resolve!: Job['resolve']
    const promise = new Promise<BlendAnalysis | null>((r) => (resolve = r))
    const job: Job = { ref, priority, promise, resolve }
    if (priority === 'now') this.waiting.splice(this.firstParty(), 0, job)
    else this.waiting.push(job)
    this.pump()
    return promise
  }

  /** Поднять в память всё, что уже есть в базе (вечеринка: план без ожидания каждого трека). */
  async warm(refs: string[]): Promise<void> {
    const missing = refs.filter((r) => !this.ready.has(r))
    if (missing.length === 0) return
    const gen = this.generation
    const rows = await this.deps.load(missing)
    if (gen !== this.generation) return
    let changed = false
    for (const [ref, a] of Object.entries(rows)) {
      if (!fresh(a)) continue
      this.ready.set(ref, a)
      changed = true
    }
    if (changed) this.onChange()
  }

  /** Сеть вернулась или файл появился — упавшие треки можно пробовать снова. */
  forgetFailures(): void {
    if (this.failed.size === 0) return
    this.failed.clear()
    this.onChange()
  }

  /** Хранилище очищено: память тоже. Идущие задачи доработают, но ничего не запишут. */
  reset(): void {
    this.generation++
    this.ready.clear()
    this.failed.clear()
    for (const job of this.waiting.splice(0)) job.resolve(null)
    this.onChange()
  }

  private firstParty(): number {
    const i = this.waiting.findIndex((j) => j.priority === 'party')
    return i < 0 ? this.waiting.length : i
  }

  private promote(job: Job): void {
    this.waiting.splice(this.waiting.indexOf(job), 1)
    job.priority = 'now'
    this.waiting.splice(this.firstParty(), 0, job)
  }

  private pump(): void {
    while (this.running.size < this.concurrency && this.waiting.length > 0) {
      const job = this.waiting.shift() as Job
      this.running.set(job.ref, job)
      void this.run(job)
    }
  }

  private async run(job: Job): Promise<void> {
    const gen = this.generation
    let result: BlendAnalysis | null = null
    let error = 'unknown'
    try {
      result = await this.obtain(job.ref, gen)
    } catch (err) {
      error = err instanceof Error ? err.message : String(err)
    }
    this.running.delete(job.ref)
    const current = gen === this.generation
    if (current && result) this.ready.set(job.ref, result)
    else if (current) this.failed.set(job.ref, error)
    job.resolve(current ? result : null)
    this.onChange()
    this.pump()
  }

  private async obtain(ref: string, gen: number): Promise<BlendAnalysis> {
    const stored = (await this.deps.load([ref]))[ref]
    if (fresh(stored)) return stored
    const a = await this.deps.compute(ref)
    if (gen === this.generation) await this.deps.save(a)
    return a
  }
}
