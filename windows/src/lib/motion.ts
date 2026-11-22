// Общие анимации интерфейса (PLATFORMS.md «Анимации»): появляется — из масштаба 0.98 и снизу
// с прозрачностью, исчезает быстрее, чем появлялось. «Меньше движения» в системе или выключатель
// `appearance.animations` — только прозрачность.
import { cubicOut, cubicIn } from 'svelte/easing'
import {
  fly as svelteFly,
  scale as svelteScale,
  slide as svelteSlide,
  type FlyParams,
  type ScaleParams,
  type SlideParams,
  type TransitionConfig,
} from 'svelte/transition'
import { flip, type AnimationConfig } from 'svelte/animate'

let animationsOn = true

/** Выключатель `appearance.animations` (панель настроек «Интерфейс»). */
export function setAnimations(on: boolean) {
  animationsOn = on
  document.documentElement.classList.toggle('no-motion', !on)
}

/** Только прозрачность: системное «Меньше движения» или анимации выключены. */
export function reducedMotion(): boolean {
  if (!animationsOn) return true
  return typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches
}

/** Плавное замедление как `--ease` (cubic-bezier(0.22, 1, 0.36, 1)). */
export function easeOutQuint(t: number) {
  return 1 - Math.pow(1 - t, 5)
}

interface PopParams {
  duration?: number
  /** Откуда растёт: сдвиг по Y в px (меню под кнопкой — отрицательный, над — положительный). */
  y?: number
  scale?: number
  origin?: string
  delay?: number
}

/** Всплывашка и меню: появление (0.98 + сдвиг) и исчезание. Для `in:` и `out:` (out быстрее). */
export function pop(node: Element, { duration = 180, y = 6, scale = 0.97, delay = 0 }: PopParams = {}, opts?: { direction?: 'in' | 'out' | 'both' }): TransitionConfig {
  const out = opts?.direction === 'out'
  const d = out ? Math.round(duration * 0.7) : duration
  if (reducedMotion()) return { duration: d * 0.6, delay, css: (t) => `opacity:${t}` }
  const base = getComputedStyle(node).transform
  const pre = base && base !== 'none' ? base + ' ' : ''
  return {
    duration: d,
    delay,
    easing: out ? cubicIn : easeOutQuint,
    css: (t, u) => `opacity:${t};transform:${pre}translateY(${u * y}px) scale(${1 - u * (1 - scale)})`,
  }
}

/** Плавное появление снизу — строки списков и плитки (каскад — через `delay`). */
export function rise(node: Element, { duration = 320, y = 10, delay = 0 }: { duration?: number; y?: number; delay?: number } = {}): TransitionConfig {
  if (reducedMotion()) return { duration: 160, delay, css: (t) => `opacity:${t}` }
  return {
    duration,
    delay,
    easing: easeOutQuint,
    css: (t, u) => `opacity:${t};transform:translateY(${u * y}px)`,
  }
}

/** Перестановка строк списка (`animate:glide` в keyed `{#each}`): строка переезжает на новое место
 *  (FLIP). «Меньше движения» — без сдвига, строка сразу на месте. */
export function glide(node: Element, rects: { from: DOMRect; to: DOMRect }, { duration = 300 }: { duration?: number } = {}): AnimationConfig {
  if (reducedMotion()) return { duration: 0 }
  return flip(node, rects, { duration, easing: easeOutQuint })
}

/** Кроссфейд: просто прозрачность (обложка и название при смене трека). */
export function xfade(_node: Element, { duration = 260, delay = 0 }: { duration?: number; delay?: number } = {}): TransitionConfig {
  return { duration, delay, easing: cubicOut, css: (t) => `opacity:${t}` }
}

/** Задержка каскада: 25 мс между строками, не дольше ~350 мс на весь список. */
export function stagger(i: number, step = 25, max = 14): number {
  return Math.min(i, max) * step
}

/** Плавный счёт цифр (статистика): от `from` до `to` за `ms`, колбэк на каждый кадр. */
export function countUp(from: number, to: number, ms: number, cb: (v: number) => void): () => void {
  if (reducedMotion() || from === to) {
    cb(to)
    return () => {}
  }
  const start = performance.now()
  let raf = 0
  const step = (now: number) => {
    const t = Math.min(1, (now - start) / ms)
    cb(from + (to - from) * easeOutQuint(t))
    if (t < 1) raf = requestAnimationFrame(step)
  }
  raf = requestAnimationFrame(step)
  return () => cancelAnimationFrame(raf)
}

/** Длительность «спокойной» версии: короче движения, только прозрачность. */
const CALM_SHARE = 0.6
const SVELTE_DEFAULT_MS = 400

function calm({ duration = SVELTE_DEFAULT_MS, delay = 0 }: { duration?: number; delay?: number }): TransitionConfig {
  return { duration: Math.round(duration * CALM_SHARE), delay, css: (t) => `opacity:${t}` }
}

/** `slide` из svelte/transition, но «Меньше движения» — без сворачивания высоты, только прозрачность. */
export function slide(node: Element, params: SlideParams = {}): TransitionConfig {
  return reducedMotion() ? calm(params) : svelteSlide(node, params)
}

/** `fly` из svelte/transition, но «Меньше движения» — без сдвига, только прозрачность. */
export function fly(node: Element, params: FlyParams = {}): TransitionConfig {
  return reducedMotion() ? calm(params) : svelteFly(node, params)
}

/** `scale` из svelte/transition, но «Меньше движения» — без масштаба, только прозрачность. */
export function scale(node: Element, params: ScaleParams = {}): TransitionConfig {
  return reducedMotion() ? calm(params) : svelteScale(node, params)
}
