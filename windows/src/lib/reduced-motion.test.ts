import { readFileSync } from 'node:fs'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { fly, glide, pop, rise, scale, slide } from './motion'

// «Меньше движения» (система) — только прозрачность: ни сдвигов, ни масштаба, ни сворачивания высоты.
const sources = import.meta.glob('../**/*.svelte', { query: '?raw', import: 'default', eager: true }) as Record<string, string>
// CSS через Vite в тестах приходит пустым — читаем файл с диска
const appCss = readFileSync(new URL('../app.css', import.meta.url), 'utf8')

const node = {} as Element
const rect = (x: number) => ({ left: x, top: 0, width: 10, height: 10 }) as DOMRect

/** Все кадры перехода (css) — только `opacity`. */
function opacityOnly(css: ((t: number, u: number) => string) | undefined) {
  expect(css).toBeTypeOf('function')
  for (const t of [0, 0.3, 1]) expect(css!(t, 1 - t)).toMatch(/^opacity:[\d.]+$/)
}

describe('«Меньше движения»', () => {
  beforeEach(() => {
    vi.stubGlobal('matchMedia', (q: string) => ({ matches: q.includes('reduce') }))
  })
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('свои переходы pop / rise — только прозрачность', () => {
    opacityOnly(pop(node).css)
    opacityOnly(rise(node).css)
  })

  it('slide / fly / scale из motion.ts — только прозрачность, без высоты и сдвига', () => {
    opacityOnly(slide(node, { duration: 260 }).css)
    opacityOnly(fly(node, { y: 20 }).css)
    opacityOnly(scale(node, { start: 0.9 }).css)
  })

  it('перестановка строк (glide) — мгновенно', () => {
    expect(glide(node, { from: rect(0), to: rect(40) }).duration).toBe(0)
  })

  it('ни один экран не берёт slide / fly / scale прямо из svelte/transition', () => {
    const offenders = Object.entries(sources)
      .filter(([, src]) => /import\s*\{[^}]*\b(slide|fly|scale)\b[^}]*\}\s*from\s*'svelte\/transition'/.test(src))
      .map(([file]) => file)
    expect(offenders).toEqual([])
  })

  it('CSS-анимации и переходы глушатся и системой, и выключателем', () => {
    expect(appCss).toMatch(/@media \(prefers-reduced-motion: reduce\)[\s\S]*?animation-duration: 0ms !important/)
    expect(appCss).toMatch(/:root\.no-motion \*[\s\S]*?transition-property: opacity/)
  })
})
