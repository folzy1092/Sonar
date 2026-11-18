// Своя «Моя волна» (SPEC §3.7): порции по 10 треков от Rust (`wave_portion`), сессия — здесь:
// что уже выдано, какие артисты на паузе (два пропуска подряд), догрузка, когда очередь кончается.
// Сигналы — оценка исхода трека (`reward.ts`, docs/WAVE.md 1.3): ручной пропуск с минусом пишется в
// `skips`, два ранних пропуска артиста подряд — пауза, оценка ≥ +1 — «зашло»; 👎 — трек больше не
// попадёт в волну, текущий — сразу дальше. Артист везде — главный (`artistKey`, как в Rust).
// Волна учится на ходу (как у Яндекса): дослушанные и лайкнутые в этой сессии треки становятся
// сидами следующих порций, однократно пропущенные артисты теряют вес, теги пропущенных треков
// идут в минус (теги зашедших — в плюс), частые артисты сессии уступают место другим. Стиль сессии (режим и «волна по треку») держится, пока волна играет —
// перемотка меняет трек, а не стиль. Два ранних пропуска подряд (`skip-series.ts`) пересобирают
// «Далее»: ещё не игравшие треки волны уходят, кроме ближайшего, и тут же приходит новая порция.
import { untrack } from 'svelte'
import { api, errorText, type Track } from '../lib/api'
import { toast } from '../lib/toast.svelte'
import { player } from './player.svelte'
import { settings } from '../lib/settings.svelte'
import { library } from '../lib/library.svelte'
import { t } from '../lib/i18n.svelte'
import { artistKey, reward } from './reward'
import { SkipSeries } from './skip-series'

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

/** Режим, часовой пояс и сессия — в каждый запрос порции (сессия нужна журналу `wave_events`). */
function ctx(sid: string) {
  return { mode: settings.get('wave.mode'), tz_min: new Date().getTimezoneOffset(), session_id: sid }
}
/** Id сессии волны. `crypto.randomUUID` есть только в безопасном контексте — на всякий случай запасной путь. */
const newSessionId = () =>
  typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
/** Догружать, когда до конца очереди осталось столько треков. */
const PREFETCH_LEFT = 3
/** «Волна офлайн»: сколько следующих треков держать скачанными. */
const OFFLINE_AHEAD = 15
/** Сколько последних «хороших» треков сессии отправлять сидами. */
const SESSION_SEEDS = 4
/** Сколько последних пропущенных треков сессии отправлять — их теги идут в минус. */
const SESSION_BAD = 6

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
  /** Треки с оценкой исхода < 0 (новые в конце): теги пропущенного — в минус следующим порциям. */
  private bad: Track[] = []
  /** Сколько раз артист уже звучал в сессии. */
  private servedArtists: string[] = []
  private previewAt = 0
  /** Сессия, под которой подобрана `preview` (её исходы лягут в тот же журнал). */
  private previewSid = ''
  /** Сессия играющей волны — id для `wave_events`. */
  private sid = ''
  private started = false
  /** Серия ранних пропусков: две подряд пересобирают «Далее» (docs/WAVE.md, этап 5). */
  private series = new SkipSeries()
  /** Растёт, когда очередь пересобрана или волна началась заново: порция, запрошенная до этого,
   *  устарела и выбрасывается. */
  private epoch = 0
  /** Последний заказ «Волны офлайн» — тот же список второй раз не отправляем. */
  private offlineKey = ''
  /** Идущий запрос следующей порции — чтобы дождаться его после пересборки. */
  private moreRun: Promise<void> | null = null

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
      // «Волна офлайн» (Система → Хранилище): следующие треки волны — в кэш треков заранее.
      // Заказ обновляется, когда меняется сам список следующих (новая порция, пропуск), Rust качает по одному.
      $effect(() => {
        if (player.context !== WAVE_CONTEXT || !settings.get('storage.wave_offline') || !settings.get('storage.cache_tracks')) return
        const refs = player.order
          .slice(player.pos + 1, player.pos + 1 + OFFLINE_AHEAD)
          .map((i) => player.tracks[i]?.ref)
          .filter((r): r is string => !!r)
        const key = refs.join(',')
        if (!refs.length || key === this.offlineKey) return
        this.offlineKey = key
        void api.prefetchTracks(refs).catch(() => {})
      })
    })
  }

  /** «Лицо» волны на главной (обложки), если его ещё нет. После перезапуска плеер мог восстановить
   *  очередь волны — тогда обложки берём из неё (текущий и следующие), иначе подбираем порцию. */
  ensureCovers() {
    if (this.covers.length) return
    if (this.active) {
      const next = player.order.slice(player.pos, player.pos + 3).map((i) => player.tracks[i]).filter(Boolean)
      if (next.length) {
        this.covers = next
        return
      }
    }
    void this.prefetch()
  }

  private retries = 0

  /** Подобрать порцию заранее (главная), не чаще раза в 10 минут. */
  async prefetch(force = false) {
    if (this.loading || (!force && this.preview.length && Date.now() - this.previewAt < 600_000)) return
    this.loading = true
    try {
      const sid = newSessionId()
      this.preview = await api.wavePortion({ exclude: [], paused_artists: [], ...ctx(sid) })
      this.previewSid = sid
      this.previewAt = Date.now()
      if (!this.active || !this.covers.length) this.covers = this.preview.slice(0, 3)
      this.error = null
      this.retries = 0
    } catch (e) {
      this.error = errorText(e)
      // на старте сервисы могут ещё подключаться — пробуем ещё пару раз, чтобы главная не осталась пустой
      if (!this.covers.length && this.retries < 3) {
        this.retries++
        setTimeout(() => void this.prefetch(true), 4000 * this.retries)
      }
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
    this.bad = []
    this.skipped = new Set()
    this.servedArtists = []
    this.series.reset()
    this.epoch++
    this.seed = seed ?? null
    let tracks: Track[]
    let sid: string
    if (!seed && this.preview.length) {
      tracks = this.preview
      sid = this.previewSid
      this.preview = []
    } else {
      sid = newSessionId()
      this.loading = true
      try {
        tracks = await api.wavePortion({ seed: seed ?? null, ...ctx(sid) })
        this.error = null
      } catch (e) {
        this.error = errorText(e)
        toast.show(this.error)
        return
      } finally {
        this.loading = false
      }
    }
    this.sid = sid
    const rest = seed ? tracks.filter((t) => t.ref !== seed.ref) : tracks
    let list = seed && withSeed ? [seed, ...rest] : rest
    // «С этого трека» — клик по обложке на главной: он играет первым, остальные — следом
    const at = firstRef ? list.findIndex((t) => t.ref === firstRef) : -1
    if (at > 0) list = [list[at], ...list.slice(0, at), ...list.slice(at + 1)]
    if (!list.length) {
      toast.show(t('Волне пока нечего предложить'))
      return
    }
    for (const t of list) this.serve(t)
    // обложки — только если их ещё нет: клик по обложке выбирает стиль, сами обложки остаются
    if (!this.covers.length) this.covers = list.slice(0, 3)
    player.shuffle = false
    await player.playList(list, 0, WAVE_CONTEXT, seed ? t('Волна по «{title}»', { title: seed.title }) : t('Моя волна'))
  }

  get mode(): WaveMode {
    return settings.get('wave.mode')
  }

  /** Следующий режим по кругу. Волна играет — сразу переключается на новый режим, иначе
   *  заранее подбирается порция под него (обложки на главной). */
  async nextMode() {
    const i = WAVE_MODES.findIndex((m) => m.id === this.mode)
    await this.setMode(WAVE_MODES[(i + 1) % WAVE_MODES.length].id)
  }

  /** Режим волны (настроение). Волна играет или `play` — сразу включается в новом режиме,
   *  иначе заранее подбирается порция под него. Быстрое окно (Ctrl+K) включает сразу. */
  async setMode(mode: WaveMode, play = false) {
    settings.set('wave.mode', mode)
    this.preview = []
    this.seed = null
    this.covers = []
    if (this.active || play) await this.start()
    else await this.prefetch(true)
  }

  /** Играет волна — пауза/продолжить, иначе — включить. */
  toggle() {
    if (this.active && player.current) player.toggle()
    else void this.start()
  }

  /** Догрузить следующую порцию в конец очереди. Идёт запрос — ничего не делает. */
  more(): Promise<void> {
    if (this.loading) return this.moreRun ?? Promise.resolve()
    const run: Promise<void> = this.loadMore().finally(() => {
      if (this.moreRun === run) this.moreRun = null
    })
    this.moreRun = run
    return run
  }

  private async loadMore() {
    const epoch = this.epoch
    this.loading = true
    try {
      const tracks = await api.wavePortion({
        exclude: [...this.served],
        paused_artists: [...this.paused],
        seed: this.seed,
        session: this.good.slice(-SESSION_SEEDS),
        skipped_artists: [...this.skipped],
        skipped_tracks: this.bad.slice(-SESSION_BAD),
        served_artists: [...this.servedArtists],
        ...ctx(this.sid),
      })
      // очередь пересобрана или волна началась заново, пока шёл запрос, — порция подобрана под старое
      if (player.context !== WAVE_CONTEXT || epoch !== this.epoch) return
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

  /** Серия ранних пропусков: «Далее» подобрано под вкус, которого сейчас нет. Убираем ещё не
   *  игравшие треки волны, кроме ближайшего, и просим новую порцию с учётом пропусков. */
  private rebuild() {
    if (player.context !== WAVE_CONTEXT) return
    const gone = player.dropUpNext(1, (t) => this.served.has(t.ref))
    if (!gone.length) return
    this.epoch++
    // убранные не звучали — вернуть их в пул, иначе до конца сессии они выпадут из волны
    for (const t of gone) this.unserve(t)
    void this.refill()
  }

  private async refill() {
    // запрос, что шёл до пересборки, закончится и выбросит свою порцию — ждём его и просим заново
    await this.moreRun
    if (player.context === WAVE_CONTEXT) await this.more()
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
      toast.show(t('Трек снова может попасть в волну'))
      return
    }
    toast.show(t('Больше не поставим этот трек'))
    if (player.current?.ref === track.ref) void player.next()
  }

  private serve(t: Track) {
    this.served.add(t.ref)
    this.servedArtists.push(artistKey(t))
  }

  /** Обратное `serve`: трек так и не прозвучал. */
  private unserve(t: Track) {
    this.served.delete(t.ref)
    const i = this.servedArtists.lastIndexOf(artistKey(t))
    if (i >= 0) this.servedArtists.splice(i, 1)
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
    // исход каждого трека волны — в журнал `wave_events` (по нему `wave_stats` и подбор весов)
    if (this.sid) void api.waveFeedback('end', t, listened, { sessionId: this.sid, reward: r }).catch(() => {})
    // ручной пропуск с минусом — в `skips` (минус артисту и треку)
    if (skipped && r < 0) void api.waveFeedback('skip', t, listened).catch(() => {})
    if (r < 0) {
      this.skipped.add(artist)
      this.bad = [...this.bad.filter((x) => x.ref !== t.ref), t].slice(-SESSION_BAD * 2)
    }
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
      this.bad = this.bad.filter((x) => x.ref !== t.ref)
      this.good = [...this.good.filter((x) => x.ref !== t.ref), t]
    }
    // два ранних пропуска подряд — пересобрать «Далее». Хук зовётся до смены трека (`next`, `jumpTo`),
    // поэтому очередь трогаем после: микрозадача идёт, когда плеер уже переключил позицию.
    if (this.series.push(r, skipped, Date.now())) queueMicrotask(() => this.rebuild())
  }
}

export const wave = new Wave()
