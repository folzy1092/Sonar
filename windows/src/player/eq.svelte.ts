// Эквалайзер (по Dotify, скрин владельца 2026-11-14): 12 полос 32 Гц – 20 кГц, ±12 дБ, пресеты
// (свои — «+»). Правки звучат сразу, но пишутся только кнопкой «Сохранить» — одна кривая на все
// треки; закрыл без сохранения — вернулась сохранённая (решение владельца 2026-11-16). Звук идёт через
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
  /** Сохранённая кривая — одна на все треки (решение владельца 2026-11-16). */
  saved = $state<number[]>(flat())
  /** Кривая «на примерке»: правки звучат сразу, но пока не нажата «Сохранить» — не пишутся. */
  dirty = $derived(this.gains.some((g, i) => Math.abs(g - this.saved[i]) >= 0.05))

  presets = $derived([...this.userPresets, ...builtinPresets])
  /** Имя пресета, с которым совпадает текущая кривая. */
  activePreset = $derived(this.presets.find((p) => p.gains.every((g, i) => Math.abs(g - this.gains[i]) < 0.05))?.name ?? null)

  private filters: BiquadFilterNode[] = []

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
      if (valid(cur)) this.saved = cur.map(clampDb)
      if (Array.isArray(presets)) this.userPresets = presets.filter((p) => typeof p?.name === 'string' && valid(p.gains))
      this.set(this.saved)
    } catch {
      // вне приложения — ровная кривая
    }
  }

  /** Новая кривая на примерку: звучит сразу, не сохраняется. */
  set(gains: number[]) {
    this.gains = gains.map(clampDb)
    this.apply()
  }

  setBand(i: number, db: number) {
    const g = this.gains.slice()
    g[i] = clampDb(db)
    this.set(g)
  }

  /** «Сохранить» — кривая становится общей для всех треков. */
  save() {
    const g = $state.snapshot(this.gains)
    this.saved = g
    void api.setSetting('audio.eq', g).catch(() => {})
  }

  /** Закрыли эквалайзер без сохранения — звучит снова сохранённая кривая. */
  discard() {
    if (this.dirty) this.set(this.saved)
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
