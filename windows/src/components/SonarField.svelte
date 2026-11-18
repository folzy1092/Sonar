<script lang="ts">
  // Поле точек героя Главной (lib/sonar-field.ts; порт iPhone SonarField). Canvas, 30 кадров/с; вне экрана,
  // в свёрнутом окне и при «Меньше движения» — стоит (один кадр). Цвет — акцент темы (под обложку).
  import { onMount } from 'svelte'
  import raw from '../assets/logo-mark.svg?raw'
  import { drift, fieldValue, makeGrid, type Grid } from '../lib/sonar-field'
  import { reducedMotion } from '../lib/motion'

  let { playing = false, step = 9 }: { playing?: boolean; step?: number } = $props()

  const D = /\sd="([^"]+)"/.exec(raw)?.[1] ?? ''
  const [VX, VY, VW, VH] = (/viewBox="([^"]+)"/.exec(raw)?.[1] ?? '0 0 24 24').split(/\s+/).map(Number)

  let canvas: HTMLCanvasElement | undefined = $state()

  /** Маска знака на сетку: 4 пробы на клетку, мягкий край размытием 3×3. */
  function logoMask(g: Grid, w: number, h: number): Float32Array {
    const mask = new Float32Array(g.cols * g.rows)
    if (!D || !g.cols || !g.rows) return mask
    const probe = document.createElement('canvas').getContext('2d')
    if (!probe) return mask
    const path = new Path2D(D)
    const side = Math.min(w, h) * 0.78
    const s = side / Math.max(VW, VH)
    const ox = (w - VW * s) / 2 - VX * s
    const oy = (h - VH * s) / 2 - VY * s
    const pts = [-0.25, 0.25]
    for (let row = 0; row < g.rows; row++)
      for (let col = 0; col < g.cols; col++) {
        let hit = 0
        for (const px of pts)
          for (const py of pts) {
            const x = (g.ox + (col + 0.5 + px) * g.step - ox) / s
            const y = (g.oy + (row + 0.5 + py) * g.step - oy) / s
            if (probe.isPointInPath(path, x, y, 'evenodd')) hit += 0.25
          }
        mask[row * g.cols + col] = hit
      }
    const out = new Float32Array(mask.length)
    for (let row = 0; row < g.rows; row++)
      for (let col = 0; col < g.cols; col++) {
        let sum = 0
        let n = 0
        for (let dy = -1; dy <= 1; dy++)
          for (let dx = -1; dx <= 1; dx++) {
            const r = row + dy
            const c = col + dx
            if (r < 0 || r >= g.rows || c < 0 || c >= g.cols) continue
            const wgt = dx === 0 && dy === 0 ? 4 : 1
            sum += mask[r * g.cols + c] * wgt
            n += wgt
          }
        out[row * g.cols + col] = Math.min(1, (sum / n) * 1.25)
      }
    return out
  }

  onMount(() => {
    const el = canvas
    if (!el) return
    const ctx = el.getContext('2d')
    if (!ctx) return
    let grid = makeGrid(0, 0, step)
    let logo: Float32Array | null = null
    let w = 0
    let h = 0
    let color = '#fff'
    let colorAt = 0
    let raf = 0
    let last = 0
    let visible = true

    const resize = () => {
      const dpr = window.devicePixelRatio || 1
      w = el.clientWidth
      h = el.clientHeight
      el.width = Math.round(w * dpr)
      el.height = Math.round(h * dpr)
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
      grid = makeGrid(w, h, step)
      logo = logoMask(grid, w, h)
      draw(performance.now() / 1000)
    }

    const draw = (t: number) => {
      if (t - colorAt > 1) {
        color = getComputedStyle(el).getPropertyValue('--accent').trim() || '#fff'
        colorAt = t
      }
      ctx.clearRect(0, 0, w, h)
      ctx.fillStyle = color
      ctx.beginPath()
      const maxR = grid.step * 0.5
      for (let row = 0; row < grid.rows; row++)
        for (let col = 0; col < grid.cols; col++) {
          const d = drift(col, row, t)
          const r = maxR * fieldValue(col, row, grid, logo, t, playing) * d.scale
          if (r < 0.45) continue
          const x = grid.ox + (col + 0.5) * grid.step + d.dx
          const y = grid.oy + (row + 0.5) * grid.step + d.dy
          ctx.moveTo(x + r, y)
          ctx.arc(x, y, r, 0, Math.PI * 2)
        }
      ctx.fill()
    }

    const loop = (now: number) => {
      raf = requestAnimationFrame(loop)
      if (!visible || document.hidden || reducedMotion()) return
      if (now - last < 1000 / 30) return
      last = now
      draw(now / 1000)
    }

    const ro = new ResizeObserver(resize)
    ro.observe(el)
    const io = new IntersectionObserver(([e]) => (visible = e.isIntersecting))
    io.observe(el)
    raf = requestAnimationFrame(loop)
    return () => {
      cancelAnimationFrame(raf)
      ro.disconnect()
      io.disconnect()
    }
  })
</script>

<canvas bind:this={canvas} class="field" aria-hidden="true"></canvas>

<style>
  .field {
    display: block;
    width: 100%;
    height: 100%;
  }
</style>
