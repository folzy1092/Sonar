<script lang="ts">
  // Волна под ползунком (как в Dotify): спектр звука из AnalyserNode, плавная заливка,
  // басы слева. На паузе плавно опадает. Рисуется только пока страница открыта.
  // Бережёт процессор: не чаще `fps` кадров в секунду, окно в фоне — ни одного. «Меньше движения»
  // (системное или выключенные анимации) — спектр не рисуется вовсе: он весь из движения.
  import { onMount } from 'svelte'
  import { player } from './player.svelte'
  import { settings } from '../lib/settings.svelte'
  import { fx } from '../lib/track-fx.svelte'
  import { reducedMotion } from '../lib/motion'

  interface Props {
    height?: number
    /** Цвет заливки; по умолчанию — приглушённый серый страницы плеера. */
    color?: string
    /** Потолок кадров в секунду. */
    fps?: number
  }
  let { height = 56, color: tint, fps = 60 }: Props = $props()

  const POINTS = 72
  let canvas: HTMLCanvasElement

  onMount(() => {
    const g = canvas.getContext('2d')!
    const color = tint ?? getComputedStyle(canvas).color
    const levels = new Float32Array(POINTS)
    let data: Uint8Array<ArrayBuffer> | null = null
    let frame = 0
    let last = 0
    let still = false

    const draw = (now = performance.now()) => {
      frame = requestAnimationFrame(draw)
      // экономия ресурсов: окно в фоне — не рисуем
      if (document.documentElement.classList.contains('idle')) return
      if (now - last < 1000 / fps - 2) return
      last = now
      if (reducedMotion()) {
        if (!still) g.clearRect(0, 0, canvas.width, canvas.height)
        still = true
        return
      }
      still = false
      const dpr = window.devicePixelRatio || 1
      const w = canvas.clientWidth
      const h = canvas.clientHeight
      if (canvas.width !== Math.round(w * dpr)) canvas.width = Math.round(w * dpr)
      if (canvas.height !== Math.round(h * dpr)) canvas.height = Math.round(h * dpr)
      g.setTransform(dpr, 0, 0, dpr, 0, 0)
      g.clearRect(0, 0, w, h)

      const a = player.analyser
      if (a && player.playing) {
        if (!data || data.length !== a.frequencyBinCount) data = new Uint8Array(a.frequencyBinCount)
        a.getByteFrequencyData(data)
        // логарифмическая шкала частот: ~40 Гц … ~14 кГц
        const hz = a.context.sampleRate / a.fftSize
        const lo = Math.max(1, Math.round(40 / hz))
        const hi = Math.min(data.length - 1, Math.round(14000 / hz))
        for (let i = 0; i < POINTS; i++) {
          const from = Math.round(lo * Math.pow(hi / lo, i / POINTS))
          const to = Math.max(from + 1, Math.round(lo * Math.pow(hi / lo, (i + 1) / POINTS)))
          let sum = 0
          for (let b = from; b < to; b++) sum += data[b]
          const v = sum / (to - from) / 255
          levels[i] += (v * v - levels[i]) * 0.35
        }
      } else {
        for (let i = 0; i < POINTS; i++) levels[i] *= 0.9
      }

      // «Сигнал»: при смене трека столбики гаснут в линию и вырастают (scaleY .08→1, 420 мс, сдвиг
      // 7 мс на столбик) — lib/track-fx.svelte.ts
      const grow = fx.barsStartedAt ? performance.now() - fx.barsStartedAt : Infinity
      if (grow < 420 + POINTS * 7) {
        for (let i = 0; i < POINTS; i++) {
          const k = Math.max(0, Math.min(1, (grow - i * 7) / 420))
          levels[i] *= 0.08 + 0.92 * (1 - Math.pow(1 - k, 3))
        }
      }
      let peak = 0
      for (let i = 0; i < POINTS; i++) peak = Math.max(peak, levels[i])
      if (peak < 0.004) return // тишина — без полоски на дне

      if (settings.get('player.visualizer_style') === 'bars') {
        // столбцы: по одному на полосу частот, скруглённые, с зазором
        const gap = 3
        const bw = Math.max(2, (w - gap * (POINTS - 1)) / POINTS)
        g.fillStyle = color
        for (let i = 0; i < POINTS; i++) {
          const bh = Math.max(2, levels[i] * (h - 2))
          const x = i * (bw + gap)
          g.beginPath()
          g.roundRect(x, h - bh, bw, bh, Math.min(bw / 2, 3))
          g.fill()
        }
        return
      }
      // плавная кривая через середины отрезков
      const step = w / (POINTS - 1)
      const y = (i: number) => h - levels[i] * (h - 4)
      g.beginPath()
      g.moveTo(0, h)
      g.lineTo(0, y(0))
      for (let i = 1; i < POINTS; i++) {
        const xm = (i - 0.5) * step
        g.quadraticCurveTo((i - 1) * step, y(i - 1), xm, (y(i - 1) + y(i)) / 2)
      }
      g.lineTo(w, y(POINTS - 1))
      g.lineTo(w, h)
      g.closePath()
      g.fillStyle = color
      g.fill()
    }
    draw()
    return () => cancelAnimationFrame(frame)
  })
</script>

<canvas bind:this={canvas} style:height="{height}px" aria-hidden="true"></canvas>

<style>
  canvas {
    display: block;
    width: 100%;
    color: rgba(163, 163, 171, 0.55);
  }
</style>
