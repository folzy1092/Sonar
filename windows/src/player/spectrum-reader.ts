// Общее чтение спектра из одного AnalyserNode для нескольких зрителей (волна под ползунком, поле точек
// героя Главной). Каждый вызов getByteFrequencyData — ещё один шаг сглаживания анализатора
// (smoothingTimeConstant), поэтому зрители, которые читают почти одновременно, получают один и тот же
// снимок: так второй зритель не меняет, как выглядит спектр у первого. Без DOM — тесты с поддельным
// анализатором (`spectrum-reader.test.ts`), привязка к плееру — `analyser.ts`.

/** Что нужно от анализатора — подмножество AnalyserNode. */
export interface AnalyserLike {
  readonly frequencyBinCount: number
  readonly fftSize: number
  readonly context: { readonly sampleRate: number }
  getByteFrequencyData(array: Uint8Array<ArrayBuffer>): void
}

export interface Spectrum {
  /** Уровни полос 0…255 (общий буфер — только читать, не держать между кадрами). */
  readonly data: Uint8Array<ArrayBuffer>
  /** Ширина одной полосы, Гц. */
  readonly binHz: number
}

/** Чаще этого снимок не обновляется, мс: волна на 60 к/с (кадр ≥ 14.7 мс) всегда получает свежий. */
export const MIN_READ_GAP_MS = 12

/**
 * Читатель спектра поверх источника анализатора. `source()` → null — анализатора нет (граф Web Audio
 * не создан) или музыка не играет: читатель ничего не создаёт и возвращает null.
 */
export function createSpectrumReader(source: () => AnalyserLike | null) {
  let buf: Uint8Array<ArrayBuffer> | null = null
  let owner: AnalyserLike | null = null
  let readAt = -Infinity

  return function readSpectrum(now: number = performance.now()): Spectrum | null {
    const a = source()
    if (!a) return null
    if (!buf || owner !== a || buf.length !== a.frequencyBinCount) {
      buf = new Uint8Array(a.frequencyBinCount)
      owner = a
      readAt = -Infinity
    }
    if (now - readAt >= MIN_READ_GAP_MS || now < readAt) {
      a.getByteFrequencyData(buf)
      readAt = now
    }
    return { data: buf, binHz: a.context.sampleRate / a.fftSize }
  }
}
