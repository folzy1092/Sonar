// Фон полноэкранного плеера как у Dotify: не увеличенная копия обложки, а сама обложка (192 px,
// сильно размытая), которую шейдер медленно «течёт» волнами. Время шейдера идёт только пока трек
// играет — на паузе картинка стоит. Смена трека — плавное перетекание за ~0,5 с, смена строки текста —
// лёгкий сдвиг «фокуса» (0,7 с). Яркие места приглушаются, чтобы текст читался. 24 кадра/с.

const VERT = `
attribute vec2 position;
varying vec2 uv;
void main() { uv = position * 0.5 + 0.5; gl_Position = vec4(position, 0.0, 1.0); }
`

const FRAG = `
precision highp float;
varying vec2 uv;
uniform sampler2D artwork0;
uniform sampler2D artwork1;
uniform float blend;
uniform float time;
uniform vec2 focus0;
uniform vec2 focus1;
uniform float focusBlend;
uniform float aspect;
uniform vec2 character0;
uniform vec2 character1;
vec3 field(vec2 focus, sampler2D art, vec2 character) {
  float t = time * 1.45;
  float seed = character.x;
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
  vec2 current = sin(vec2(p.y * 2.3, p.x * 1.9) + vec2(t * 0.31, -t * 0.27) + seed);
  current += 0.45 * sin(vec2(p.x + p.y, p.y - p.x) * 3.1 + current.yx * 0.7 + vec2(-t * 0.19, t * 0.23));
  vec2 driftA = vec2(sin(t * 0.21 + seed), cos(t * 0.18 - seed)) * vec2(0.26, 0.20);
  vec2 surface = uv + current * 0.29 + driftA * 0.40 + focus * 0.12;
  return texture2D(art, clamp(surface, 0.0, 1.0)).rgb * character.y;
}
vec3 ambient(vec2 focus) {
  if (blend <= 0.0) return field(focus, artwork0, character0);
  vec3 next = field(focus, artwork1, character1);
  if (blend >= 1.0) return next;
  return mix(field(focus, artwork0, character0), next, blend);
}
void main() {
  vec3 colour = ambient(focus1);
  if (focusBlend < 1.0) colour = mix(ambient(focus0), colour, focusBlend);
  float luminance = dot(pow(colour, vec3(2.2)), vec3(0.2126, 0.7152, 0.0722));
  if (luminance > 0.12) {
    float mapped = 0.12 + (luminance - 0.12) * 0.24;
    colour *= pow(mapped / luminance, 1.0 / 2.2);
  }
  float grain = fract(dot(gl_FragCoord.xy, vec2(0.75487766, 0.56984029))) - 0.5;
  gl_FragColor = vec4(clamp(colour + grain / 255.0, 0.0, 1.0), 1.0);
}
`

const SIZE = 192

/** Размытие тройным box-blur (≈ гаусс) по RGBA, края — отражением. */
function blur(data: Uint8ClampedArray, w: number, h: number, radius: number) {
  let src = Float32Array.from(data)
  let dst = new Float32Array(data.length)
  const r = Math.max(1, Math.round(radius))
  const mirror = (i: number, n: number) => {
    const m = ((i % (2 * n)) + 2 * n) % (2 * n)
    return m < n ? m : 2 * n - m - 1
  }
  for (let pass = 0; pass < 3; pass++) {
    for (const horizontal of [true, false]) {
      const len = horizontal ? w : h
      const lines = horizontal ? h : w
      const at = (line: number, i: number) => 4 * (horizontal ? line * w + mirror(i, len) : mirror(i, len) * w + line)
      for (let line = 0; line < lines; line++) {
        for (let c = 0; c < 4; c++) {
          let sum = 0
          for (let k = -r; k <= r; k++) sum += src[at(line, k) + c]
          for (let i = 0; i < len; i++) {
            dst[at(line, i) + c] = sum / (2 * r + 1)
            sum += src[at(line, i + r + 1) + c] - src[at(line, i - r) + c]
          }
        }
      }
      ;[src, dst] = [dst, src]
    }
  }
  data.set(src)
}

/** Обложка → маленькая размытая текстура + «характер»: сид волн и экспозиция (тёмные — светлее). */
function prepare(img: HTMLImageElement): { canvas: HTMLCanvasElement; seed: number; exposure: number } {
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = SIZE
  const g = canvas.getContext('2d', { willReadFrequently: true })!
  g.fillStyle = 'black'
  g.fillRect(0, 0, SIZE, SIZE)
  const side = Math.min(img.naturalWidth, img.naturalHeight)
  g.drawImage(img, (img.naturalWidth - side) / 2, (img.naturalHeight - side) / 2, side, side, 0, 0, SIZE, SIZE)
  const px = g.getImageData(0, 0, SIZE, SIZE)
  const d = px.data
  // серость (доля серых светлых пикселей) — серые обложки размываем меньше, чтобы силуэт читался
  let grey = 0
  let seedSum = 0
  for (let i = 0; i < d.length; i += 4) {
    const mx = Math.max(d[i], d[i + 1], d[i + 2])
    const mn = Math.min(d[i], d[i + 1], d[i + 2])
    if (mx - mn <= 32 && (d[i] + d[i + 1] + d[i + 2]) / 3 >= 80) grey++
    seedSum += d[i] + 0.7 * d[i + 1] + 0.3 * d[i + 2]
  }
  const n = d.length / 4
  const gs = Math.max(0, Math.min(1, (grey / n - 0.3) / 0.45))
  const greyness = gs * gs * (3 - 2 * gs)
  blur(d, SIZE, SIZE, 16 - 4 * greyness)
  g.putImageData(px, 0, 0)
  const lum: number[] = []
  let max = 0
  for (let i = 0; i < d.length; i += 4) {
    lum.push((0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255)
    max = Math.max(max, d[i], d[i + 1], d[i + 2])
  }
  lum.sort((a, b) => a - b)
  const exposure = !lum.length || lum[Math.floor(lum.length / 2)] >= 0.58 ? 1 : Math.min(1.43, 0.221 / Math.max(0.12, max / 255))
  return { canvas, seed: seedSum / Math.max(1, 48 * n), exposure }
}

export class ArtField {
  private gl: WebGLRenderingContext
  private program: WebGLProgram
  private textures: WebGLTexture[] = []
  private loc: Record<string, WebGLUniformLocation | null> = {}
  private ready = [false, false]
  private keys: (string | null)[] = [null, null]
  private seq = [0, 0]
  private active = 0
  private mix = 0
  private elapsed = Math.random() * 40
  private last = 0
  private raf = 0
  private running = false
  private disposed = false
  private focusFrom = [0, 0]
  private focusTo = [0, 0]
  private focusMix = 1
  private focusIndex = -1

  constructor(private canvas: HTMLCanvasElement) {
    const gl = canvas.getContext('webgl', { alpha: false, antialias: false, depth: false, preserveDrawingBuffer: true, powerPreference: 'low-power' })
    if (!gl) throw new Error('WebGL недоступен')
    this.gl = gl
    const program = gl.createProgram()!
    for (const [type, code] of [
      [gl.VERTEX_SHADER, VERT],
      [gl.FRAGMENT_SHADER, FRAG],
    ] as const) {
      const sh = gl.createShader(type)!
      gl.shaderSource(sh, code)
      gl.compileShader(sh)
      if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(sh) ?? 'shader')
      gl.attachShader(program, sh)
    }
    gl.linkProgram(program)
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program) ?? 'link')
    this.program = program
    gl.useProgram(program)
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer())
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW)
    const pos = gl.getAttribLocation(program, 'position')
    gl.enableVertexAttribArray(pos)
    gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, 0, 0)
    for (const u of ['artwork0', 'artwork1', 'blend', 'time', 'focus0', 'focus1', 'focusBlend', 'aspect', 'character0', 'character1'])
      this.loc[u] = gl.getUniformLocation(program, u)
    for (let i = 0; i < 2; i++) {
      const tex = gl.createTexture()!
      this.textures.push(tex)
      gl.activeTexture(gl.TEXTURE0 + i)
      gl.bindTexture(gl.TEXTURE_2D, tex)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([10, 10, 10, 255]))
      gl.uniform1i(this.loc[`artwork${i}`], i)
    }
    this.resize()
  }

  resize() {
    const r = this.canvas.getBoundingClientRect()
    const k = Math.min(1, 1200 / Math.max(1, r.width))
    this.canvas.width = Math.max(1, Math.round(r.width * k))
    this.canvas.height = Math.max(1, Math.round(r.height * k))
    this.gl.viewport(0, 0, this.canvas.width, this.canvas.height)
    this.gl.useProgram(this.program)
    this.gl.uniform1f(this.loc.aspect, this.canvas.width / this.canvas.height)
    this.draw()
  }

  /** Новая обложка: грузится во второй слот и плавно перетекает. */
  async show(url: string | null) {
    if (!url || this.keys[this.active] === url) return
    const slot = this.ready[this.active] ? 1 - this.active : this.active
    const n = ++this.seq[slot]
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.src = url
    try {
      await img.decode()
    } catch {
      return
    }
    if (this.disposed || n !== this.seq[slot]) return
    const { canvas, seed, exposure } = prepare(img)
    const gl = this.gl
    gl.useProgram(this.program)
    gl.uniform2f(this.loc[`character${slot}`], seed, exposure)
    gl.activeTexture(gl.TEXTURE0 + slot)
    gl.bindTexture(gl.TEXTURE_2D, this.textures[slot])
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true)
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, canvas)
    const first = !this.ready[0] && !this.ready[1]
    this.ready[slot] = true
    this.keys[slot] = url
    this.active = slot
    if (first) this.mix = slot
    this.kick()
  }

  /** Смена строки текста — фокус фона слегка сдвигается. */
  setFocus(index: number) {
    if (index === this.focusIndex) return
    this.focusIndex = index
    this.focusFrom = this.focusFrom.map((v, i) => v + (this.focusTo[i] - v) * this.focusMix)
    const t = Math.max(0, index) + 1
    const rnd = (i: number) => {
      const x = 43758.5453 * Math.sin(t * (i === 0 ? 12.9898 : 78.233))
      return 0.44 * (x - Math.floor(x) - 0.5)
    }
    this.focusTo = index < 0 ? [0, 0] : [rnd(0), rnd(1)]
    this.focusMix = 0
    this.kick()
  }

  /** Играет — волны текут; пауза — картинка стоит (переходы обложки и фокуса всё равно доигрывают). */
  setRunning(on: boolean) {
    this.running = on
    this.kick()
  }

  private settling() {
    return Math.abs(this.mix - this.active) > 0.002 || this.focusMix < 1
  }

  private kick() {
    if (this.raf || this.disposed) return this.draw()
    this.last = 0
    this.raf = requestAnimationFrame(this.tick)
  }

  private tick = (ts: number) => {
    this.raf = 0
    if (this.disposed) return
    if (!this.last || ts - this.last >= 1000 / 24) {
      const dt = this.last ? Math.min(100, ts - this.last) : 0
      this.last = ts
      if (this.running && !document.hidden) this.elapsed += dt / 1000
      this.mix += (this.active - this.mix) * Math.min(1, dt / 160)
      if (Math.abs(this.mix - this.active) <= 0.002) this.mix = this.active
      this.focusMix = Math.min(1, this.focusMix + dt / 700)
      this.draw()
    }
    if ((this.running && !document.hidden) || this.settling()) this.raf = requestAnimationFrame(this.tick)
  }

  private draw() {
    if (this.disposed) return
    const gl = this.gl
    gl.useProgram(this.program)
    if (!this.ready[0] && !this.ready[1]) {
      gl.clearColor(0.04, 0.04, 0.04, 1)
      gl.clear(gl.COLOR_BUFFER_BIT)
      return
    }
    const blend = this.ready[0] && this.ready[1] ? this.mix : this.ready[0] ? 0 : 1
    gl.uniform1f(this.loc.blend, blend)
    gl.uniform1f(this.loc.time, this.elapsed)
    gl.uniform2fv(this.loc.focus0, this.focusFrom)
    gl.uniform2fv(this.loc.focus1, this.focusTo)
    const f = this.focusMix
    gl.uniform1f(this.loc.focusBlend, f * f * (3 - 2 * f))
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)
  }

  dispose() {
    this.disposed = true
    if (this.raf) cancelAnimationFrame(this.raf)
    for (const t of this.textures) this.gl.deleteTexture(t)
    this.gl.deleteProgram(this.program)
  }
}
