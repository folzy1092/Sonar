import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { FX_SKIP, skipped, visible } from './fx-layer'

// Без DOM: элемент и предки — простые объекты с тем, что читает `visible` (lib/fx-layer.ts).
interface FakeNode {
  parentElement: FakeNode | null
  classList: { contains: (c: string) => boolean }
  getAnimations: () => Animation[]
  getBoundingClientRect: () => DOMRect
  style: { transform: string }
  closest: (selector: string) => Element | null
}

function node(parent: FakeNode | null, transform = 'none', animations: Animation[] = []): FakeNode {
  return {
    parentElement: parent,
    classList: { contains: () => false },
    getAnimations: () => animations,
    getBoundingClientRect: () => ({ left: 100, top: 100, right: 132, bottom: 132, width: 32, height: 32 }) as DOMRect,
    style: { transform },
    closest: () => null,
  }
}

/** Обратный переход transform у кнопки после `:active { scale(0.9) }` — идёт 140 мс. */
const pressTransition = { playState: 'running', transitionProperty: 'transform', effect: null } as unknown as Animation

beforeEach(() => {
  vi.stubGlobal('document', { querySelector: () => null })
  vi.stubGlobal('innerWidth', 1280)
  vi.stubGlobal('innerHeight', 800)
  vi.stubGlobal('KeyframeEffect', class {})
  vi.stubGlobal('getComputedStyle', (el: FakeNode) => ({ transform: el.style.transform }))
})

afterEach(() => vi.unstubAllGlobals())

describe('visible', () => {
  // сердце на обложке страницы плеера: span.ic внутри button.on-cover, у кнопки ещё идёт press-scale
  const pressedButton = () => node(node(null), 'matrix(0.9, 0, 0, 0.9, 0, 0)', [pressTransition])

  it('лайк: кнопка-предок в обратном переходе после :active — эффект всё равно рисуется', () => {
    const heart = node(pressedButton())
    expect(visible(heart as unknown as Element)).not.toBeNull()
  })

  it('смена трека (steady): предок сдвинут или двигается — эффект не рисуется', () => {
    const cover = node(pressedButton())
    expect(visible(cover as unknown as Element, { steady: true })).toBeNull()
  })

  it('смена трека (steady): предки на месте — рисуется', () => {
    const cover = node(node(node(null)))
    expect(visible(cover as unknown as Element, { steady: true })).not.toBeNull()
  })

  it('элемент за пределами окна — не рисуется ни в каком режиме', () => {
    const off = { ...node(null), getBoundingClientRect: () => ({ left: 0, top: 900, right: 32, bottom: 932, width: 32, height: 32 }) as DOMRect }
    expect(visible(off as unknown as Element)).toBeNull()
  })
})

/** Заглушка элемента: `closest` находит предка, только если он помечен `data-fx-skip`. */
const skipNode = (insideSkip: boolean) => ({
  closest: (selector: string) => (selector === FX_SKIP && insideSkip ? ({} as Element) : null),
})

describe('слой эффектов: пропуск живых примеров и закрытой шторки', () => {
  it('элемент внутри data-fx-skip пропускается — кольца от превью не рисуются', () => {
    // Arrange
    const inPreview = skipNode(true)
    // Act
    const result = skipped(inPreview)
    // Assert
    expect(result).toBe(true)
  })

  it('обычный элемент окна не пропускается', () => {
    expect(skipped(skipNode(false))).toBe(false)
  })

  it('visible: элемент в data-fx-skip не рисуется даже на виду', () => {
    const el = { ...node(null), closest: (sel: string) => (sel === FX_SKIP ? ({} as Element) : null) }
    expect(visible(el as unknown as Element)).toBeNull()
  })
})
