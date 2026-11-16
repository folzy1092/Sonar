<script lang="ts">
  // «Барабан» (референс владельца 2026-11-16): лента делений едет под неподвижной меткой по центру
  // (треугольник сверху, светлая черта). Тянуть мышью влево-вправо, колесо — шаг, двойной клик — к
  // значению по умолчанию. Любая смена значения (и извне — например, тон, связанный со скоростью)
  // догоняется плавно, как прокрутка страницы: лента не прыгает, а доезжает пружиной.
  import { onDestroy } from 'svelte'
  import { reducedMotion } from '../lib/motion'

  interface Props {
    value: number
    min: number
    max: number
    step: number
    /** Куда возвращает двойной клик. */
    reset?: number
    /** Пикселей ленты на один шаг. */
    px?: number
    /** Длинное деление каждые столько шагов. */
    major?: number
    disabled?: boolean
    onchange: (v: number) => void
  }
  let { value, min, max, step, reset = 0, px = 6, major = 10, disabled = false, onchange }: Props = $props()

  /** То, что сейчас нарисовано (догоняет `value`). */
  // svelte-ignore state_referenced_locally
  let shown = $state(value)
  let raf = 0
  let dragging = false
  let startX = 0
  let startV = 0

  const clamp = (v: number) => Math.min(max, Math.max(min, v))
  const snap = (v: number) => Math.round(clamp(v) / step) * step

  // лента доезжает до нового значения: на каждом кадре проходит часть оставшегося пути
  $effect(() => {
    const target = value
    if (dragging || reducedMotion()) {
      shown = target
      return
    }
    cancelAnimationFrame(raf)
    const tick = () => {
      const d = target - shown
      if (Math.abs(d) < step / 50) {
        shown = target
        return
      }
      shown += d * 0.16
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
  })
  onDestroy(() => cancelAnimationFrame(raf))

  /** Сдвиг ленты: значение `shown` стоит ровно под меткой. */
  const offset = $derived(((shown - min) / step) * px)

  function down(e: PointerEvent) {
    if (disabled) return
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    dragging = true
    startX = e.clientX
    startV = value
  }
  function move(e: PointerEvent) {
    if (!dragging) return
    // тянешь ленту вправо — под меткой оказываются меньшие значения
    const v = snap(startV - ((e.clientX - startX) / px) * step)
    if (v !== value) onchange(Number(v.toFixed(4)))
  }
  function up() {
    dragging = false
  }
  function wheel(e: WheelEvent) {
    if (disabled) return
    e.preventDefault()
    const d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : -e.deltaY
    onchange(Number(snap(value + Math.sign(d) * step).toFixed(4)))
  }
</script>

<div
  class="ruler"
  class:disabled
  role="slider"
  tabindex="-1"
  aria-valuenow={value}
  aria-valuemin={min}
  aria-valuemax={max}
  style:--px="{px}px"
  style:--major="{px * major}px"
  style:--off="{-offset}px"
  style:--len="{((max - min) / step) * px + 2}px"
  onpointerdown={down}
  onpointermove={move}
  onpointerup={up}
  onpointercancel={up}
  onwheel={wheel}
  ondblclick={() => !disabled && onchange(reset)}
>
  <span class="tape"></span>
  <span class="needle"></span>
  <span class="mark" aria-hidden="true"></span>
</div>

<style>
  .ruler {
    position: relative;
    height: 40px;
    overflow: hidden;
    cursor: grab;
    touch-action: none;
    /* края ленты затухают — как будто она уходит за барабан */
    mask-image: linear-gradient(90deg, transparent, #000 22%, #000 78%, transparent);
    -webkit-mask-image: linear-gradient(90deg, transparent, #000 22%, #000 78%, transparent);
  }
  .ruler:active {
    cursor: grabbing;
  }
  .ruler.disabled {
    cursor: default;
  }
  /* лента: начинается под меткой (значение min) и уезжает влево на `offset`; длинные деления каждые
     `major` шагов, мелкие — каждый шаг */
  .tape {
    position: absolute;
    left: 50%;
    bottom: 4px;
    width: var(--len);
    height: 22px;
    translate: calc(var(--off) - 1px) 0;
    background:
      repeating-linear-gradient(90deg, color-mix(in srgb, var(--text) 55%, transparent) 0 2px, transparent 2px var(--major)) 0 0 / 100% 100% no-repeat,
      repeating-linear-gradient(90deg, color-mix(in srgb, var(--text) 24%, transparent) 0 1px, transparent 1px var(--px)) 0 100% / 100% 14px no-repeat;
  }
  .needle {
    position: absolute;
    left: 50%;
    bottom: 2px;
    width: 2px;
    height: 26px;
    translate: -50% 0;
    border-radius: 2px;
    background: var(--text);
    box-shadow: 0 0 8px color-mix(in srgb, var(--text) 40%, transparent);
  }
  .mark {
    position: absolute;
    left: 50%;
    top: 0;
    translate: -50% 0;
    border-left: 6px solid transparent;
    border-right: 6px solid transparent;
    border-top: 8px solid var(--text-2);
  }
</style>
