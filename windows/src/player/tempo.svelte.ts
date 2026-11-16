// Скорость, тон и реверб (меню у кнопки-часов, решение владельца 2026-11-16): готовые значения
// ×0.8 … ×1.35, ползунок скорости 0.5–2× с шагом 0.01, тон −12…+12 полутонов, «Связать тон со
// скоростью» (как slowed / sped up: тон едет вместе с темпом), «Сохранять между треками» (иначе на
// новом треке — снова 1×), реверб 0–100 %. Звук — `player.svelte.ts` `applySpeed` и `effects.ts`.
import { api } from '../lib/api'

export const SPEED_PRESETS = [0.8, 0.9, 1, 1.15, 1.25, 1.35] as const
export const SPEED_MIN = 0.5
export const SPEED_MAX = 2
export const PITCH_MIN = -12
export const PITCH_MAX = 12

/** Скорость в допустимых пределах, с точностью до сотых. */
export const clampRate = (v: number) => Math.round(Math.min(SPEED_MAX, Math.max(SPEED_MIN, v)) * 100) / 100
/** Тон в полутонах, с точностью до десятых. */
export const clampPitch = (v: number) => Math.round(Math.min(PITCH_MAX, Math.max(PITCH_MIN, v)) * 10) / 10
/** На сколько полутонов сдвигается тон, когда он связан со скоростью. */
export const linkedSemitones = (rate: number) => Math.round(12 * Math.log2(rate) * 10) / 10
/** Множитель частоты для сдвига в полутонах. */
export const pitchRatio = (semitones: number) => 2 ** (semitones / 12)

/** Подпись кнопки: «0.8×», «1.25×»; на 1× без эффектов — пусто (значок часов). */
export function badge(rate: number, pitch: number, reverb: number): string {
  if (rate !== 1) return `${rate}×`
  if (pitch !== 0) return `${pitch > 0 ? '+' : ''}${pitch}`
  if (reverb > 0) return 'Reverb'
  return ''
}

interface Saved {
  rate: number
  pitch: number
  linked: boolean
  keep: boolean
  reverb: number
}

class Tempo {
  rate = $state(1)
  /** Свой сдвиг тона (когда не связан со скоростью), полутоны. */
  pitch = $state(0)
  linked = $state(true)
  keep = $state(true)
  /** 0…1 */
  reverb = $state(0)

  /** Тон, который звучит: связан — от скорости, иначе свой. */
  semitones = $derived(this.linked ? linkedSemitones(this.rate) : this.pitch)
  badge = $derived(badge(this.rate, this.linked ? 0 : this.pitch, this.reverb))

  private lastRef: string | null = null
  private timer: ReturnType<typeof setTimeout> | null = null
  private loaded = false

  async load() {
    if (this.loaded) return
    this.loaded = true
    try {
      const [s, legacy] = await Promise.all([api.getSetting<Partial<Saved>>('player.tempo'), api.getSetting<string>('player.speed_mode')])
      if (s && typeof s === 'object') {
        if (typeof s.rate === 'number') this.rate = clampRate(s.rate)
        if (typeof s.pitch === 'number') this.pitch = clampPitch(s.pitch)
        if (typeof s.linked === 'boolean') this.linked = s.linked
        if (typeof s.keep === 'boolean') this.keep = s.keep
        if (typeof s.reverb === 'number') this.reverb = Math.min(1, Math.max(0, s.reverb))
      } else if (legacy === 'slowed' || legacy === 'speed') {
        // старая кнопка по кругу: Slowed 0.8× / Sped up 1.25×
        this.rate = legacy === 'slowed' ? 0.8 : 1.25
      }
    } catch {
      // вне приложения — по умолчанию
    }
  }

  setRate(v: number) {
    this.rate = clampRate(v)
    this.save()
  }

  setPitch(v: number) {
    this.pitch = clampPitch(v)
    this.save()
  }

  setLinked(on: boolean) {
    // отвязали — тон остаётся тем, что звучал, и дальше двигается сам
    if (!on && this.linked) this.pitch = clampPitch(linkedSemitones(this.rate))
    this.linked = on
    this.save()
  }

  setKeep(on: boolean) {
    this.keep = on
    this.save()
  }

  setReverb(v: number) {
    this.reverb = Math.round(Math.min(1, Math.max(0, v)) * 100) / 100
    this.save()
  }

  /** Всё как было: 1×, без сдвига и реверба. */
  reset() {
    this.rate = 1
    this.pitch = 0
    this.reverb = 0
    this.save()
  }

  /** Новый трек: без «Сохранять между треками» скорость и тон возвращаются к 1×. */
  trackChanged(ref: string | null) {
    if (ref === this.lastRef) return
    const first = this.lastRef === null
    this.lastRef = ref
    if (!first && !this.keep && (this.rate !== 1 || this.pitch !== 0)) {
      this.rate = 1
      this.pitch = 0
      this.save()
    }
  }

  private save() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      const s: Saved = { rate: this.rate, pitch: this.pitch, linked: this.linked, keep: this.keep, reverb: this.reverb }
      void api.setSetting('player.tempo', s).catch(() => {})
    }, 250)
  }
}

export const tempo = new Tempo()
