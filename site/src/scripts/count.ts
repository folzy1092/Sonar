// Плавная смена числа (цены на /pay): от прежнего значения к новому за ~0,4 с.
// «Меньше движения» — сразу новое значение.
const DURATION_MS = 420

export function tweenNumber(el: HTMLElement, to: number, format: (n: number) => string): void {
  const from = Number(el.dataset.value ?? to)
  el.dataset.value = String(to)
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  if (from === to || reduce) {
    el.textContent = format(to)
    return
  }
  const start = performance.now()
  const step = (now: number) => {
    if (el.dataset.value !== String(to)) return // пришло новое значение — этот шаг больше не нужен
    const k = Math.min(1, (now - start) / DURATION_MS)
    const eased = 1 - (1 - k) ** 3
    el.textContent = format(Math.round(from + (to - from) * eased))
    if (k < 1) requestAnimationFrame(step)
  }
  requestAnimationFrame(step)
}
