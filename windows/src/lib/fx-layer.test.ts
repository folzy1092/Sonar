import { describe, expect, it } from 'vitest'
import { FX_SKIP, skipped } from './fx-layer'

/** Заглушка элемента: `closest` находит предка, только если он помечен `data-fx-skip`. */
const node = (insideSkip: boolean) => ({
  closest: (selector: string) => (selector === FX_SKIP && insideSkip ? ({} as Element) : null),
})

describe('слой эффектов: пропуск живых примеров и закрытой шторки', () => {
  it('элемент внутри data-fx-skip пропускается — кольца от превью не рисуются', () => {
    // Arrange
    const inPreview = node(true)
    // Act
    const result = skipped(inPreview)
    // Assert
    expect(result).toBe(true)
  })

  it('обычный элемент окна не пропускается', () => {
    expect(skipped(node(false))).toBe(false)
  })
})
