// Рисует поле точек героя на canvas (математика — `lib/field.ts`). 30 кадров/с, одним путём; вне экрана,
// во фоновой вкладке и при «Меньше движения» — стоит (при «Меньше движения» — один неподвижный кадр).
import { blurMask, cellCenter, drift, makeGrid, play, POKE_LIFE, value, type Grid, type Poke } from '../lib/field'

const STEP = 8
const FRAME_MS = 1000 / 30
const MIN_RADIUS = 0.45
const LOGO_SIDE = 0.92
const SAMPLES = 2
const POKE_KINDS = 3
/** Пока поле в стадии знака: первый кадр сразу со знаком. */
const START_TIME = 1.2

interface ViewBox {
  readonly x: number
  readonly y: number
  readonly w: number
  readonly h: number
}

function parseViewBox(raw: string): ViewBox {
  const [x, y, w, h] = raw.split(/\s+/).map(Number)
  return { x, y, w, h }
}

/** Маска знака: знак рисуется в маленький canvas (2×2 пробы на клетку), доля закраски → размытие. */
function logoMask(grid: Grid, path: Path2D, vb: ViewBox): Float32Array {
  const w = grid.cols * SAMPLES
  const h = grid.rows * SAMPLES
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d', { willReadFrequently: true })
  if (!ctx || w === 0 || h === 0) return new Float32Array(grid.cols * grid.rows)
  const side = Math.min(w, h) * LOGO_SIDE
  const scale = side / Math.max(vb.w, vb.h)
  ctx.translate((w - vb.w * scale) / 2, (h - vb.h * scale) / 2)
  ctx.scale(scale, scale)
  ctx.translate(-vb.x, -vb.y)
  ctx.fill(path, 'evenodd')
  const data = ctx.getImageData(0, 0, w, h).data
  const hits = new Float32Array(grid.cols * grid.rows)
  for (let row = 0; row < grid.rows; row++) {
    for (let col = 0; col < grid.cols; col++) {
      let sum = 0
      for (let sy = 0; sy < SAMPLES; sy++) {
        for (let sx = 0; sx < SAMPLES; sx++) {
          sum += data[((row * SAMPLES + sy) * w + col * SAMPLES + sx) * 4 + 3] / 255
        }
      }
      hits[row * grid.cols + col] = sum / (SAMPLES * SAMPLES)
    }
  }
  return blurMask(hits, grid.cols, grid.rows)
}

export function mountField(canvas: HTMLCanvasElement): void {
  const ctx = canvas.getContext('2d')
  const d = canvas.dataset.logo
  if (!ctx || !d) return
  const path = new Path2D(d)
  const vb = parseViewBox(canvas.dataset.viewbox ?? '0 0 100 100')
  const color = getComputedStyle(canvas).color
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)')

  let grid = makeGrid(0, 0, STEP)
  let logo = new Float32Array(0)
  let pokes: Poke[] = []
  let kindCounter = -1
  let visible = false
  let raf = 0
  let last = 0
  const epoch = performance.now() / 1000 - START_TIME

  const now = () => performance.now() / 1000 - epoch

  const resize = () => {
    const rect = canvas.getBoundingClientRect()
    const dpr = Math.min(2, window.devicePixelRatio || 1)
    canvas.width = Math.round(rect.width * dpr)
    canvas.height = Math.round(rect.height * dpr)
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    grid = makeGrid(rect.width, rect.height, STEP)
    logo = logoMask(grid, path, vb)
    draw(reduce.matches ? START_TIME : now())
  }

  const draw = (t: number) => {
    ctx.clearRect(0, 0, grid.width, grid.height)
    if (grid.cols === 0 || grid.rows === 0) return
    pokes = pokes.filter((p) => t - p.time < POKE_LIFE)
    const maxR = STEP * 0.5
    ctx.beginPath()
    for (let row = 0; row < grid.rows; row++) {
      for (let col = 0; col < grid.cols; col++) {
        const c = cellCenter(grid, col, row)
        let v = value(col, row, grid, logo, t)
        if (v <= 0 && pokes.length === 0) continue
        const dr = drift(col, row, t)
        let x = c.x + dr.dx
        let y = c.y + dr.dy
        v *= dr.scale
        for (const poke of pokes) {
          const fx = play(poke, x, y, t)
          x += fx.dx
          y += fx.dy
          v = Math.min(1, v * fx.scale)
        }
        const r = maxR * v
        if (r < MIN_RADIUS) continue
        ctx.moveTo(x + r, y)
        ctx.arc(x, y, r, 0, Math.PI * 2)
      }
    }
    ctx.fillStyle = color
    ctx.fill()
  }

  const loop = (ms: number) => {
    raf = requestAnimationFrame(loop)
    if (ms - last < FRAME_MS) return
    last = ms
    draw(now())
  }

  const sync = () => {
    const run = visible && !reduce.matches && !document.hidden
    if (run && !raf) raf = requestAnimationFrame(loop)
    if (!run && raf) {
      cancelAnimationFrame(raf)
      raf = 0
    }
  }

  canvas.addEventListener('pointerdown', (e) => {
    if (reduce.matches) return
    const rect = canvas.getBoundingClientRect()
    kindCounter += 1
    pokes = [...pokes, { x: e.clientX - rect.left, y: e.clientY - rect.top, time: now(), kind: kindCounter % POKE_KINDS }]
  })

  new ResizeObserver(resize).observe(canvas)
  new IntersectionObserver((entries) => {
    visible = entries.some((e) => e.isIntersecting)
    sync()
  }).observe(canvas)
  document.addEventListener('visibilitychange', sync)
  reduce.addEventListener('change', () => {
    sync()
    if (reduce.matches) draw(START_TIME)
  })
}
