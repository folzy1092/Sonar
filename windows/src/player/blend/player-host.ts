// Хост сведения для настоящего плеера (docs/BLEND.md §6.5): грузит B во второй <audio> на паузе и с нулём
// громкости, держит его hls.js, освобождает деки и отдаёт плееру «играющий дек» без `load()`.
// Сам плеер — через узкий `HostSide`, чтобы player.svelte.ts не разрастался.

import Hls from 'hls.js'
import { api, type StreamUrl, type Track, type TrackSound } from '../../lib/api'
import { settings } from '../../lib/settings.svelte'
import { tempo } from '../tempo.svelte'
import type { BlendAnalysis } from './analysis'
import type { BlendHost, OwnSound } from './controller.svelte'
import type { DeckChain } from './deck-chain'
import { blendSettings } from './settings'

export interface PlayerDeck {
  el: HTMLAudioElement
  chain: DeckChain
}

/** Что хосту нужно от плеера. */
export interface HostSide {
  ctx(): AudioContext | null
  /** Дек, который сейчас не текущий. */
  otherDeck(): HTMLAudioElement | null
  chain(el: HTMLAudioElement): DeckChain | undefined
  analysis(ref: string): BlendAnalysis | null
  /** B стал текущим; вернуть hls.js прежнего дека, чтобы хост освободил его вместе с деком. */
  promote(el: HTMLAudioElement, hls: Hls | null, stream: StreamUrl, track: Track, listenedMs: number): Hls | null
  hold(on: boolean): void
  /** Фатальная ошибка hls.js у загруженного B. */
  deckError(el: HTMLAudioElement): void
  /** Поток в дек на паузе с позиции `atSec` (hls.js или файл) — тот же путь, что у своего дека плеера. */
  mount(el: HTMLAudioElement, stream: StreamUrl, atSec: number): Hls | null
}

/** Сколько ждать, пока B будет готов играть, мс: дольше — переход не успеет, будет кроссфейд. */
const LOAD_TIMEOUT_MS = 10_000

interface Held {
  hls: Hls | null
  stream: StreamUrl | null
  track: Track | null
}

/** Свой звук трека так, как его применит `tempo.trackChanged`: «Для этого трека» или общий (с «Запомнить»). */
export function ownSound(s: TrackSound | null, keep: boolean, cur: OwnSound): OwnSound {
  if (s) return { rate: s.rate, pitch: s.pitch, linked: s.linked }
  return keep ? cur : { rate: 1, pitch: 0, linked: cur.linked }
}

function silence(chain: DeckChain, ctx: AudioContext) {
  const g = chain.gain.gain
  g.cancelScheduledValues(ctx.currentTime)
  g.setValueAtTime(0, ctx.currentTime)
}

function stop(el: HTMLAudioElement, hls: Hls | null) {
  el.pause()
  hls?.destroy()
  el.removeAttribute('src')
  el.load()
}

/** Дек готов играть с нужного места (или ошибка / таймаут). */
function ready(el: HTMLAudioElement, hls: Hls | null): Promise<void> {
  return new Promise((resolve, reject) => {
    const done = (ok: boolean) => {
      clearTimeout(timer)
      el.removeEventListener('canplay', onReady)
      el.removeEventListener('error', onFail)
      hls?.off(Hls.Events.ERROR, onHls)
      if (ok) resolve()
      else reject(new Error('blend: deck B not ready'))
    }
    const onReady = () => done(true)
    const onFail = () => done(false)
    const onHls = (_e: unknown, data: { fatal: boolean }) => {
      if (data.fatal) done(false)
    }
    const timer = setTimeout(onFail, LOAD_TIMEOUT_MS)
    if (el.readyState >= HTMLMediaElement.HAVE_FUTURE_DATA) return done(true)
    el.addEventListener('canplay', onReady)
    el.addEventListener('error', onFail)
    hls?.on(Hls.Events.ERROR, onHls)
  })
}

export function createBlendHost(side: HostSide): BlendHost<Track, PlayerDeck> {
  const held = new Map<HTMLAudioElement, Held>()

  function release(deck: PlayerDeck) {
    const h = held.get(deck.el)
    held.delete(deck.el)
    stop(deck.el, h?.hls ?? null)
  }

  async function load(track: Track, startSec: number): Promise<PlayerDeck | null> {
    const ctx = side.ctx()
    const el = side.otherDeck()
    const chain = el && side.chain(el)
    if (!ctx || !el || !chain) return null
    silence(chain, ctx)
    const mine = { hls: null, stream: null, track }
    held.set(el, mine)
    const stale = () => held.get(el)?.track !== track
    try {
      const stream = await api.streamUrl(track.ref, track)
      if (stale()) return null
      const hls = side.mount(el, stream, Math.max(0, startSec))
      held.set(el, { hls, stream, track })
      await ready(el, hls)
      if (stale()) return null
      hls?.on(Hls.Events.ERROR, (_e, data) => {
        if (data.fatal) side.deckError(el)
      })
      return { el, chain }
    } catch {
      if (!stale()) release({ el, chain })
      return null
    }
  }

  return {
    now: () => side.ctx()?.currentTime ?? 0,
    get nyquist() {
      return (side.ctx()?.sampleRate ?? 48_000) / 2
    },
    settings: () =>
      blendSettings({
        type: settings.get('audio.blend_type'),
        length: settings.get('audio.blend_length'),
        cut: settings.get('audio.blend_cut'),
        tempo: settings.get('audio.blend_tempo'),
        key: settings.get('audio.blend_key'),
      }),
    analysis: (ref) => side.analysis(ref),
    sound: async (ref) => {
      const cur = { rate: tempo.rate, pitch: tempo.pitch, linked: tempo.linked }
      const s = await api.trackSound(ref).catch(() => null)
      return ownSound(s, tempo.keep, cur)
    },
    load,
    promote(deck, listenedMs) {
      const h = held.get(deck.el)
      if (!h?.stream || !h.track) return
      held.delete(deck.el)
      const oldHls = side.promote(deck.el, h.hls, h.stream, h.track, listenedMs)
      // прежний текущий дек контроллер отпустит через `release` — вместе с его hls.js
      const prev = side.otherDeck()
      if (prev) held.set(prev, { hls: oldHls, stream: null, track: null })
    },
    release,
    hold: (on) => side.hold(on),
  }
}
