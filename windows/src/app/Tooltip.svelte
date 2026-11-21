<script lang="ts">
  // Своя подсказка вместо системной: title переносится в data-tip, чтобы браузер
  // не рисовал серый прямоугольник. Работает глобально, места с title не трогаем.
  import { onMount, tick } from 'svelte'

  const SHOW_DELAY = 450
  const FAST_DELAY = 80
  const GAP = 9
  const EDGE = 8

  let text = $state('')
  let shown = $state(false)
  let below = $state(false)
  let left = $state(0)
  let top = $state(0)
  let arrowX = $state(0)
  let box: HTMLDivElement | undefined = $state()

  let current: HTMLElement | null = null
  let showTimer: ReturnType<typeof setTimeout> | undefined
  let hideTimer: ReturnType<typeof setTimeout> | undefined
  let warm = false // курсор только что ходил между подсказками
  let observer: MutationObserver | undefined

  // Переносит title в data-tip; возвращает актуальный текст подсказки.
  function adopt(el: HTMLElement): string {
    const t = el.getAttribute('title')
    if (t !== null) {
      el.removeAttribute('title')
      if (t.trim()) el.dataset.tip = t
      else delete el.dataset.tip
    }
    return (el.dataset.tip ?? '').trim()
  }

  function clearTimers() {
    clearTimeout(showTimer)
    showTimer = undefined
  }

  function hide() {
    clearTimers()
    observer?.disconnect()
    current = null
    if (shown) {
      shown = false
      warm = true
      clearTimeout(hideTimer)
      hideTimer = setTimeout(() => (warm = false), 600)
    }
  }

  async function place() {
    if (!current) return
    await tick()
    if (!box || !current) return
    const r = current.getBoundingClientRect()
    const w = box.offsetWidth
    const h = box.offsetHeight
    const vw = window.innerWidth
    const vh = window.innerHeight
    const cx = r.left + r.width / 2
    let x = Math.min(Math.max(cx - w / 2, EDGE), Math.max(EDGE, vw - w - EDGE))
    below = r.top - h - GAP < EDGE
    let y = below ? r.bottom + GAP : r.top - h - GAP
    y = Math.min(Math.max(y, EDGE), Math.max(EDGE, vh - h - EDGE))
    left = x
    top = y
    arrowX = Math.min(Math.max(cx - x, 12), Math.max(12, w - 12))
  }

  async function show(el: HTMLElement) {
    const t = adopt(el)
    if (!t || current !== el) return
    text = t
    shown = true
    await place()
  }

  function schedule(el: HTMLElement) {
    clearTimers()
    showTimer = setTimeout(() => show(el), shown || warm ? FAST_DELAY : SHOW_DELAY)
  }

  function onOver(e: PointerEvent) {
    const target = e.target as Element | null
    const el = target?.closest?.('[title],[data-tip]') as HTMLElement | null
    if (!el) {
      if (current) hide()
      return
    }
    // title переносим при каждом наведении: Svelte мог выставить его заново.
    const t = adopt(el)
    if (el === current) return
    if (current) {
      clearTimers()
      observer?.disconnect()
    }
    current = el
    if (!t) {
      if (shown) hide()
      return
    }
    observer?.disconnect()
    observer = new MutationObserver(() => {
      if (!current) return
      const nt = adopt(current)
      if (!nt) return hide()
      if (shown) {
        text = nt
        place()
      }
    })
    observer.observe(el, { attributes: true, attributeFilter: ['title', 'data-tip'] })
    schedule(el)
  }

  function onOut(e: PointerEvent) {
    if (!current) return
    const to = e.relatedTarget as Node | null
    if (to && current.contains(to)) return
    hide()
  }

  onMount(() => {
    const opts = { capture: true, passive: true } as const
    const off = () => hide()
    document.addEventListener('pointerover', onOver, opts)
    document.addEventListener('pointerout', onOut, opts)
    document.addEventListener('pointerdown', off, opts)
    document.addEventListener('wheel', off, opts)
    document.addEventListener('scroll', off, opts)
    document.addEventListener('keydown', off, opts)
    window.addEventListener('blur', off)
    // title, выставленный заново без движения мыши (клик по повтору меняет подпись), браузер показал бы
    // системной подсказкой — забираем его сразу, где бы он ни появился
    const titles = new MutationObserver((list) => {
      for (const m of list) if (m.target instanceof HTMLElement && m.target.hasAttribute('title')) adopt(m.target)
    })
    titles.observe(document.body, { attributes: true, attributeFilter: ['title'], subtree: true })
    for (const el of document.body.querySelectorAll<HTMLElement>('[title]')) adopt(el)
    return () => {
      titles.disconnect()
      document.removeEventListener('pointerover', onOver, opts)
      document.removeEventListener('pointerout', onOut, opts)
      document.removeEventListener('pointerdown', off, opts)
      document.removeEventListener('wheel', off, opts)
      document.removeEventListener('scroll', off, opts)
      document.removeEventListener('keydown', off, opts)
      window.removeEventListener('blur', off)
      observer?.disconnect()
      clearTimers()
      clearTimeout(hideTimer)
    }
  })
</script>

<div
  bind:this={box}
  class="tip"
  class:shown
  class:below
  role="tooltip"
  aria-hidden="true"
  style="left:{left}px;top:{top}px;--ax:{arrowX}px"
>
  {text}
</div>

<style>
  .tip {
    position: fixed;
    z-index: 9000;
    pointer-events: none;
    max-width: 260px;
    width: max-content;
    padding: 5px 9px;
    border-radius: 9px;
    background: color-mix(in srgb, var(--surface-2) 92%, transparent);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    border: 1px solid var(--border-strong);
    box-shadow: 0 10px 28px rgba(0, 0, 0, 0.45);
    color: var(--text);
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.35;
    white-space: normal;
    overflow-wrap: anywhere;
    opacity: 0;
    visibility: hidden;
    transform: translateY(4px) scale(0.94);
    transform-origin: 50% 100%;
    transition:
      opacity 90ms var(--ease),
      transform 90ms var(--ease),
      visibility 0s linear 90ms;
  }
  .tip.below {
    transform: translateY(-4px) scale(0.94);
    transform-origin: 50% 0;
  }
  .tip.shown {
    opacity: 1;
    visibility: visible;
    transform: none;
    transition:
      opacity 160ms var(--ease),
      transform 160ms var(--ease),
      visibility 0s;
  }
  /* уголок к элементу */
  .tip::after {
    content: '';
    position: absolute;
    left: var(--ax, 50%);
    bottom: -5px;
    width: 8px;
    height: 8px;
    background: inherit;
    border-right: 1px solid var(--border-strong);
    border-bottom: 1px solid var(--border-strong);
    transform: translateX(-50%) rotate(45deg);
    border-bottom-right-radius: 2px;
  }
  .tip.below::after {
    bottom: auto;
    top: -5px;
    border: 0;
    border-left: 1px solid var(--border-strong);
    border-top: 1px solid var(--border-strong);
    border-radius: 2px 0 0 0;
  }
  @media (prefers-reduced-motion: reduce) {
    .tip,
    .tip.below {
      transform: none;
    }
  }
</style>
