// Автоплей похожих как в SoundCloud («Autoplay related tracks»): любая очередь — поиск, Любимые,
// плейлист, альбом, исполнитель — не обрывается. Когда до конца остаётся меньше трёх треков,
// в конец заранее дописываются похожие (их видно в «Далее» отдельным блоком под тумблером), и так
// дальше, пока слушаешь. Похожие ищутся от последнего трека очереди и от случайного трека из
// твоей части очереди — чтобы продолжение держалось темы плейлиста, а не уплывало по цепочке.
// Тумблер — `general.similar_autoplay` (в панели «Далее» и в Настройки → Очередь); выключил —
// ещё не игравшие похожие убираются. В своей волне не работает: она и так бесконечная.
import { untrack } from 'svelte'
import { api, type Track } from '../lib/api'
import { settings } from '../lib/settings.svelte'
import { player } from './player.svelte'
import { WAVE_CONTEXT, wave } from './my-wave.svelte'

/** Догружать, когда до конца очереди осталось меньше стольких треков. */
const LEFT = 3
/** Сколько похожих дописывать за раз. */
const BATCH = 10
/** Сколько похожих спрашивать у каждого сида. */
const PER_SEED = 20

/**
 * Похожие для продолжения: чередуются списки от разных сидов, без треков, которые уже есть в
 * очереди, без 👎, недоступных и повторов; не больше `n`.
 */
export function freshSimilar(lists: Track[][], inQueue: Set<string>, disliked: (ref: string) => boolean, n: number): Track[] {
  const seen = new Set(inQueue)
  const out: Track[] = []
  const longest = Math.max(0, ...lists.map((l) => l.length))
  for (let i = 0; i < longest && out.length < n; i++) {
    for (const list of lists) {
      const t = list[i]
      if (!t || t.available === false || disliked(t.ref) || seen.has(t.ref)) continue
      seen.add(t.ref)
      out.push(t)
      if (out.length >= n) break
    }
  }
  return out
}

/** Сиды: последний трек очереди и случайный трек из твоей (не автоплейной) части. */
export function autoplaySeeds(queue: Track[], auto: Set<string>, rand = Math.random): Track[] {
  const last = queue.at(-1)
  if (!last) return []
  const own = queue.filter((t) => !auto.has(t.ref) && t.ref !== last.ref)
  const extra = own.length ? own[Math.floor(rand() * own.length)] : null
  return extra ? [last, extra] : [last]
}

class Autoplay {
  loading = $state(false)
  /** Очередь, на которой похожих не нашлось, — не долбить сервис, пока она не изменится. */
  private dead = ''
  private started = false

  get on() {
    return settings.get('general.similar_autoplay')
  }

  set(on: boolean) {
    settings.set('general.similar_autoplay', on)
  }

  init() {
    if (this.started) return
    this.started = true
    $effect.root(() => {
      $effect(() => {
        if (!this.on || player.context === WAVE_CONTEXT || player.repeat !== 'off' || !player.current) return
        const left = player.order.length - 1 - player.pos
        if (left < LEFT) untrack(() => void this.fill())
      })
      // выключили — ещё не игравшие похожие уходят из «Далее»
      $effect(() => {
        if (!this.on) untrack(() => player.dropAuto())
      })
    })
  }

  private async fill() {
    if (this.loading) return
    const queue = player.order.map((i) => player.tracks[i]).filter(Boolean)
    const key = `${player.context}|${queue.length}|${queue.at(-1)?.ref}`
    if (key === this.dead) return
    const seeds = autoplaySeeds(queue, player.autoRefs)
    if (!seeds.length) return
    this.loading = true
    try {
      const lists = await Promise.all(seeds.map((s) => api.similarTracks(s.ref, PER_SEED).catch(() => [] as Track[])))
      // пока грузилось, включили другую очередь или выключили тумблер
      const now = player.order.map((i) => player.tracks[i])
      if (!this.on || now.at(-1)?.ref !== queue.at(-1)?.ref || player.context === WAVE_CONTEXT) return
      const next = freshSimilar(lists, new Set(player.tracks.map((t) => t.ref)), (r) => wave.isDisliked(r), BATCH)
      if (next.length) await player.addToQueue(next, false, true)
      else this.dead = key
    } finally {
      this.loading = false
    }
  }
}

export const autoplay = new Autoplay()

/** Трек из поиска, как в SoundCloud: играет он, а следом — похожие на него (автоплей допишет). */
export async function playStation(t: Track, context: string | null = 'search') {
  await player.playList([t], 0, context, `Похожее на «${t.title}»`)
}
