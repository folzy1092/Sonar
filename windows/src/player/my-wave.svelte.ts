// Своя «Моя волна» (SPEC §3.7): порции по 10 треков от Rust (`wave_portion`), сессия — здесь:
// что уже выдано, какие артисты на паузе (два пропуска подряд), догрузка, когда очередь кончается.
// Сигналы — оценка исхода трека (`reward.ts`, docs/WAVE.md 1.3): ручной пропуск с минусом пишется в
// `skips`, два ранних пропуска артиста подряд — пауза, оценка ≥ +1 — «зашло»; 👎 — трек больше не
// попадёт в волну, текущий — сразу дальше. Артист везде — главный (`artistKey`, как в Rust).
// Волна учится на ходу (как у Яндекса): дослушанные и лайкнутые в этой сессии треки становятся
// сидами следующих порций, однократно пропущенные артисты теряют вес, частые артисты сессии
// уступают место другим. Стиль сессии (режим и «волна по треку») держится, пока волна играет —
// перемотка меняет трек, а не стиль.
import { untrack } from 'svelte'
import { api, errorText, type Track } from '../lib/api'
import { toast } from '../lib/toast.svelte'
import { player } from './player.svelte'
import { settings } from '../lib/settings.svelte'
import { library } from '../lib/library.svelte'
import { artistKey, reward } from './reward'

export const WAVE_CONTEXT = 'wave'

/** Режимы волны — кнопка под «Моя волна» на главной (клик — следующий). Настроение Rust угадывает
 *  по жанру, тегам и названию (wave.rs `mood_fit`), «Незнакомое» — артисты, которых ты не слушал.
 *  Во всех режимах учитывается время суток: кого ты обычно слушаешь в эти часы. */
export const WAVE_MODES = [
  { id: 'own', title: 'Своя', sub: 'по твоим лайкам', icon: 'heart' },
  { id: 'hard', title: 'Жёсткая', sub: 'фонк, рэйдж, рок', icon: 'bolt' },
  { id: 'calm', title: 'Спокойная', sub: 'чилл, лоу-фай, акустика', icon: 'moon' },
  { id: 'sad', title: 'Грустная', sub: 'когда накрыло', icon: 'cloudDown' },
  { id: 'fun', title: 'Весёлая', sub: 'поп, хаус, движ', icon: 'sun' },
  { id: 'new', title: 'Незнакомое', sub: 'новые для тебя артисты', icon: 'disc' },
] as const
export type WaveMode = (typeof WAVE_MODES)[number]['id']

/** Режим и часовой пояс — в каждый запрос порции. */
function ctx() {
  return { mode: settings.get('wave.mode'), tz_min: new Date().getTimezoneOffset() }
}
/** Догружать, когда до конца очереди осталось столько треков. */
const PREFETCH_LEFT = 3
/** Сколько последних «хороших» треков сессии отправлять сидами. */
const SESSION_SEEDS = 4

class Wave {
  loading = $state(false)
  error = $state<string | null>(null)
  /** Заранее подобранная порция — обложки на главной и мгновенный старт. */
  preview = $state<Track[]>([])
  /** Обложки на главной — «лицо» стиля волны. Задаются при подборе порции, включении и смене
   *  режима и **не меняются от перемотки**: они выбирают стиль, а не показывают очередь. */
  covers = $state<Track[]>([])
  /** «Волна по треку»: стиль сессии, держится во всех следующих порциях. */
  seed = $state<Track | null>(null)
  /** 👎 — чтобы кнопка показывала состояние. */
  disliked = $state<Set<string>>(new Set())

  active = $derived(player.context === WAVE_CONTEXT)

  private served = new Set<string>()
  private paused = new Set<string>()
  private skipRun = new Map<string, number>()
  /** Дослушанные / лайкнутые в сессии — сиды следующих порций (новые в конце). */
  private good: Track[] = []
  /** Артисты, пропущенные в сессии хотя бы раз, — мягкий минус. */
  private skipped = new Set<string>()
  /** Сколько раз артист уже звучал в сессии. */
  private servedArtists: string[] = []
  private previewAt = 0
  private started = false

  init() {
    if (this.started) return
    this.started = true
    void api
      .dislikedRefs()
      .then((r) => (this.disliked = new Set(r)))
      .catch(() => {})
    player.onTrackEnd((t, listened, skipped) => this.onEnd(t, listened, skipped))
    // «Похожие после очереди» (`general.similar_autoplay`): очередь кончилась — волна по последнему треку
    player.onQueueEnd = (last) => {
      if (player.context === WAVE_CONTEXT || player.repeat !== 'off' || !settings.get('general.similar_autoplay')) return false
      void this.start(last, false)
      return true
    }
    $effect.root(() => {
      $effect(() => {
        if (player.context !== WAVE_CONTEXT) return
        const left = player.order.length - 1 - player.pos
        if (left < PREFETCH_LEFT) untrack(() => void this.more())
      })
    })
  }

  /** Подобрать порцию заранее (главная), не чаще раза в 10 минут. */
  async prefetch(force = false) {
    if (this.loading || (!force && this.preview.length && Date.now() - this.previewAt < 600_000)) return
    this.loading = true
    try {
      this.preview = await api.wavePortion({ exclude: [], paused_artists: [], ...ctx() })
      this.previewAt = Date.now()
      if (!this.active) this.covers = this.preview.slice(0, 3)
      this.error = null
    } catch (e) {
      this.error = errorText(e)
    } finally {
      this.loading = false
    }
  }

  /** Включить волну. `seed` — «Волна по треку»: только похожие на него; `withSeed` — он играет первым. */
  async start(seed?: Track, withSeed = true, firstRef?: string) {
    this.served = new Set()
    this.paused = new Set()
    this.skipRun = new Map()
    this.good = []
    this.skipped = new Set()
    this.servedArtists = []
    this.seed = seed ?? null
    let tracks: Track[]
    if (!seed && this.preview.length) {
      tracks = this.preview
      this.preview = []
    } else {
      this.loading = true
      try {
        tracks = await api.wavePortion({ seed: seed ?? null, ...ctx() })
        this.error = null
      } catch (e) {
        this.error = errorText(e)
        toast.show(this.error)
        return
      } finally {
        this.loading = false
      }
    }
    const rest = seed ? tracks.filter((t) => t.ref !== seed.ref) : tracks
    let list = seed && withSeed ? [seed, ...rest] : rest
    // «С этого трека» — клик по обложке на главной: он играет первым, остальные — следом
    const at = firstRef ? list.findIndex((t) => t.ref === firstRef) : -1
    if (at > 0) list = [list[at], ...list.slice(0, at), ...list.slice(at + 1)]
    if (!list.length) {
      toast.show('Волне пока нечего предложить')
      return
    }
    for (const t of list) this.serve(t)
    // обложки — только если их ещё нет: клик по обложке выбирает стиль, сами обложки остаются
    if (!this.covers.length) this.covers = list.slice(0, 3)
    player.shuffle = false
    await player.playList(list, 0, WAVE_CONTEXT, seed ? `Волна по «${seed.title}»` : 'Моя волна')
  }

  get mode(): WaveMode {
    return settings.get('wave.mode')
  }

  /** Следующий режим по кругу. Волна играет — сразу переключается на новый режим, иначе
   *  заранее подбирается порция под него (обложки на главной). */
  async nextMode() {
    const i = WAVE_MODES.findIndex((m) => m.id === this.mode)
    settings.set('wave.mode', WAVE_MODES[(i + 1) % WAVE_MODES.length].id)
    this.preview = []
    this.seed = null
    this.covers = []
    if (this.active) await this.start()
    else await this.prefetch(true)
  }

  /** Играет волна — пауза/продолжить, иначе — включить. */
  toggle() {
    if (this.active && player.current) player.toggle()
    else void this.start()
  }

  /** Догрузить следующую порцию в конец очереди. */
  async more() {
    if (this.loading) return
    this.loading = true
    try {
      const tracks = await api.wavePortion({
        exclude: [...this.served],
        paused_artists: [...this.paused],
        seed: this.seed,
        session: this.good.slice(-SESSION_SEEDS),
        skipped_artists: [...this.skipped],
        served_artists: this.servedArtists,
        ...ctx(),
      })
      if (player.context !== WAVE_CONTEXT) return
      const fresh = tracks.filter((t) => !this.served.has(t.ref))
      for (const t of fresh) this.serve(t)
      if (fresh.length) await player.addToQueue(fresh, false)
      this.error = null
    } catch (e) {
      this.error = errorText(e)
    } finally {
      this.loading = false
    }
  }

  isDisliked(ref: string | null | undefined) {
    return !!ref && this.disliked.has(ref)
  }

  /** 👎: больше не ставить; если это текущий трек — сразу следующий. Повторно — отменить. */
  async dislike(track: Track) {
    const on = !this.disliked.has(track.ref)
    const next = new Set(this.disliked)
    if (on) next.add(track.ref)
    else next.delete(track.ref)
    this.disliked = next
    try {
      await api.waveFeedback(on ? 'dislike' : 'undislike', track)
    } catch (e) {
      toast.show(errorText(e))
      return
    }
    if (!on) {
      toast.show('Трек снова может попасть в волну')
      return
    }
    toast.show('Больше не поставим этот трек')
    if (player.current?.ref === track.ref) void player.next()
  }

  private serve(t: Track) {
    this.served.add(t.ref)
    this.servedArtists.push(artistKey(t))
  }

  private onEnd(t: Track, listened: number, skipped: boolean) {
    if (player.context !== WAVE_CONTEXT) return
    const artist = artistKey(t)
    const r = reward({
      listenedMs: listened,
      durationMs: t.duration_ms,
      manualSkip: skipped,
      liked: library.isLiked(t.ref),
      disliked: this.disliked.has(t.ref),
    })
    // ручной пропуск с минусом — в `skips` (минус артисту и треку)
    if (skipped && r < 0) void api.waveFeedback('skip', t, listened).catch(() => {})
    if (r < 0) this.skipped.add(artist)
    // пауза артиста — два ранних пропуска подряд (−1; 👎 — тоже не «зашло», но считаем отдельно)
    if (r === -1) {
      const n = (this.skipRun.get(artist) ?? 0) + 1
      this.skipRun.set(artist, n)
      if (n >= 2) this.paused.add(artist)
    } else {
      this.skipRun.delete(artist)
    }
    // зашло (≥ +1: дослушал или лайкнул) — волна дальше тянется к этому треку
    if (r >= 1) {
      this.skipped.delete(artist)
      this.good = [...this.good.filter((x) => x.ref !== t.ref), t]
    }
  }
}

export const wave = new Wave()
