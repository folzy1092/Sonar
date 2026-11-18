// Движок плеера на <audio> (SPEC §9.2): поток с локального аудио-сервера Rust, HLS SoundCloud —
// через hls.js. Очередь, повтор, перемешивание, громкость, режим скорости, медиа-клавиши,
// запись player_state и plays в локальную базу (формат API.md §5).
// Два элемента для бесшовности и кроссфейда, GainNode нормализации — позже (W5).
import Hls from 'hls.js'
import { untrack } from 'svelte'
import { api, errorText, onMediaControl, type PlayerState, type Repeat, type StreamUrl, type Track } from '../lib/api'
import { eq } from './eq.svelte'
import { Leveler } from './leveler'
import { Effects } from './effects'
import { pitchRatio, tempo } from './tempo.svelte'
import { settings } from '../lib/settings.svelte'
import { isFallbackError } from '../lib/services'
import { fallbackToast, type Via } from '../lib/fallback'
import { t } from '../lib/i18n.svelte'
import { playableQueue } from '../lib/local'
import { isLocalRef } from '../lib/services'
import { Clock } from '../lyrics/core/clock'
import { countsAsPlay, dropUpcoming, enqueue, enqueueAt, fallbackSkipPos, makeOrder, nextPos, nextRepeat, prevPos } from './queue'
import { toast } from '../lib/toast.svelte'


const HEARTBEAT_MS = 30_000

class Player {
  tracks = $state<Track[]>([])
  /** Порядок воспроизведения: индексы в `tracks` (перемешанный, если shuffle). */
  order = $state<number[]>([])
  pos = $state(0)
  /** Стабильные id элементов очереди, параллельно `tracks` (ключи строк очереди на странице плеера:
   *  при «вперёд / назад» строка переезжает, а не появляется заново — player/queue-view.ts). */
  entryIds = $state<number[]>([])
  private lastEntryId = 0
  context = $state<string | null>(null)
  /** Название контекста для очереди («Любимые», имя плейлиста, альбома, исполнителя). */
  contextTitle = $state<string | null>(null)

  playing = $state(false)
  /** Очередь доиграла до конца (стоит на последнем треке, пауза): «Слушать» начинает подборку заново
   *  (lib/listen.ts), а не продолжает последний трек. Снимается при загрузке трека и при игре. */
  ended = $state(false)
  loading = $state(false)
  /** Прогресс загрузки трека для анимации загрузки (components/LoadFx.svelte): `null` — не грузится,
   *  0…1 — этапы (ссылка на поток → метаданные / манифест → первый фрагмент → можно играть),
   *  −1 — сколько осталось, неизвестно (застряли посреди трека). */
  loadProgress = $state<number | null>(null)
  private loadDone: ReturnType<typeof setTimeout> | null = null

  /** Отметить этап загрузки: прогресс только растёт; 1 — готово, через 250 мс сброс. */
  private stage(p: number) {
    if (this.loadDone) clearTimeout(this.loadDone)
    this.loadDone = null
    if (p < 0) {
      this.loadProgress = -1
      return
    }
    const cur = this.loadProgress ?? 0
    this.loadProgress = p === 0 ? 0 : Math.max(cur < 0 ? 0 : cur, p)
    if (p >= 1) this.loadDone = setTimeout(() => (this.loadProgress = null), 250)
  }
  error = $state<string | null>(null)
  /** Сервис трека сам не играет (Spotify без Premium) — нужен резервный сервис, не сбой. */
  fallbackNeeded = $state(false)
  /** Трек играет не со своего сервиса (резервный сервис): откуда и почему; null — со своего. */
  via = $state<Via | null>(null)
  positionMs = $state(0)
  durationMs = $state(0)
  /** Реальный формат потока для плашки: «AAC 160», «MP3 320», «FLAC». */
  quality = $state<string | null>(null)

  volume = $state(0.8)
  repeat = $state<Repeat>('off')
  shuffle = $state(false)

  current = $derived<Track | null>(this.tracks[this.order[this.pos]] ?? null)
  /** Треки, которые дописал автоплей похожих (`autoplay.svelte.ts`), — в «Далее» они идут
   *  отдельным блоком под тумблером, свои «В очередь» встают перед ними. Новая очередь — пусто. */
  autoRefs = $state(new Set<string>())

  /** «Далее» — треки после текущего в порядке воспроизведения. */
  upNext = $derived(this.order.slice(this.pos + 1).map((i) => this.tracks[i]))

  /** Активный «дек» — тот, что сейчас звучит и управляется. Реактивный: тексту песни нужно знать,
   *  что после кроссфейда играет другой <audio>. */
  private audio = $state.raw<HTMLAudioElement | null>(null)
  /** Два дека для кроссфейда и бесшовного: следующий трек стартует на втором, пока первый затухает. */
  private decks: HTMLAudioElement[] = []
  /** Громкость каждого дека в Web Audio (кроссфейд меняет их местами). */
  private deckGain = new Map<HTMLAudioElement, GainNode>()
  /** Затухающий дек после перехода: остановится по таймеру. */
  private fading: { el: HTMLAudioElement; hls: Hls | null; timer: ReturnType<typeof setTimeout> } | null = null
  private crossing = false
  /** Для какого следующего трека уже заранее запрошен поток. */
  private warmedFor: string | null = null
  private hls: Hls | null = null
  private loadToken = 0
  private listenedMs = 0
  private startedAt = 0
  private lastTick = 0
  private heartbeat: ReturnType<typeof setInterval> | null = null
  /** Часы таймлайна как у Dotify (PlaybackClock): между редкими timeupdate позиция идёт от якоря
   *  по performance.now() с учётом скорости, полосы прогресса рисуются каждый кадр. */
  private clock = new Clock()
  private frameSubs = new Set<(ms: number) => void>()
  private raf = 0
  private offMedia: (() => void) | null = null
  private ctx: AudioContext | null = null
  /** Нормализация громкости (`audio.normalize`). */
  leveler: Leveler | null = null
  private effects: Effects | null = null
  /** Кто слушает конец трека (своя волна): трек, сколько прослушано, пропущен ли вручную. */
  private endHooks = new Set<(t: Track, listenedMs: number, skipped: boolean) => void>()
  /** Очередь доиграла до конца: вернуть true, если кто-то продолжил (похожие после очереди). */
  onQueueEnd: ((last: Track) => boolean) | null = null
  /** Спектр звука для волны на странице плеера (Web Audio). */
  analyser: AnalyserNode | null = null

  /** Сам <audio> — тексту нужны его события для своих часов (lyrics/LyricsView). */
  get media(): HTMLAudioElement | null {
    return this.audio
  }

  init() {
    if (this.audio) return
    const make = () => {
      const el = new Audio()
      el.preload = 'auto'
      // поток идёт с 127.0.0.1 с CORS — без этого Web Audio получит тишину
      el.crossOrigin = 'anonymous'
      this.listen(el)
      return el
    }
    this.decks = [make(), make()]
    this.audio = this.decks[0]
    this.connectAnalyser()
    this.applyVolume()
    this.applySpeed()
    this.initRest()
  }

  /** События дека — только от активного: затухающий после кроссфейда не трогает плеер. */
  private listen(a: HTMLAudioElement) {
    const own =
      <E extends Event>(fn: (e: E) => void) =>
      (e: E) => {
        if (a === this.audio) fn(e)
      }
    const addEventListener = (type: string, fn: (e: Event) => void) => a.addEventListener(type, own(fn))

    addEventListener('play', () => this.setPlaying(true))
    addEventListener('pause', () => this.setPlaying(false))
    addEventListener('waiting', () => {
      this.loading = true
      // буфер кончился посреди трека — сколько ждать, неизвестно
      if (this.loadProgress === null) this.stage(-1)
    })
    addEventListener('playing', () => {
      this.loading = false
      if (this.loadProgress !== null) this.stage(1)
    })
    addEventListener('canplay', () => {
      this.loading = false
      if (this.loadProgress !== null) this.stage(1)
    })
    addEventListener('loadedmetadata', () => {
      if (this.loadProgress !== null && this.loadProgress >= 0) this.stage(0.7)
    })
    addEventListener('durationchange', () => {
      if (Number.isFinite(a.duration) && a.duration > 0) this.durationMs = a.duration * 1000
    })
    addEventListener('timeupdate', () => this.onTime())
    // до метаданных currentTime = 0 ничего не значит (смена src) — держим позицию из place()
    const tick = (fn: () => void) => () => {
      if (a.readyState === HTMLMediaElement.HAVE_NOTHING) return
      fn()
      this.syncFrames()
    }
    const now = () => performance.now()
    addEventListener('timeupdate', tick(() => this.clock.sample(a.currentTime, now())))
    addEventListener('playing', tick(() => this.clock.play(a.currentTime, now(), a.playbackRate)))
    addEventListener('pause', tick(() => this.clock.hold(a.currentTime)))
    addEventListener('waiting', tick(() => this.clock.hold(a.currentTime)))
    addEventListener('seeking', tick(() => this.clock.seek(a.currentTime)))
    addEventListener(
      'seeked',
      tick(() => (a.paused ? this.clock.hold(a.currentTime) : this.clock.play(a.currentTime, now(), a.playbackRate))),
    )
    addEventListener('ratechange', tick(() => this.clock.setRate(a.playbackRate, a.currentTime, now())))
    addEventListener('ended', () => this.onEnded())
    addEventListener('error', () => {
      const message = a.error?.message || t('не удалось воспроизвести')
      if (a === this.audio) void this.onMediaError(message)
      else this.onError(message)
    })
  }

  private initRest() {
    this.offMedia = onMediaControl((action) => {
      if (action === 'play') void this.play()
      else if (action === 'pause' || action === 'stop') this.pause()
      else if (action === 'toggle') this.toggle()
      else if (action === 'next') void this.next()
      else if (action === 'previous') void this.prev()
      else if (action.startsWith('seek:')) this.seek(Number(action.slice(5)))
    })

    void this.restore()
    void eq.load()
    // нормализация громкости — включается и выключается сразу, без перезапуска трека
    $effect.root(() => {
      $effect(() => {
        const on = settings.get('audio.normalize')
        untrack(() => this.leveler?.setEnabled(on))
      })
      // меню скорости: любое изменение — сразу в звук
      $effect(() => {
        void [tempo.rate, tempo.pitch, tempo.linked, tempo.wet]
        untrack(() => this.applySpeed())
      })
    })
  }

  /** Полная остановка: при подмене модуля в dev (HMR), иначе старый <audio> играет «вторым потоком». */
  destroy() {
    this.hls?.destroy()
    this.hls = null
    for (const d of this.decks) {
      d.pause()
      d.removeAttribute('src')
      d.load()
    }
    if (this.fading) clearTimeout(this.fading.timer)
    this.fading = null
    this.audio = null
    if (this.heartbeat) clearInterval(this.heartbeat)
    cancelAnimationFrame(this.raf)
    this.raf = 0
    this.offMedia?.()
    void this.ctx?.close()
  }

  private connectAnalyser() {
    try {
      const ctx = new AudioContext()
      // оба дека → свой регулятор (кроссфейд) → общий вход эквалайзера
      const mix = ctx.createGain()
      for (const d of this.decks) {
        const g = ctx.createGain()
        g.gain.value = d === this.audio ? 1 : 0
        ctx.createMediaElementSource(d).connect(g)
        g.connect(mix)
        this.deckGain.set(d, g)
      }
      const analyser = ctx.createAnalyser()
      analyser.fftSize = 2048
      analyser.smoothingTimeConstant = 0.82
      // источник → эквалайзер → выравниватель громкости → тон и реверб → анализатор волны → выход
      const leveler = new Leveler(ctx)
      const effects = new Effects(ctx)
      eq.connect(ctx, mix, leveler.input)
      leveler.node.connect(effects.input)
      effects.output.connect(analyser)
      this.effects = effects
      analyser.connect(ctx.destination)
      this.leveler = leveler
      this.ctx = ctx
      this.analyser = analyser
    } catch {
      this.analyser = null
    }
  }

  onTrackEnd(cb: (t: Track, listenedMs: number, skipped: boolean) => void): () => void {
    this.endHooks.add(cb)
    return () => this.endHooks.delete(cb)
  }

  // ——— очередь ———

  /** Играть список с трека `index`. `context` — откуда (search, favorites, playlist:<id>…). */
  async playList(all: Track[], start: number, context: string | null, title: string | null = null) {
    // пропавшие файлы с компьютера в очередь не идут — на них плеер встал бы с ошибкой
    const { tracks, index } = playableQueue(all, start)
    if (!tracks.length) return
    this.finishPlay()
    this.tracks = tracks
    this.entryIds = this.freshIds(tracks.length)
    this.context = context
    this.contextTitle = title
    this.autoRefs = new Set()
    this.order = makeOrder(tracks.length, index, this.shuffle)
    this.pos = this.shuffle ? 0 : index
    void api.cacheTracks(tracks).catch(() => {})
    await this.load(true)
  }

  /** «Перемешать»: включить перемешивание и начать со случайного трека. */
  async playShuffled(tracks: Track[], context: string | null, title: string | null = null) {
    if (!tracks.length) return
    this.shuffle = true
    await this.playList(tracks, Math.floor(Math.random() * tracks.length), context, title)
  }

  /** «Следующим» (`next`) или «В очередь» (в конец, но перед похожими автоплея). Пустая очередь —
   *  сразу играет. `auto` — дописывает автоплей: в самый конец, с отметкой. */
  async addToQueue(all: Track[], next: boolean, auto = false) {
    const { tracks } = playableQueue(all, 0)
    if (!tracks.length) return
    if (!this.current) return this.playList(tracks, 0, 'queue')
    void api.cacheTracks(tracks).catch(() => {})
    let order = this.order
    const pos = this.pos
    const list = this.tracks.slice()
    const ids = this.syncedIds()
    // первое ещё не игравшее похожее автоплея — свои треки встают перед ним
    const firstAuto = next || auto ? -1 : order.findIndex((i, k) => k > pos && this.autoRefs.has(list[i]?.ref))
    let at = firstAuto
    for (const t of next ? [...tracks].reverse() : tracks) {
      list.push(t)
      ids.push(++this.lastEntryId)
      if (at >= 0) order = enqueueAt(order, at++, list.length - 1)
      else order = enqueue(order, pos, list.length - 1, next)
    }
    if (auto) this.autoRefs = new Set([...this.autoRefs, ...tracks.map((t) => t.ref)])
    this.tracks = list
    this.entryIds = ids
    this.order = order
    this.saveState()
  }

  /** Убрать трек из «Далее» (номер в upNext) — меню трека в очереди. */
  removeUpcoming(upNextIndex: number) {
    const at = this.pos + 1 + upNextIndex
    const idx = this.order[at]
    if (idx === undefined) return
    this.dropEntries((_, i) => i === idx)
    this.saveState()
  }

  /** Убрать из «Далее» похожие автоплея (тумблер выключили). Текущий и сыгранные остаются. */
  dropAuto() {
    const auto = this.autoRefs
    if (!auto.size) return
    this.dropEntries((t) => auto.has(t.ref))
    this.autoRefs = new Set()
    this.saveState()
  }

  /** Убрать из «Далее» ещё не игравшие треки, подходящие под `drop`, кроме `keep` ближайших
   *  (волна после серии пропусков: очередь подбиралась под вкус, которого сейчас нет). Вернёт убранные. */
  dropUpNext(keep: number, drop: (t: Track) => boolean): Track[] {
    const dropped = this.dropEntries(drop, keep)
    if (dropped.length) this.saveState()
    return dropped
  }

  /** Новые id для `n` элементов очереди. */
  private freshIds(n: number): number[] {
    return Array.from({ length: n }, () => ++this.lastEntryId)
  }

  /** id элементов очереди той же длины, что `tracks` (копия; не совпало — выдать новые). */
  private syncedIds(): number[] {
    return this.entryIds.length === this.tracks.length ? this.entryIds.slice() : this.freshIds(this.tracks.length)
  }

  /** Убрать из «Далее» не игравшие треки под `drop` (с номером в `tracks`), id уходят вместе с ними. */
  private dropEntries(drop: (t: Track, index: number) => boolean, keep = 0): Track[] {
    const ids = this.syncedIds()
    const rows = this.tracks.map((tr, i) => ({ tr, i, id: ids[i] }))
    const out = dropUpcoming(rows, this.order, this.pos, (x) => drop(x.tr, x.i), keep)
    if (!out.dropped.length) return []
    this.tracks = out.tracks.map((x) => x.tr)
    this.entryIds = out.tracks.map((x) => x.id)
    this.order = out.order
    return out.dropped.map((x) => x.tr)
  }

  /** Перейти к треку из «Далее» (номер в upNext). */
  async jumpTo(upNextIndex: number) {
    await this.playPos(this.pos + 1 + upNextIndex)
  }

  /** Сыграть трек с позиции `p` в порядке воспроизведения (строки «Ранее» и «Далее» в очереди). */
  async playPos(p: number) {
    if (!Number.isInteger(p) || p < 0 || p >= this.order.length) return
    this.finishPlay(true)
    this.pos = p
    await this.load(true)
  }

  async next(manual = true) {
    const p = nextPos(this.pos, this.order.length, this.repeat, manual)
    const last = this.current
    this.finishPlay(manual)
    if (p === null && last && this.onQueueEnd?.(last)) return
    if (p === null) {
      this.pause()
      this.seek(0)
      this.ended = true
      return
    }
    this.pos = p
    await this.load(true)
  }

  async prev() {
    if (this.positionMs > 3000) return this.seek(0)
    this.finishPlay()
    this.pos = prevPos(this.pos, this.order.length, this.repeat)
    await this.load(true)
  }

  toggleShuffle() {
    this.shuffle = !this.shuffle
    const cur = this.order[this.pos] ?? 0
    this.order = makeOrder(this.tracks.length, cur, this.shuffle)
    this.pos = this.shuffle ? 0 : cur
    this.saveState()
  }

  cycleRepeat() {
    this.repeat = nextRepeat(this.repeat)
    this.saveState()
  }

  // ——— управление ———

  async play() {
    if (!this.audio || !this.current) return
    if (!this.audio.src) return this.load(true, this.positionMs)
    try {
      await this.audio.play()
    } catch (e) {
      this.onError(errorText(e))
    }
  }

  pause() {
    this.endFade()
    this.audio?.pause()
  }

  toggle() {
    if (this.playing) this.pause()
    else void this.play()
  }

  seek(ms: number) {
    if (!this.audio) return
    const max = this.durationMs || this.current?.duration_ms || 0
    const t = Math.max(0, Math.min(ms, max))
    this.endFade()
    this.place(t)
    if (this.audio.src) this.audio.currentTime = t / 1000
    this.saveState()
    this.updateMedia()
  }

  setVolume(v: number) {
    this.volume = Math.max(0, Math.min(1, v))
    this.applyVolume()
    void api.setSetting('player.volume', this.volume).catch(() => {})
  }

  /** Устройство вывода (`audio.output_device`): звук идёт через Web Audio, поэтому меняем выход
   *  у AudioContext (`setSinkId`, Chromium 110+). Пустая строка — системное устройство. */
  async setOutput(deviceId: string) {
    const ctx = this.ctx as (AudioContext & { setSinkId?: (id: string) => Promise<void> }) | null
    try {
      await ctx?.setSinkId?.(deviceId)
    } catch {
      // устройство пропало — остаёмся на текущем
    }
  }

  // ——— внутреннее ———

  private applyVolume() {
    // квадрат — громкость на слух ровнее, чем линейная; duckK — приглушение на время звонка
    for (const d of this.decks) d.volume = this.volume * this.volume * this.duckK * this.sleepK
  }

  /** Множитель громкости таймера сна (`sleep.svelte.ts`): плавно гасит звук перед паузой. */
  private sleepK = 1

  setSleepFade(k: number) {
    this.sleepK = Math.max(0, Math.min(1, k))
    this.applyVolume()
  }

  /** Множитель громкости на время звонка: плавно 1 ↔ 0.2 за ~0.8 с. */
  private duckK = 1
  private duckRaf = 0
  /** Идёт ли звонок (calls.rs шлёт `call:active`, когда микрофон занят другим приложением). */
  inCall = $state(false)

  setCall(on: boolean) {
    this.inCall = on
    const target = on && settings.get('audio.duck_calls') ? 0.2 : 1
    // таймер, а не кадры: окно может быть свёрнуто в трей, а кадры там не идут
    clearTimeout(this.duckRaf)
    const from = this.duckK
    const t0 = performance.now()
    const step = () => {
      const k = Math.min(1, (performance.now() - t0) / 800)
      this.duckK = from + (target - from) * (1 - (1 - k) ** 3)
      this.applyVolume()
      if (k < 1) this.duckRaf = window.setTimeout(step, 30)
    }
    step()
  }

  /** Скорость, тон и реверб из меню скорости (`tempo.svelte.ts`). Тон связан со скоростью — его
   *  двигает сам <audio> (slowed / sped up); не связан — <audio> держит тон, а сдвиг делает `effects`. */
  private applySpeed() {
    if (!this.audio) return
    const rate = tempo.rate
    this.audio.preservesPitch = !tempo.linked
    this.audio.defaultPlaybackRate = rate
    this.audio.playbackRate = rate
    void this.effects?.setPitch(tempo.linked ? 1 : pitchRatio(tempo.pitch))
    this.effects?.setReverb(tempo.wet)
  }

  /** `crossfade` — зовёт кроссфейд: старый дек ещё затухает, громкость нового выставит сам переход.
   *  `fallbackSkips` — сколько треков подряд уже пропущено из-за «нужен резервный сервис». */
  private async load(autoplay: boolean, startMs = 0, crossfade = false, fallbackSkips = 0) {
    if (!crossfade) {
      this.endFade()
      this.gainTo(this.audio, 1, 0)
    }
    this.leveler?.trackChanged()
    tempo.trackChanged(this.current?.ref ?? null)
    const a = this.audio
    const track = this.current
    if (!a || !track) return
    const token = ++this.loadToken
    this.ended = false
    this.error = null
    this.fallbackNeeded = false
    this.via = null
    this.loading = true
    this.stage(0)
    this.durationMs = track.duration_ms
    this.place(startMs)
    this.hls?.destroy()
    this.hls = null
    this.quality = null
    a.removeAttribute('src')
    this.updateMedia()

    try {
      const s = await api.streamUrl(track.ref, track)
      if (token !== this.loadToken) return
      this.stage(0.35)
      this.announce(s)
      await this.attach(s, token, autoplay, startMs)
      this.localMisses = 0
      this.saveState()
    } catch (e) {
      // play() отклонён из-за ошибки потока — её уже подхватил onMediaError и ищет резервный сервис
      if (token !== this.loadToken || this.fallbackTried === token) return
      if (isFallbackError(track.ref, e) && this.skipFallback(autoplay, fallbackSkips + 1)) return
      this.fallbackNeeded = isFallbackError(track.ref, e)
      this.onError(errorText(e))
      // файл с компьютера пропал уже в очереди — дальше, а не стоп; круг без живых треков не крутим
      if (autoplay && isLocalRef(track.ref) && ++this.localMisses < this.order.length) void this.next(false)
    }
  }

  /** Поток в дек: HLS — через hls.js, файл — в <audio>; потом скорость и старт (`autoplay`). */
  private async attach(s: StreamUrl, token: number, autoplay: boolean, startMs: number) {
    const a = this.audio
    if (!a) return
    if (s.kind === 'hls' && Hls.isSupported()) {
      const hls = new Hls({ startPosition: startMs / 1000 })
      hls.on(Hls.Events.ERROR, (_e, data) => {
        if (data.fatal && token === this.loadToken) void this.onMediaError(`HLS: ${data.details}`)
      })
      hls.on(Hls.Events.MANIFEST_PARSED, () => token === this.loadToken && this.loadProgress !== null && this.stage(0.6))
      hls.on(Hls.Events.FRAG_LOADED, () => token === this.loadToken && this.loadProgress !== null && this.stage(0.9))
      hls.loadSource(s.url)
      hls.attachMedia(a)
      this.hls = hls
    } else {
      a.src = s.url
      if (startMs) a.currentTime = startMs / 1000
    }
    this.applySpeed()
    this.listenedMs = 0
    this.startedAt = Date.now()
    this.lastTick = 0
    if (autoplay) await a.play()
    else {
      this.loading = false
      this.stage(1)
    }
  }

  /** Плашка качества и всплывашка «Играет из YouTube Music — в SoundCloud недоступен». */
  private announce(s: StreamUrl) {
    this.quality = s.quality
    this.via = s.via
    const note = fallbackToast(s.via)
    if (note) toast.show(note)
  }

  /** Загрузка, для которой резервный сервис уже пробовали: второй раз не ищем, а показываем ошибку. */
  private fallbackTried = -1

  /** Свой поток открылся, но не играет (ошибка <audio> или hls.js) — тот же трек из резервного
   *  сервиса (`stream_fallback`), с того же места. Не нашёлся или резерв выключен — ошибка как раньше. */
  private async onMediaError(message: string) {
    const track = this.current
    const token = this.loadToken
    const canRetry = track && !isLocalRef(track.ref) && this.fallbackTried !== token && settings.get('audio.fallback')
    if (!track || !canRetry) return this.onError(message)
    this.fallbackTried = token
    const resume = this.playing || this.loading
    const startMs = this.positionMs
    this.loading = resume
    try {
      const s = await api.streamFallback(track.ref, track)
      if (token !== this.loadToken) return
      this.hls?.destroy()
      this.hls = null
      this.error = null
      this.announce(s)
      await this.attach(s, token, resume, startMs)
    } catch {
      if (token === this.loadToken) this.onError(message)
    }
  }

  /** Сколько пропавших файлов с компьютера подряд пропущено — чтобы не ходить по кругу. */
  private localMisses = 0

  /** Трек сам не играет (нужен резервный сервис) — не стоп, а следующий по очереди. Вся очередь
   *  такая — `false`: остаётся понятное состояние «нужен резервный сервис» в мини-плеере. */
  private skipFallback(autoplay: boolean, skips: number): boolean {
    if (!autoplay) return false
    const p = fallbackSkipPos(this.pos, this.order.length, this.repeat, skips)
    if (p === null) return false
    toast.show(t('Нужен резервный сервис — трек пропущен'))
    this.pos = p
    void this.load(true, 0, false, skips)
    return true
  }

  private onTime() {
    const a = this.audio!
    const ms = a.currentTime * 1000
    // считаем реально прослушанное: только маленькие шаги вперёд, без перемоток
    const delta = ms - this.lastTick
    if (this.playing && delta > 0 && delta < 2000) this.listenedMs += delta
    this.lastTick = ms
    this.positionMs = ms
    this.maybeCrossfade(a, ms)
  }

  /** Плавно (`sec`) выставить громкость дека в Web Audio; 0 с — сразу. */
  private gainTo(el: HTMLAudioElement | null, v: number, sec: number) {
    const g = el ? this.deckGain.get(el) : null
    if (!g || !this.ctx) return
    const t = this.ctx.currentTime
    g.gain.cancelScheduledValues(t)
    g.gain.setValueAtTime(g.gain.value, t)
    if (sec > 0) g.gain.linearRampToValueAtTime(v, t + sec)
    else g.gain.setValueAtTime(v, t)
  }

  /** Конец трека близко — кроссфейд (`audio.crossfade`, с) или бесшовная стыковка (`audio.gapless`).
   *  За 6 с до перехода поток следующего трека запрашивается заранее, чтобы старт был мгновенным. */
  private maybeCrossfade(a: HTMLAudioElement, ms: number) {
    if (this.crossing || this.loading || !this.playing || !this.ctx || this.repeat === 'one') return
    const dur = Number.isFinite(a.duration) && a.duration > 0 ? a.duration * 1000 : this.durationMs
    if (!dur || dur < 20_000) return
    const cf = Math.max(0, Number(settings.get('audio.crossfade')) || 0)
    const span = cf > 0 ? cf * 1000 : settings.get('audio.gapless') ? 250 : 0
    if (!span) return
    const p = nextPos(this.pos, this.order.length, this.repeat, false)
    if (p === null) return
    const next = this.tracks[this.order[p]]
    if (!next) return
    const left = dur - ms
    if (left < span + 6000 && this.warmedFor !== next.ref) {
      this.warmedFor = next.ref
      void api.streamUrl(next.ref, next).catch(() => {})
    }
    // timeupdate идёт ~4 раза в секунду — запас на один шаг
    if (left <= span + 260) void this.crossfade(p, span)
  }

  /** Переход на следующий трек внахлёст: он стартует на втором деке с нуля громкости, громкости
   *  плавно меняются местами, старый дек останавливается. Для приложения это обычный «следующий». */
  private async crossfade(p: number, span: number) {
    const old = this.audio
    const neu = this.decks.find((d) => d !== old)
    if (!old || !neu) return
    this.crossing = true
    this.endFade()
    this.finishPlay(false)
    const oldHls = this.hls
    this.hls = null
    this.gainTo(neu, 0, 0)
    this.audio = neu
    this.pos = p
    try {
      await this.load(true, 0, true)
    } finally {
      this.crossing = false
    }
    const sec = span / 1000
    this.gainTo(neu, 1, sec)
    this.gainTo(old, 0, sec)
    this.fading = { el: old, hls: oldHls, timer: setTimeout(() => this.endFade(), span + 250) }
  }

  /** Остановить затухающий дек (переход закончился или его прервали пауза, перемотка, другой трек). */
  private endFade() {
    const f = this.fading
    if (!f) return
    this.fading = null
    clearTimeout(f.timer)
    f.el.pause()
    f.hls?.destroy()
    f.el.removeAttribute('src')
    f.el.load()
    this.gainTo(f.el, 0, 0)
    this.gainTo(this.audio, 1, 0)
  }

  private onEnded() {
    void this.next(false)
  }

  private onError(message: string) {
    this.loading = false
    if (this.loadDone) clearTimeout(this.loadDone)
    this.loadProgress = null
    this.error = message
    this.playing = false
    this.updateMedia()
  }

  /** Позиция таймлайна (мс) на кадр `ts`: плавно между timeupdate, монотонно, в пределах трека. */
  frameMs(ts = performance.now()): number {
    const ms = this.clock.read(ts) * 1000
    const max = this.durationMs || this.current?.duration_ms || 0
    return max ? Math.min(ms, max) : ms
  }

  /** Полосы прогресса (мини-плеер, ползунок): `fn` получает позицию каждый кадр, пока играет, и
   *  один раз на паузе, перемотке, смене трека. Пишет прямо в DOM — плеер не перерисовывается.
   *  `positionMs` (подписи времени) по-прежнему обновляется по timeupdate. */
  onFrame(fn: (ms: number) => void): () => void {
    this.frameSubs.add(fn)
    fn(this.frameMs())
    this.syncFrames()
    return () => this.frameSubs.delete(fn)
  }

  /** Жёстко поставить позицию: перемотка, смена трека, восстановление сессии. */
  private place(ms: number) {
    this.positionMs = ms
    this.clock.seek(ms / 1000)
    this.syncFrames()
  }

  /** Отдать подписчикам текущую позицию и запустить кадры, если часы идут. */
  private syncFrames() {
    const v = this.frameMs()
    for (const fn of this.frameSubs) fn(v)
    if (!this.raf && this.frameSubs.size && this.clock.mode === 'running') this.raf = requestAnimationFrame(this.frame)
  }

  private frame = (ts: number) => {
    if (!this.frameSubs.size || this.clock.mode !== 'running') {
      this.raf = 0
      return
    }
    const v = this.frameMs(ts)
    for (const fn of this.frameSubs) fn(v)
    this.raf = requestAnimationFrame(this.frame)
  }

  private setPlaying(on: boolean) {
    this.playing = on
    if (on) this.ended = false
    if (on && this.ctx?.state === 'suspended') void this.ctx.resume()
    if (on) this.error = null
    if (this.heartbeat) clearInterval(this.heartbeat)
    this.heartbeat = on ? setInterval(() => this.saveState(), HEARTBEAT_MS) : null
    this.saveState()
    this.updateMedia()
  }

  /** Засчитать прослушивание текущего трека, если дослушали достаточно (SPEC §3.8). */
  private finishPlay(skipped = false) {
    const t = this.current
    if (!t || !this.startedAt) return
    const listened = Math.round(this.listenedMs)
    for (const cb of this.endHooks) cb(t, listened, skipped)
    if (countsAsPlay(listened, t.duration_ms)) {
      void api
        .recordPlay({ ref: t.ref, artist: t.artist, context: this.context, played_at: this.startedAt, listened_ms: listened })
        .catch(() => {})
    }
    this.startedAt = 0
    this.listenedMs = 0
  }

  private state(): PlayerState {
    return {
      device_id: null,
      ref: this.current?.ref ?? null,
      context: this.context,
      is_playing: this.playing,
      position_ms: Math.round(this.positionMs),
      // в базе очередь — в исходном порядке; порядок перемешивания живёт только в памяти
      queue: this.tracks.map((t) => t.ref),
      queue_index: this.order[this.pos] ?? null,
      shuffle: this.shuffle,
      repeat: this.repeat,
      client_ts: Date.now(),
    }
  }

  private saveState() {
    if (!this.current) return
    void api.savePlayerState(this.state()).catch(() => {})
  }

  private updateMedia() {
    const t = this.current
    void api
      .mediaUpdate(
        t
          ? {
              active: true,
              track_ref: t.ref,
              artist_avatar: t.artists?.[0]?.avatar_url ?? null,
              title: t.title,
              artist: t.artist,
              album: t.album?.title,
              cover_url: t.cover_url,
              duration_ms: Math.round(this.durationMs),
              playing: this.playing,
              position_ms: Math.round(this.positionMs),
            }
          : { active: false, playing: false },
      )
      .catch(() => {})
  }

  /** Настройки и последнее состояние: тот же трек и позиция, на паузе (`general.restore`). */
  private async restore() {
    try {
      const [volume, , saved, mode, output] = await Promise.all([
        api.getSetting<number>('player.volume'),
        tempo.load(),
        api.loadPlayerState(),
        api.getSetting<'none' | 'track' | 'queue'>('general.restore'),
        api.getSetting<string>('audio.output_device'),
      ])
      if (output) void this.setOutput(output)
      if (typeof volume === 'number') this.volume = volume
      this.applyVolume()
      this.applySpeed()
      if (!saved || !saved.tracks.length || this.current || mode === 'none') return
      const { state } = saved
      let tracks = saved.tracks
      // «При запуске: трек» — только сам трек, без очереди
      if (mode === 'track') tracks = tracks.filter((t) => t.ref === state.ref).slice(0, 1)
      if (!tracks.length) return
      const index = Math.max(0, tracks.findIndex((t) => t.ref === state.ref))
      this.tracks = tracks
      this.entryIds = this.freshIds(tracks.length)
      this.context = state.context
      this.repeat = state.repeat
      this.shuffle = state.shuffle
      this.order = makeOrder(tracks.length, index, state.shuffle)
      this.pos = state.shuffle ? 0 : index
      this.durationMs = tracks[index].duration_ms
      this.place(state.position_ms)
      this.updateMedia()
    } catch {
      // вне приложения (npm run dev) — просто пустой плеер
    }
  }
}

export const player = new Player()

export function formatTime(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = String(s % 60).padStart(2, '0')
  return h ? `${h}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`
}

// Vite HMR: модуль плеера подменили — старый экземпляр глушим, новый поднимет App.
if (import.meta.hot) {
  import.meta.hot.dispose(() => player.destroy())
}
