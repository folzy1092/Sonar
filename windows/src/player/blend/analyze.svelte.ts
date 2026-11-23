// Анализ сведения в приложении (docs/BLEND.md §4): файл трека — с локального аудио-сервера (`blend_source`),
// декодирование в 11 025 Гц — `OfflineAudioContext`, расчёт — воркер, хранение — `blend_analysis` в базе.
// Пока сведение включено, в очередь идут играющий трек и следующий (§4.5).

import { untrack } from 'svelte'
import { api, onOfflineChanged } from '../../lib/api'
import { isTauri } from '../../lib/tauri'
import { settings } from '../../lib/settings.svelte'
import { player } from '../player.svelte'
import { ANALYSIS_VERSION, type BlendAnalysis } from './analysis'
import { AnalyzeQueue, type AnalyzePriority } from './analyze-queue'
import type { AnalyzeJob, AnalyzeReply } from './analysis.worker'
import { SAMPLE_RATE } from './features'

/** `ready` — есть, `pending` — считается, `failed` — не вышло (будет обычный кроссфейд), `none` — не просили. */
export type AnalysisState = 'ready' | 'pending' | 'failed' | 'none'

/** Воркер один на приложение; ответы — по номеру задачи. */
class WorkerClient {
  private worker: Worker | null = null
  private seq = 0
  private readonly waiting = new Map<number, { ok: (a: BlendAnalysis) => void; fail: (e: Error) => void }>()

  run(ref: string, channels: Float32Array[]): Promise<BlendAnalysis> {
    const worker = this.ensure()
    const id = ++this.seq
    return new Promise((ok, fail) => {
      this.waiting.set(id, { ok, fail })
      const job: AnalyzeJob = { id, ref, channels }
      worker.postMessage(job, channels.map((c) => c.buffer as ArrayBuffer))
    })
  }

  private ensure(): Worker {
    if (this.worker) return this.worker
    const w = new Worker(new URL('./analysis.worker.ts', import.meta.url), { type: 'module' })
    w.onmessage = (e: MessageEvent<AnalyzeReply>) => {
      const job = this.waiting.get(e.data.id)
      if (!job) return
      this.waiting.delete(e.data.id)
      if ('result' in e.data) job.ok(e.data.result)
      else job.fail(new Error(e.data.error))
    }
    w.onerror = (e) => {
      // воркер упал целиком — все ждущие задачи с ошибкой, следующая поднимет новый
      for (const job of this.waiting.values()) job.fail(new Error(e.message || 'воркер анализа упал'))
      this.waiting.clear()
      w.terminate()
      this.worker = null
    }
    this.worker = w
    return w
  }
}

/** PCM трека 11 025 Гц, по каналу на массив. */
async function decode(url: string): Promise<Float32Array[]> {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`файл трека: HTTP ${res.status}`)
  const buf = await res.arrayBuffer()
  const audio = await new OfflineAudioContext(1, 1, SAMPLE_RATE).decodeAudioData(buf)
  return Array.from({ length: audio.numberOfChannels }, (_, c) => audio.getChannelData(c))
}

async function load(refs: string[]): Promise<Record<string, BlendAnalysis>> {
  const rows = await api.blendGet(refs)
  const out: Record<string, BlendAnalysis> = {}
  for (const [ref, row] of Object.entries(rows)) {
    if (row.version !== ANALYSIS_VERSION) continue
    try {
      out[ref] = JSON.parse(row.data) as BlendAnalysis
    } catch {
      // битая строка — посчитаем заново и перезапишем
    }
  }
  return out
}

class BlendAnalysisStore {
  /** Растёт на каждое изменение очереди: экраны читают `state` / `peek` реактивно. */
  private tick = $state(0)
  private readonly worker = new WorkerClient()
  private readonly queue = new AnalyzeQueue(
    {
      load,
      compute: (ref) => this.compute(ref),
      save: (a) => api.blendPut(a.ref, a.version, JSON.stringify(a)),
    },
    () => this.tick++,
  )
  private started = false

  init() {
    if (this.started || !isTauri) return
    this.started = true
    // сеть вернулась — треки, которые не скачались, можно пробовать снова
    onOfflineChanged((on) => {
      if (!on) this.queue.forgetFailures()
    })
    $effect.root(() => {
      $effect(() => {
        if (!settings.get('audio.blend')) return
        const now = player.current?.ref
        const next = player.repeat === 'one' ? undefined : player.upNext[0]?.ref
        untrack(() => {
          if (now) void this.queue.request(now)
          if (next) void this.queue.request(next)
        })
      })
    })
  }

  peek(ref: string): BlendAnalysis | undefined {
    void this.tick
    return this.queue.peek(ref)
  }

  state(ref: string): AnalysisState {
    void this.tick
    if (this.queue.peek(ref)) return 'ready'
    if (this.queue.pending(ref)) return 'pending'
    return this.queue.failure(ref) ? 'failed' : 'none'
  }

  failure(ref: string): string | undefined {
    void this.tick
    return this.queue.failure(ref)
  }

  request(ref: string, priority: AnalyzePriority = 'now'): Promise<BlendAnalysis | null> {
    return this.queue.request(ref, priority)
  }

  /** Вечеринка: поднять готовое из базы, остальное — в хвост очереди. */
  async party(refs: string[]): Promise<void> {
    await this.queue.warm(refs)
    for (const ref of refs) void this.queue.request(ref, 'party')
  }

  /** «Очистить» в Хранилище: база уже пустая — память тоже. */
  reset() {
    this.queue.reset()
  }

  private async compute(ref: string): Promise<BlendAnalysis> {
    const src = await api.blendSource(ref)
    try {
      return await this.worker.run(ref, await decode(src.url))
    } finally {
      if (src.temp) void api.blendRelease(ref).catch(() => {})
    }
  }
}

export const blendAnalysis = new BlendAnalysisStore()
