// Быстрое преобразование Фурье для анализа сведения (docs/BLEND.md §4.3): радикс-2, на месте,
// таблицы поворотов и перестановки считаются один раз на размер. Пакеты с npm для анализа не берём.

export class Fft {
  readonly size: number
  private readonly rev: Uint32Array
  private readonly cos: Float32Array
  private readonly sin: Float32Array

  constructor(size: number) {
    if (size < 2 || (size & (size - 1)) !== 0) throw new Error(`FFT: размер ${size} — не степень двойки`)
    this.size = size
    const bits = Math.log2(size)
    this.rev = new Uint32Array(size)
    for (let i = 0; i < size; i++) {
      let r = 0
      for (let b = 0; b < bits; b++) r |= ((i >> b) & 1) << (bits - 1 - b)
      this.rev[i] = r
    }
    this.cos = new Float32Array(size / 2)
    this.sin = new Float32Array(size / 2)
    for (let i = 0; i < size / 2; i++) {
      this.cos[i] = Math.cos((-2 * Math.PI * i) / size)
      this.sin[i] = Math.sin((-2 * Math.PI * i) / size)
    }
  }

  /** Прямое преобразование на месте: `re`, `im` длиной `size`. */
  transform(re: Float32Array, im: Float32Array): void {
    const n = this.size
    for (let i = 0; i < n; i++) {
      const j = this.rev[i]
      if (j > i) {
        const tr = re[i]
        re[i] = re[j]
        re[j] = tr
        const ti = im[i]
        im[i] = im[j]
        im[j] = ti
      }
    }
    for (let len = 2; len <= n; len <<= 1) {
      const half = len >> 1
      const step = n / len
      for (let start = 0; start < n; start += len) {
        for (let k = 0; k < half; k++) {
          const wr = this.cos[k * step]
          const wi = this.sin[k * step]
          const a = start + k
          const b = a + half
          const xr = re[b] * wr - im[b] * wi
          const xi = re[b] * wi + im[b] * wr
          re[b] = re[a] - xr
          im[b] = im[a] - xi
          re[a] += xr
          im[a] += xi
        }
      }
    }
  }
}

/** Окно Ханна длиной `n`. */
export function hann(n: number): Float32Array {
  const w = new Float32Array(n)
  for (let i = 0; i < n; i++) w[i] = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (n - 1))
  return w
}
