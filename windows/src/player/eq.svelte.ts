// Эквалайзер (по Dotify, скрин владельца 2026-11-14): 12 полос 32 Гц – 20 кГц, ±12 дБ, пресеты
// (свои — «+»), «Запомнить» — кривая для текущего трека (track_prefs.eq_json). Звук идёт через
// цепочку BiquadFilter в Web Audio: источник → полосы → анализатор волны → выход.
import { api } from '../lib/api'

export const EQ_FREQS = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 12000, 16000, 20000] as const
export const EQ_MAX_DB = 12
export const freqLabel = (f: number) => (f >= 1000 ? `${f / 1000}k` : String(f))

export interface EqPreset {
  name: string
  gains: number[]
  builtin?: boolean
}

const flat = () => EQ_FREQS.map(() => 0)

export const builtinPresets: EqPreset[] = [
  { name: 'Нейтральный', gains: flat(), builtin: true },
  { name: 'Басы', gains: [7, 6, 5, 3, 1, 0, 0, 0, 0, 0, 0, 0], builtin: true },
  { name: 'Высокие', gains: [0, 0, 0, 0, 0, 0, 1, 2, 4, 5, 6, 6], builtin: true },
  { name: 'Вокал', gains: [-2, -2, -1, 0, 2, 4, 4, 3, 1, 0, -1, -1], builtin: true },
  { name: 'Громче', gains: [4, 3, 1, 0, -1, -1, 0, 1, 2, 3, 4, 4], builtin: true },
]

export const clampDb = (v: number) => Math.round(Math.max(-EQ_MAX_DB, Math.min(EQ_MAX_DB, v)) * 10) / 10

function valid(g: unknown): g is number[] {
  return Array.isArray(g) && g.length === EQ_FREQS.length && g.every((x) => typeof x === 'number' && Number.isFinite(x))
}

class Equalizer {
  gains = $state<number[]>(flat())
  userPresets = $state<EqPreset[]>([])
  /** Трек, для которого кривая «запомнена» (тогда правки пишутся в него, а не в общую). */
  trackRef = $state<string | null>(null)
  remembered = $state(false)

  presets = $derived([...this.userPresets, ...builtinPresets])
  /** Имя пресета, с которым совпадает текущая кривая. */
  activePreset = $derived(this.presets.find((p) => p.gains.every((g, i) => Math.abs(g - this.gains[i]) < 0.05))?.name ?? null)

  private filters: BiquadFilterNode[] = []
  private global: number[] = flat()
  private saveTimer: ReturnType<typeof setTimeout> | null = null

  /** Цепочка фильтров между `input` и `output` (вызывает плеер). */
  connect(ctx: AudioContext, input: AudioNode, output: AudioNode) {
    this.filters = EQ_FREQS.map((f, i) => {
      const b = ctx.createBiquadFilter()
      b.type = i === 0 ? 'lowshelf' : i === EQ_FREQS.length - 1 ? 'highshelf' : 'peaking'
      b.frequency.value = f
      b.Q.value = 1.1
      b.gain.value = this.gains[i]
      return b
    })
    let node: AudioNode = input
    for (const b of this.filters) {
      node.connect(b)
      node = b
    }
    node.connect(output)
  }

  private apply() {
    this.filters.forEach((b, i) => b.gain.setTargetAtTime(this.gains[i], b.context.currentTime, 0.03))
  }

  async load() {
    try {
      const [cur, presets] = await Promise.all([
        api.getSetting<number[]>('audio.eq'),
        api.getSetting<{ name: string; gains: number[] }[]>('audio.eq_presets'),
      ])
      if (valid(cur)) this.global = cur.map(clampDb)
      if (Array.isArray(presets)) this.userPresets = presets.filter((p) => typeof p?.name === 'string' && valid(p.gains))
      if (!this.remembered) this.set(this.global, false)
    } catch {
      // вне приложения — ровная кривая
    }
  }

  /** Сменился трек: его запомненная кривая или общая. */
  async onTrack(ref: string | null) {
    this.trackRef = ref
    let own: number[] | null = null
    if (ref) {
      try {
        const g = await api.trackEq(ref)
        if (valid(g) && this.trackRef === ref) own = g.map(clampDb)
      } catch {
        // нет записи — общая кривая
      }
    }
    if (this.trackRef !== ref) return
    this.remembered = !!own
    this.set(own ?? this.global, false)
  }

  /** Новая кривая; `save` — записать (в трек, если он запомнен, иначе в общую). */
  set(gains: number[], save = true) {
    this.gains = gains.map(clampDb)
    this.apply()
    if (!save) return
    if (this.saveTimer) clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => {
      const g = $state.snapshot(this.gains)
      if (this.remembered && this.trackRef) void api.setTrackEq(this.trackRef, g).catch(() => {})
      else {
        this.global = g
        void api.setSetting('audio.eq', g).catch(() => {})
      }
    }, 300)
  }

  setBand(i: number, db: number) {
    const g = this.gains.slice()
    g[i] = clampDb(db)
    this.set(g)
  }

  /** «Запомнить» для трека / «Забыть» — снова общая кривая. */
  toggleRemember() {
    const ref = this.trackRef
    if (!ref) return
    if (this.remembered) {
      this.remembered = false
      void api.setTrackEq(ref, null).catch(() => {})
      this.set(this.global, false)
    } else {
      this.remembered = true
      void api.setTrackEq(ref, $state.snapshot(this.gains)).catch(() => {})
    }
  }

  addPreset(name: string) {
    const n = name.trim()
    if (!n) return
    const list = this.userPresets.filter((p) => p.name !== n)
    this.userPresets = [{ name: n, gains: $state.snapshot(this.gains) }, ...list]
    this.savePresets()
  }

  removePreset(name: string) {
    this.userPresets = this.userPresets.filter((p) => p.name !== name)
    this.savePresets()
  }

  private savePresets() {
    void api.setSetting('audio.eq_presets', $state.snapshot(this.userPresets)).catch(() => {})
  }
}

export const eq = new Equalizer()
