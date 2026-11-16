// Движок плеера на <audio> (SPEC §9.2): поток с локального аудио-сервера Rust, HLS SoundCloud —
// через hls.js. Очередь, повтор, перемешивание, громкость, режим скорости, медиа-клавиши,
// запись player_state и plays в локальную базу (формат API.md §5).
// Два элемента для бесшовности и кроссфейда, GainNode нормализации — позже (W5).
import Hls from 'hls.js'
import { api, errorText, onMediaControl, type PlayerState, type Repeat, type Track } from '../lib/api'
import { eq } from './eq.svelte'
import { Clock } from '../lyrics/core/clock'
import { countsAsPlay, dropUpcoming, enqueue, enqueueAt, makeOrder, nextPos, nextRepeat, prevPos } from './queue'

/** Режимы скорости кнопки рядом с громкостью: тон меняется вместе со скоростью (slowed / sped up). */
export const speedModes = {
  normal: { label: 'Обычная', badge: '', rate: 1 },
  slowed: { label: 'Slowed', badge: 'Slowed', rate: 0.8 },
  speed: { label: 'Sped up', badge: 'Speed', rate: 1.25 },
} as const
export type SpeedMode = keyof typeof speedModes

const HEARTBEAT_MS = 30_000

class Player {
  tracks = $state<Track[]>([])
  /** Порядок воспроизведения: индексы в `tracks` (перемешанный, если shuffle). */
  order = $state<number[]>([])
  pos = $state(0)
  context = $state<string | null>(null)
  /** Название контекста для очереди («Любимые», имя плейлиста, альбома, исполнителя). */
  contextTitle = $state<string | null>(null)

  playing = $state(false)
  loading = $state(false)
  error = $state<string | null>(null)
  positionMs = $state(0)
  durationMs = $state(0)
  /** Реальный формат потока для плашки: «AAC 160», «MP3 320», «FLAC». */
  quality = $state<string | null>(null)

  volume = $state(0.8)
  repeat = $state<Repeat>('off')
  shuffle = $state(false)
  speedMode = $state<SpeedMode>('normal')

  current = $derived<Track | null>(this.tracks[this.order[this.pos]] ?? null)
  /** Треки, которые дописал автоплей похожих (`autoplay.svelte.ts`), — в «Далее» они идут
   *  отдельным блоком под тумблером, свои «В очередь» встают перед ними. Новая очередь — пусто. */
  autoRefs = $state(new Set<string>())

  /** «Далее» — треки после текущего в порядке воспроизведения. */
  upNext = $derived(this.order.slice(this.pos + 1).map((i) => this.tracks[i]))

  private audio: HTMLAudioElement | null = null
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
    const a = new Audio()
    a.preload = 'auto'
    // поток идёт с 127.0.0.1 с CORS — без этого Web Audio получит тишину
    a.crossOrigin = 'anonymous'
    this.audio = a
    this.connectAnalyser(a)
    this.applyVolume()
    this.applySpeed()

    a.addEventListener('play', () => this.setPlaying(true))
    a.addEventListener('pause', () => this.setPlaying(false))
    a.addEventListener('waiting', () => (this.loading = true))
    a.addEventListener('playing', () => (this.loading = false))
    a.addEventListener('canplay', () => (this.loading = false))
    a.addEventListener('durationchange', () => {
      if (Number.isFinite(a.duration) && a.duration > 0) this.durationMs = a.duration * 1000
    })
    a.addEventListener('timeupdate', () => this.onTime())
    // до метаданных currentTime = 0 ничего не значит (смена src) — держим позицию из place()
    const tick = (fn: () => void) => () => {
      if (a.readyState === HTMLMediaElement.HAVE_NOTHING) return
      fn()
      this.syncFrames()
    }
    const now = () => performance.now()
    a.addEventListener('timeupdate', tick(() => this.clock.sample(a.currentTime, now())))
    a.addEventListener('playing', tick(() => this.clock.play(a.currentTime, now(), a.playbackRate)))
    a.addEventListener('pause', tick(() => this.clock.hold(a.currentTime)))
    a.addEventListener('waiting', tick(() => this.clock.hold(a.currentTime)))
    a.addEventListener('seeking', tick(() => this.clock.seek(a.currentTime)))
    a.addEventListener(
      'seeked',
      tick(() => (a.paused ? this.clock.hold(a.currentTime) : this.clock.play(a.currentTime, now(), a.playbackRate))),
    )
    a.addEventListener('ratechange', tick(() => this.clock.setRate(a.playbackRate, a.currentTime, now())))
    a.addEventListener('ended', () => this.onEnded())
    a.addEventListener('error', () => this.onError(a.error?.message || 'не удалось воспроизвести'))

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
  }

  /** Полная остановка: при подмене модуля в dev (HMR), иначе старый <audio> играет «вторым потоком». */
  destroy() {
    this.hls?.destroy()
    this.hls = null
    if (this.audio) {
      this.audio.pause()
      this.audio.removeAttribute('src')
      this.audio.load()
    }
    this.audio = null
    if (this.heartbeat) clearInterval(this.heartbeat)
    cancelAnimationFrame(this.raf)
    this.raf = 0
    this.offMedia?.()
    void this.ctx?.close()
  }

  private connectAnalyser(a: HTMLAudioElement) {
    try {
      const ctx = new AudioContext()
      const analyser = ctx.createAnalyser()
      analyser.fftSize = 2048
      analyser.smoothingTimeConstant = 0.82
      // источник → эквалайзер → анализатор волны → выход
      eq.connect(ctx, ctx.createMediaElementSource(a), analyser)
      analyser.connect(ctx.destination)
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
  async playList(tracks: Track[], index: number, context: string | null, title: string | null = null) {
    if (!tracks.length) return
    this.finishPlay()
    this.tracks = tracks
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
  async addToQueue(tracks: Track[], next: boolean, auto = false) {
    if (!tracks.length) return
    if (!this.current) return this.playList(tracks, 0, 'queue')
    void api.cacheTracks(tracks).catch(() => {})
    let order = this.order
    const pos = this.pos
    const list = this.tracks.slice()
    // первое ещё не игравшее похожее автоплея — свои треки встают перед ним
    const firstAuto = next || auto ? -1 : order.findIndex((i, k) => k > pos && this.autoRefs.has(list[i]?.ref))
    let at = firstAuto
    for (const t of next ? [...tracks].reverse() : tracks) {
      list.push(t)
      if (at >= 0) order = enqueueAt(order, at++, list.length - 1)
      else order = enqueue(order, pos, list.length - 1, next)
    }
    if (auto) this.autoRefs = new Set([...this.autoRefs, ...tracks.map((t) => t.ref)])
    this.tracks = list
    this.order = order
    this.saveState()
  }

  /** Убрать из «Далее» похожие автоплея (тумблер выключили). Текущий и сыгранные остаются. */
  dropAuto() {
    const auto = this.autoRefs
    if (!auto.size) return
    const out = dropUpcoming(this.tracks, this.order, this.pos, (t) => auto.has(t.ref))
    this.tracks = out.tracks
    this.order = out.order
    this.autoRefs = new Set()
    this.saveState()
  }

  /** Убрать из «Далее» ещё не игравшие треки, подходящие под `drop`, кроме `keep` ближайших
   *  (волна после серии пропусков: очередь подбиралась под вкус, которого сейчас нет). Вернёт убранные. */
  dropUpNext(keep: number, drop: (t: Track) => boolean): Track[] {
    const out = dropUpcoming(this.tracks, this.order, this.pos, drop, keep)
    if (!out.dropped.length) return []
    this.tracks = out.tracks
    this.order = out.order
    this.saveState()
    return out.dropped
  }

  /** Перейти к треку из «Далее» (номер в upNext). */
  async jumpTo(upNextIndex: number) {
    this.finishPlay(true)
    this.pos = this.pos + 1 + upNextIndex
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

  setSpeedMode(mode: SpeedMode) {
    this.speedMode = mode
    this.applySpeed()
    void api.setSetting('player.speed_mode', mode).catch(() => {})
  }

  // ——— внутреннее ———

  private applyVolume() {
    // квадрат — громкость на слух ровнее, чем линейная
    if (this.audio) this.audio.volume = this.volume * this.volume
  }

  private applySpeed() {
    if (!this.audio) return
    const rate = speedModes[this.speedMode].rate
    this.audio.preservesPitch = false // slowed / sped up: тон вместе со скоростью
    this.audio.defaultPlaybackRate = rate
    this.audio.playbackRate = rate
  }

  private async load(autoplay: boolean, startMs = 0) {
    const a = this.audio
    const track = this.current
    if (!a || !track) return
    const token = ++this.loadToken
    this.error = null
    this.loading = true
    this.durationMs = track.duration_ms
    this.place(startMs)
    this.hls?.destroy()
    this.hls = null
    this.quality = null
    a.removeAttribute('src')
    this.updateMedia()

    try {
      const s = await api.streamUrl(track.ref)
      if (token !== this.loadToken) return
      this.quality = s.quality
      if (s.kind === 'hls' && Hls.isSupported()) {
        const hls = new Hls({ startPosition: startMs / 1000 })
        hls.on(Hls.Events.ERROR, (_e, data) => {
          if (data.fatal && token === this.loadToken) this.onError(`HLS: ${data.details}`)
        })
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
      else this.loading = false
      this.saveState()
    } catch (e) {
      if (token === this.loadToken) this.onError(errorText(e))
    }
  }

  private onTime() {
    const a = this.audio!
    const ms = a.currentTime * 1000
    // считаем реально прослушанное: только маленькие шаги вперёд, без перемоток
    const delta = ms - this.lastTick
    if (this.playing && delta > 0 && delta < 2000) this.listenedMs += delta
    this.lastTick = ms
    this.positionMs = ms
  }

  private onEnded() {
    void this.next(false)
  }

  private onError(message: string) {
    this.loading = false
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
      const [volume, speed, saved, mode, output] = await Promise.all([
        api.getSetting<number>('player.volume'),
        api.getSetting<SpeedMode>('player.speed_mode'),
        api.loadPlayerState(),
        api.getSetting<'none' | 'track' | 'queue'>('general.restore'),
        api.getSetting<string>('audio.output_device'),
      ])
      if (output) void this.setOutput(output)
      if (typeof volume === 'number') this.volume = volume
      if (speed && speed in speedModes) this.speedMode = speed
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
