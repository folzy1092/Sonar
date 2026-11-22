// Скорость, тон и реверб (меню у кнопки-часов, решение владельца 2026-11-16): готовые значения
// ×0.8 … ×1.35, ползунок скорости 0.5–2× с шагом 0.01, тон −12…+12 полутонов, «Связать тон со
// скоростью» (как slowed / sped up: тон едет вместе с темпом), «Сохранять между треками» (иначе на
// новом треке — снова 1×), реверб 0–100 %. Звук — `player.svelte.ts` `applySpeed` и `effects.ts`.
// «Для этого трека» (решение владельца 2026-11-22): скорость, тон, реверб и кривая эквалайзера
// запоминаются для одного трека (`track_prefs.sound_json`, синк `track_pref`), остальные треки — по общим.
import { api, type TrackSound } from '../lib/api'
import { eq } from './eq.svelte'

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

/** Что звучит → звук трека: выключенный реверб — 0. */
export function toSound(s: Pick<Saved, 'rate' | 'pitch' | 'linked' | 'reverb' | 'reverbOn'>, eqGains: number[] | null): TrackSound {
  return {
    rate: clampRate(s.rate),
    pitch: clampPitch(s.pitch),
    linked: s.linked,
    reverb: s.reverbOn ? Math.round(Math.min(1, Math.max(0, s.reverb)) * 100) / 100 : 0,
    eq: eqGains ? eqGains.slice() : null,
  }
}

/** Звук трека → состояние меню. Реверб 0 — выключен, а сила остаётся прежней (`keepReverb`). */
export function fromSound(s: TrackSound, keepReverb: number): Pick<Saved, 'rate' | 'pitch' | 'linked' | 'reverb' | 'reverbOn'> {
  return {
    rate: clampRate(s.rate),
    pitch: clampPitch(s.pitch),
    linked: s.linked,
    reverb: s.reverb > 0 ? Math.min(1, s.reverb) : keepReverb,
    reverbOn: s.reverb > 0,
  }
}

type Mix = Pick<Saved, 'rate' | 'pitch' | 'linked' | 'reverb' | 'reverbOn'>

interface Saved {
  rate: number
  pitch: number
  linked: boolean
  keep: boolean
  reverb: number
  reverbOn: boolean
}

class Tempo {
  rate = $state(1)
  /** Свой сдвиг тона (когда не связан со скоростью), полутоны. */
  pitch = $state(0)
  linked = $state(true)
  keep = $state(true)
  /** Сила реверба 0…1 — запоминается и при выключенном реверберации. */
  reverb = $state(0.35)
  /** Переключатель «Реверберация». */
  reverbOn = $state(false)
  /** Что звучит: выключен — 0. */
  wet = $derived(this.reverbOn ? this.reverb : 0)

  /** Тон, который звучит: связан — от скорости, иначе свой. */
  semitones = $derived(this.linked ? linkedSemitones(this.rate) : this.pitch)
  badge = $derived(badge(this.rate, this.linked ? 0 : this.pitch, this.reverbOn ? this.reverb : 0))
  /** Что-то настроено — кнопка в плеере подсвечена. */
  active = $derived(this.rate !== 1 || (!this.linked && this.pitch !== 0) || this.reverbOn)

  /** У трека свой звук («Для этого трека»): правки пишутся в трек, а не в общие настройки. */
  perTrack = $state(false)
  /** Играющий трек есть — переключатель «Для этого трека» доступен. */
  hasTrack = $state(false)

  private lastRef: string | null = null
  private timer: ReturnType<typeof setTimeout> | null = null
  private loaded = false
  /** Общие скорость, тон и реверб, пока звучат трековые. */
  private general: Mix | null = null

  constructor() {
    eq.onTrackSave = () => this.save()
  }

  private mix(): Mix {
    return { rate: this.rate, pitch: this.pitch, linked: this.linked, reverb: this.reverb, reverbOn: this.reverbOn }
  }

  private put(m: Mix) {
    this.rate = m.rate
    this.pitch = m.pitch
    this.linked = m.linked
    this.reverb = m.reverb
    this.reverbOn = m.reverbOn
  }

  /** «Для этого трека»: включили — нынешний звук (и кривая эквалайзера) запоминается для трека;
   *  выключили — трек забывает свой звук и играет по общим настройкам. */
  setPerTrack(on: boolean) {
    const ref = this.lastRef
    if (!ref || on === this.perTrack) return
    if (on) {
      this.general = this.mix()
      this.perTrack = true
      eq.useTrack($state.snapshot(eq.saved))
      this.save()
    } else {
      this.leaveTrack()
      void api.setTrackSound(ref, null).catch(() => {})
    }
  }

  /** Трек без своего звука: общие скорость, тон, реверб и кривая. */
  private leaveTrack() {
    if (!this.perTrack) return
    if (this.timer) {
      // недописанная правка трека — дописать сразу
      clearTimeout(this.timer)
      this.timer = null
      this.flush()
    }
    this.perTrack = false
    if (this.general) this.put(this.general)
    this.general = null
    eq.useGlobal()
  }

  /** Звук трека пришёл из базы — звучит он. */
  private enterTrack(s: TrackSound) {
    if (this.timer) {
      // общая правка (сброс к 1× на новом треке) ждёт записи — пусть уйдёт в общие, а не в трек
      clearTimeout(this.timer)
      this.timer = null
      this.flush()
    }
    if (!this.perTrack) this.general = this.mix()
    this.put(fromSound(s, this.general?.reverb ?? this.reverb))
    this.perTrack = true
    eq.useTrack(s.eq)
  }

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
        if (typeof s.reverb === 'number' && s.reverb > 0) this.reverb = Math.min(1, s.reverb)
        if (typeof s.reverbOn === 'boolean') this.reverbOn = s.reverbOn
        else if (typeof s.reverb === 'number') this.reverbOn = s.reverb > 0
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

  /** Тон. Связан со скоростью — двигается скорость (как у пластинки): −2 пт ≈ ×0.89. */
  setPitch(v: number) {
    if (this.linked) {
      const next = clampRate(pitchRatio(clampPitch(v)))
      // шаг питча 0.1 st мельче шага скорости 0.01 — сдвигаем скорость хотя бы на 0.01 в ту же сторону
      const dir = Math.sign(v - this.semitones)
      this.rate = next === this.rate && dir !== 0 ? clampRate(this.rate + dir * 0.01) : next
    } else {
      this.pitch = clampPitch(v)
    }
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

  setReverbOn(on: boolean) {
    this.reverbOn = on
    if (on && this.reverb <= 0) this.reverb = 0.35
    this.save()
  }

  /** Всё как было: 1×, без сдвига и реверба. */
  reset() {
    this.rate = 1
    this.pitch = 0
    this.reverbOn = false
    this.save()
  }

  /** Новый трек: свой звук трека — звучит он; иначе общие настройки, а без «Сохранять между
   *  треками» скорость и тон возвращаются к 1×. */
  trackChanged(ref: string | null) {
    if (ref === this.lastRef) return
    const first = this.lastRef === null
    this.leaveTrack()
    this.lastRef = ref
    this.hasTrack = ref !== null
    if (!first && !this.keep && (this.rate !== 1 || this.pitch !== 0)) {
      this.rate = 1
      this.pitch = 0
      this.save()
    }
    if (!ref) return
    void api
      .trackSound(ref)
      .then((s) => {
        // пока читали, трек сменился — не наш
        if (s && ref === this.lastRef) this.enterTrack(s)
      })
      .catch(() => {})
  }

  private save() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.timer = null
      this.flush()
    }, 250)
  }

  /** Записать: у трека со своим звуком — в трек, иначе — в общие настройки. */
  private flush() {
    if (this.perTrack && this.lastRef) {
      void api.setTrackSound(this.lastRef, toSound(this.mix(), $state.snapshot(eq.saved))).catch(() => {})
      // «Сохранять для след. треков» — общая настройка, она живёт и у трека со своим звуком
      if (this.general) void api.setSetting('player.tempo', { ...this.general, keep: this.keep }).catch(() => {})
      return
    }
    const s: Saved = { rate: this.rate, pitch: this.pitch, linked: this.linked, keep: this.keep, reverb: this.reverb, reverbOn: this.reverbOn }
    void api.setSetting('player.tempo', s).catch(() => {})
  }
}

export const tempo = new Tempo()
