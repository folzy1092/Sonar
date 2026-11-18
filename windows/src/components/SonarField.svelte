<script lang="ts">
  // Поле точек героя Главной (lib/sonar-field.ts; порт iPhone SonarField). Canvas, не больше 30 кадров/с;
  // вне экрана, в свёрнутом окне и в фоне при экономии ресурсов (класс .idle) — не рисуем. Цвет — акцент
  // темы (под обложку). Клик — волна-разлёт / вихрь / подскок по кругу, наведение — лёгкое притяжение,
  // под музыку — спектр общего анализатора плеера (player/analyser.ts): низы — дыхание, размер капель и
  // надувание точек сверх полного, середина — размах течения, верха — рябь, бит — встряска и кольцо-пинг
  // от центра, смена трека — сильное широкое кольцо (lib/sonar-ping.ts). «Меньше движения» — 15 к/с, без
  // сдвигов: клик — только смена прозрачности; экономия ресурсов в неактивном окне — 15 к/с, без встряски
  // и колец.
  import { onMount } from 'svelte'
  import raw from '../assets/logo-mark.svg?raw'
  import {
    AUDIO_START,
    SHAKE_LIFE,
    SILENT,
    addPoke,
    approach,
    bandLevels,
    drift,
    edgeFade,
    fadePulse,
    fieldValue,
    frameDue,
    hoverPull,
    isQuiet,
    makeGrid,
    prunePokes,
    shakeOffset,
    stackPokes,
    stepAudio,
    type AudioState,
    type Grid,
    type Poke,
  } from '../lib/sonar-field'
  import { BEAT_PING, TRACK_PING, addPing, dotRadius, prunePings, stackPings, type Ping } from '../lib/sonar-ping'
  import { reducedMotion } from '../lib/motion'
  import { settings } from '../lib/settings.svelte'
  import { readSpectrum } from '../player/analyser'
  import { player } from '../player/player.svelte'

  let { playing = false, step = 9 }: { playing?: boolean; step?: number } = $props()

  /** Насколько быстро курсор «входит» в поле и уходит из него, с. */
  const HOVER_TAU = 0.18
  /** Самый длинный шаг времени между кадрами, с — после паузы физика не прыгает. */
  const MAX_DT = 0.1
  /** «Меньше движения»: насколько гаснет поле от клика. */
  const CALM_FADE = 0.3
  /** Середина спектра раскачивает течение точек: на полной — размах ×(1 + MID_SWAY). */
  const MID_SWAY = 2
  /** Доля низов в надувании точек (остальное — кольца). */
  const LOW_KICK = 0.7

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
    const root = document.documentElement
    let grid = makeGrid(0, 0, step)
    let logo: Float32Array | null = null
    let w = 0
    let h = 0
    let color = '#fff'
    let colorAt = 0
    let raf = 0
    let last = 0
    let lastT = Number.NaN
    let visible = true
    // игра: клики, курсор, музыка (lib/sonar-field.ts — чистые функции, здесь только состояние кадров)
    let pokes: Poke[] = []
    let pokeCount = 0
    let flashAt = -Infinity
    let hovering = false
    let hx = 0
    let hy = 0
    let hoverAmt = 0
    let audio: AudioState = AUDIO_START
    // кольца-пинги: на бит и на смену трека; трек сравниваем по ref, первый кадр — без кольца
    let pings: Ping[] = []
    let beatSeen = -Infinity
    let trackRef = player.current?.ref ?? null

    /** Экономия ресурсов в неактивном (но видимом) окне — режим «свёрнуто»: рисуем реже и без встряски. */
    const saving = () => settings.get('system.power_saving') !== 'off' && !document.hasFocus()

    const resize = () => {
      const dpr = window.devicePixelRatio || 1
      w = el.clientWidth
      h = el.clientHeight
      el.width = Math.round(w * dpr)
      el.height = Math.round(h * dpr)
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
      grid = makeGrid(w, h, step)
      logo = logoMask(grid, w, h)
      draw(performance.now() / 1000, reducedMotion(), true)
    }

    /** Кадр музыки: спектр общего анализатора (нет анализатора или пауза — тишина, уровни мягко гаснут). */
    const listen = (t: number, dt: number) => {
      // отметка кадра в мс — та же, что у волны под ползунком: в одном кадре снимок общий
      const spectrum = readSpectrum(t * 1000)
      audio = stepAudio(audio, spectrum ? bandLevels(spectrum.data, spectrum.binHz) : SILENT, t, dt)
      return spectrum || !isQuiet(audio.levels) ? audio.levels : null
    }

    /** Новые кольца: бит трека — слабое, смена трека — сильное. В «Меньше движения» и экономии — нет. */
    const ring = (t: number, quiet: boolean) => {
      const ref = player.current?.ref ?? null
      const changed = ref !== trackRef
      trackRef = ref
      const beat = audio.beatAt !== beatSeen
      beatSeen = audio.beatAt
      pings = prunePings(pings, t)
      if (quiet) return
      if (changed && ref) pings = addPing(pings, t, TRACK_PING)
      else if (beat && Number.isFinite(audio.beatAt)) pings = addPing(pings, t, BEAT_PING)
    }

    const draw = (t: number, calm: boolean, lite: boolean) => {
      const dt = Number.isFinite(lastT) ? Math.min(MAX_DT, Math.max(0, t - lastT)) : 0
      lastT = t
      if (t - colorAt > 1) {
        color = getComputedStyle(el).getPropertyValue('--accent').trim() || '#fff'
        colorAt = t
      }
      const levels = listen(t, dt)
      // «Меньше движения»: спектр — сплошь движение, его не показываем (как волна под ползунком)
      const music = calm ? null : levels
      ring(t, lite)
      const sway = 1 + MID_SWAY * (music?.mid ?? 0)
      const lowKick = LOW_KICK * (music?.low ?? 0)
      const cx = w / 2
      const cy = h / 2
      const reach = Math.hypot(w, h)
      pokes = prunePokes(pokes, t, reach)
      hoverAmt = approach(hoverAmt, hovering && !calm ? 1 : 0, dt, HOVER_TAU)
      const shakeAge = calm || lite ? Infinity : t - audio.beatAt
      const moving = !calm
      // «Меньше движения» — только прозрачность: форма и размер точек замирают на одном кадре
      const ft = calm ? 0 : t

      ctx.clearRect(0, 0, w, h)
      ctx.globalAlpha = calm ? 1 - CALM_FADE * fadePulse(t - flashAt) : 1
      ctx.fillStyle = color
      ctx.beginPath()
      for (let row = 0; row < grid.rows; row++)
        for (let col = 0; col < grid.cols; col++) {
          const d = drift(col, row, ft, sway)
          let v = fieldValue(col, row, grid, logo, ft, playing, music) * d.scale
          let x = grid.ox + (col + 0.5) * grid.step
          let y = grid.oy + (row + 0.5) * grid.step
          // кольцо зажигает точки и вне фигуры; у кромки поля гаснет вместе с ней
          const ping = pings.length ? stackPings(pings, Math.hypot(x - cx, y - cy), t) * edgeFade(col, row, grid) : 0
          v = Math.min(1, v + ping)
          if (moving) {
            x += d.dx
            y += d.dy
            if (pokes.length) {
              const o = stackPokes(pokes, x, y, t)
              x += o.dx
              y += o.dy
              v = Math.min(1, v * o.scale)
            }
            if (hoverAmt > 0.001) {
              const o = hoverPull(x, y, hx, hy, hoverAmt)
              x += o.dx
              y += o.dy
              v = Math.min(1, v * o.scale)
            }
            if (shakeAge < SHAKE_LIFE) {
              const o = shakeOffset(col, row, shakeAge)
              x += o.dx
              y += o.dy
              v = Math.min(1, v * o.scale)
            }
          }
          const r = dotRadius(grid.step, v, lowKick + ping)
          if (r < 0.45) continue
          ctx.moveTo(x + r, y)
          ctx.arc(x, y, r, 0, Math.PI * 2)
        }
      ctx.fill()
    }

    const loop = (now: number) => {
      raf = requestAnimationFrame(loop)
      // вне экрана, свёрнуто или в фоне при экономии ресурсов — ни одного кадра
      if (!visible || document.hidden || root.classList.contains('idle')) {
        lastT = Number.NaN
        return
      }
      const calm = reducedMotion()
      const lite = calm || saving()
      if (!frameDue(now, last, lite)) return
      last = now
      draw(now / 1000, calm, lite)
    }

    /** Точка события в координатах поля. */
    const local = (e: PointerEvent) => {
      const rect = el.getBoundingClientRect()
      return { x: e.clientX - rect.left, y: e.clientY - rect.top }
    }
    const onMove = (e: PointerEvent) => {
      const p = local(e)
      hx = p.x
      hy = p.y
      hovering = true
    }
    const onLeave = () => (hovering = false)
    const onDown = (e: PointerEvent) => {
      if (e.button !== 0 || !e.isPrimary) return
      const p = local(e)
      const t = e.timeStamp / 1000
      if (reducedMotion()) flashAt = t
      else pokes = addPoke(pokes, p.x, p.y, t, pokeCount++, Math.hypot(w, h))
    }

    const ro = new ResizeObserver(resize)
    ro.observe(el)
    const io = new IntersectionObserver(([e]) => (visible = e.isIntersecting))
    io.observe(el)
    el.addEventListener('pointermove', onMove)
    el.addEventListener('pointerleave', onLeave)
    el.addEventListener('pointerdown', onDown)
    raf = requestAnimationFrame(loop)
    return () => {
      cancelAnimationFrame(raf)
      ro.disconnect()
      io.disconnect()
      el.removeEventListener('pointermove', onMove)
      el.removeEventListener('pointerleave', onLeave)
      el.removeEventListener('pointerdown', onDown)
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
