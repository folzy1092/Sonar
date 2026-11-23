// «Свести для вечеринки» (docs/BLEND.md §9): плейлист играется сведением в своём порядке. В «Далее»
// всегда один следующий — его ставит вечеринка; когда досчитывается анализ, ещё не готовый
// следующий меняется на лучший готовый. Порядок и дуга энергии — `party-core.ts`.
// Контекст плеера — `party:<контекст плейлиста>`: пока он такой, сведение включено само.

import { untrack } from 'svelte'
import type { Track } from '../../lib/api'
import { t } from '../../lib/i18n.svelte'
import { offline } from '../../lib/offline.svelte'
import { player } from '../player.svelte'
import { tempo } from '../tempo.svelte'
import type { BlendAnalysis } from './analysis'
import { blendAnalysis } from './analyze.svelte'
import { PartyOrder, isPartyContext, partyBase, partyContext, trackEnergy, type PartyLook } from './party-core'
import { plan } from './planner'
import { currentBlendSettings } from './player-host'

/** Менять уже поставленный следующий, только если до конца текущего больше: потом грузится поток. */
const SWAP_GUARD_MS = 40_000
/** Оценка перехода, когда текущий трек ещё не посчитан. */
const UNKNOWN_SCORE = 0.5

class PartyStore {
  /** Идущая вечеринка: контекст и название плейлиста. */
  active = $state<{ base: string; name: string } | null>(null)
  #order: PartyOrder | null = null
  #tracks = new Map<string, Track>()
  #played = new Set<string>()
  /** Следующий, которого поставила вечеринка (не трек, добавленный руками). */
  #queued: string | null = null
  #elapsedMs = 0
  #scores = new Map<string, number>()
  #started = false

  /** Начать с плейлиста: случайный из первых 10, дальше — по ходу. */
  async start(tracks: Track[], base: string, name: string) {
    const playable = tracks.filter((tr) => tr.available !== false && offline.allows(tr))
    if (!playable.length) return
    const order = new PartyOrder(playable.map((tr) => tr.ref))
    const first = playable.find((tr) => tr.ref === order.first)
    if (!first) return
    this.#reset()
    this.#order = order
    this.#tracks = new Map(playable.map((tr) => [tr.ref, tr]))
    this.active = { base, name }
    await player.playList([first], 0, partyContext(base), t('Вечеринка · {name}', { name }))
    void blendAnalysis.party([...order.pool])
  }

  /** Выйти: «Далее» остаётся как есть, контекст — снова плейлист. */
  end() {
    const active = this.active
    if (!active) return
    this.#reset()
    if (isPartyContext(player.context)) {
      player.context = partyBase(player.context)
      player.contextTitle = active.name
    }
  }

  init() {
    if (this.#started) return
    this.#started = true
    player.onTrackEnd((_, listenedMs) => {
      if (this.active) this.#elapsedMs += listenedMs
    })
    $effect.root(() => {
      // ушли в другой плейлист, волну, поиск — вечеринки больше нет
      $effect(() => {
        const ctx = player.context
        untrack(() => {
          if (this.active && !isPartyContext(ctx)) this.#reset()
        })
      })
      $effect(() => {
        if (!this.active) return
        // перезапуск: сменился текущий, «Далее» или досчитался чей-то анализ (state читает общий счётчик)
        void player.current?.ref
        void player.upNext[0]?.ref
        void player.blend.phase
        const first = untrack(() => this.#order?.pool[0])
        if (first) blendAnalysis.state(first)
        untrack(() => this.#step())
      })
    })
  }

  #step() {
    const order = this.#order
    const cur = player.current
    if (!order || !cur) return
    this.#commit(cur.ref)
    const head = player.upNext[0]?.ref
    // в «Далее» свой трек, добавленный руками, — сначала он
    if (head && head !== this.#queued) return
    const best = order.suggest(this.#elapsedMs + player.durationMs, this.#look, (next) => this.#score(cur.ref, next))
    if (!best || best === head) return
    if (!head) return this.#enqueue(best)
    const swap =
      !blendAnalysis.peek(head) &&
      !!blendAnalysis.peek(best) &&
      player.blend.phase === 'idle' &&
      player.durationMs - player.positionMs > SWAP_GUARD_MS
    if (!swap) return
    player.removeUpcoming(0)
    this.#enqueue(best)
  }

  /** Заиграл трек плейлиста — сдвинуть дугу, добрать пул и отдать новых на анализ. */
  #commit(ref: string) {
    const order = this.#order
    if (!order || this.#played.has(ref) || !this.#tracks.has(ref)) return
    this.#played.add(ref)
    if (this.#queued === ref) this.#queued = null
    const a = blendAnalysis.peek(ref)
    order.commit(ref, a ? trackEnergy(a) : null, this.#elapsedMs)
    const added = order.refill((r) => blendAnalysis.state(r) === 'failed')
    if (added.length) void blendAnalysis.party(added)
  }

  #enqueue(ref: string) {
    const track = this.#tracks.get(ref)
    if (!track) return
    this.#queued = ref
    void player.addToQueue([track], true)
  }

  #look = (ref: string): PartyLook => {
    const analysis = blendAnalysis.peek(ref) ?? null
    return { analysis, failed: !analysis && blendAnalysis.state(ref) === 'failed' }
  }

  /** Лучший план перехода текущий → кандидат, 0…1; посчитанное запоминается на пару. */
  #score(curRef: string, next: BlendAnalysis): number {
    const a = blendAnalysis.peek(curRef)
    if (!a) return UNKNOWN_SCORE
    const key = `${curRef}>${next.ref}`
    const known = this.#scores.get(key)
    if (known !== undefined) return known
    const opts = { ...currentBlendSettings(), rateA: tempo.rate, linkedA: tempo.linked, rateB: 1, linkedB: tempo.linked }
    const score = plan(a, next, opts)[0]?.score ?? 0
    this.#scores.set(key, score)
    return score
  }

  #reset() {
    this.active = null
    this.#order = null
    this.#tracks = new Map()
    this.#played = new Set()
    this.#queued = null
    this.#elapsedMs = 0
    this.#scores = new Map()
  }
}

export const party = new PartyStore()
