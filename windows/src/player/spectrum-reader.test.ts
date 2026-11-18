import { describe, expect, it } from 'vitest'
import { MIN_READ_GAP_MS, createSpectrumReader, type AnalyserLike } from './spectrum-reader'

function fakeAnalyser(bins = 8): AnalyserLike & { reads: number } {
  const a: AnalyserLike & { reads: number } = {
    reads: 0,
    frequencyBinCount: bins,
    fftSize: bins * 2,
    context: { sampleRate: 48_000 },
    getByteFrequencyData(array: Uint8Array<ArrayBuffer>) {
      a.reads += 1
      array.fill(a.reads)
    },
  }
  return a
}

describe('createSpectrumReader', () => {
  it('без анализатора возвращает null и ничего не читает', () => {
    // Arrange
    const read = createSpectrumReader(() => null)

    // Act + Assert
    expect(read(0)).toBeNull()
  })

  it('отдаёт полосы и ширину полосы в герцах', () => {
    // Arrange
    const a = fakeAnalyser(8)
    const read = createSpectrumReader(() => a)

    // Act
    const s = read(100)

    // Assert
    expect(s?.data.length).toBe(8)
    expect(s?.binHz).toBe(48_000 / 16)
    expect(s?.data[0]).toBe(1)
  })

  it('зрители в пределах одного кадра делят один снимок', () => {
    // Arrange
    const a = fakeAnalyser()
    const read = createSpectrumReader(() => a)

    // Act
    read(1000)
    read(1000 + MIN_READ_GAP_MS - 1)

    // Assert
    expect(a.reads).toBe(1)
  })

  it('небольшой шаг назад (отметка кадра после performance.now) — тот же снимок', () => {
    // Arrange
    const a = fakeAnalyser()
    const read = createSpectrumReader(() => a)

    // Act
    read(1005)
    read(1000)

    // Assert
    expect(a.reads).toBe(1)
  })

  it('по прошествии промежутка читает заново', () => {
    // Arrange
    const a = fakeAnalyser()
    const read = createSpectrumReader(() => a)

    // Act
    read(1000)
    const s = read(1000 + MIN_READ_GAP_MS)

    // Assert
    expect(a.reads).toBe(2)
    expect(s?.data[0]).toBe(2)
  })

  it('новый анализатор — новый буфер и свежее чтение', () => {
    // Arrange
    let a = fakeAnalyser(4)
    const read = createSpectrumReader(() => a)
    read(1000)

    // Act
    a = fakeAnalyser(16)
    const s = read(1001)

    // Assert
    expect(s?.data.length).toBe(16)
    expect(a.reads).toBe(1)
  })
})
