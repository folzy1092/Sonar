// Воркер анализа сведения (docs/BLEND.md §4.2): каналы трека 11 025 Гц приходят переданными (без копии),
// назад — готовый анализ. Тяжёлое — здесь, чтобы интерфейс и звук не дёргались.

import { analyze, toMono, type BlendAnalysis } from './analysis'

export interface AnalyzeJob {
  id: number
  ref: string
  channels: Float32Array[]
}

export type AnalyzeReply = { id: number; result: BlendAnalysis } | { id: number; error: string }

self.onmessage = (e: MessageEvent<AnalyzeJob>) => {
  const { id, ref, channels } = e.data
  let reply: AnalyzeReply
  try {
    reply = { id, result: analyze(toMono(channels), ref) }
  } catch (err) {
    reply = { id, error: err instanceof Error ? err.message : String(err) }
  }
  self.postMessage(reply)
}
