// Движок плеера на <audio> (SPEC §9.2): поток с локального аудио-сервера Rust, HLS SoundCloud —
// через hls.js. Очередь, повтор, перемешивание, громкость, режим скорости, медиа-клавиши,
// запись player_state и plays в локальную базу (формат API.md §5).
// Два элемента для бесшовности и кроссфейда, GainNode нормализации — позже (W5).
import Hls from 'hls.js'
import { untrack } from 'svelte'
import { api, errorText, onMediaControl, type PlayerState, type Repeat, type Track } from '../lib/api'
import { eq } from './eq.svelte'
import { countsAsPlay, enqueue, makeOrder, nextPos, nextRepeat, prevPos } from './queue'

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
  /** «Далее» — треки после текущего в порядке воспроизведения. */
  upNext = $derived(this.order.slice(this.pos + 1).map((i) => this.tracks[i]))

  private audio: HTMLAudioElement | null = null
  private hls: Hls | null = null
  private loadToken = 0
  private listenedMs = 0
  private startedAt = 0
  private lastTick = 0
  private heartbeat: ReturnType<typeof setInterval> | null = null
  private offMedia: (() => void) | null = null
  private ctx: AudioContext | null = null
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
    $effect.root(() => {
      $effect(() => {
        const ref = this.current?.ref ?? null
        // внутри eq читает и пишет своё состояние — не подписываемся на него
        untrack(() => void eq.onTrack(ref))
      })
    })
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

  // ——— очередь ———

  /** Играть список с трека `index`. `context` — откуда (search, favorites, playlist:<id>…). */
  async playList(tracks: Track[], index: number, context: string | null, title: string | null = null) {
    if (!tracks.length) return
    this.finishPlay()
    this.tracks = tracks
    this.context = context
    this.contextTitle = title
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

  /** «Следующим» (`next`) или «В очередь» (в конец). Пустая очередь — сразу играет. */
  async addToQueue(tracks: Track[], next: boolean) {
    if (!tracks.length) return
    if (!this.current) return this.playList(tracks, 0, 'queue')
    void api.cacheTracks(tracks).catch(() => {})
    let order = this.order
    const pos = this.pos
    const list = this.tracks.slice()
    for (const t of next ? [...tracks].reverse() : tracks) {
      list.push(t)
      order = enqueue(order, pos, list.length - 1, next)
    }
    this.tracks = list
    this.order = order
    this.saveState()
  }

  /** Перейти к треку из «Далее» (номер в upNext). */
  async jumpTo(upNextIndex: number) {
    this.finishPlay()
    this.pos = this.pos + 1 + upNextIndex
    await this.load(true)
  }

  async next(manual = true) {
    const p = nextPos(this.pos, this.order.length, this.repeat, manual)
    this.finishPlay()
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
    this.positionMs = t
    if (this.audio.src) this.audio.currentTime = t / 1000
    this.saveState()
    this.updateMedia()
  }

  setVolume(v: number) {
    this.volume = Math.max(0, Math.min(1, v))
    this.applyVolume()
    void api.setSetting('player.volume', this.volume).catch(() => {})
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
    this.positionMs = startMs
    this.durationMs = track.duration_ms
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
  private finishPlay() {
    const t = this.current
    if (!t || !this.startedAt) return
    const listened = Math.round(this.listenedMs)
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
      const [volume, speed, saved] = await Promise.all([
        api.getSetting<number>('player.volume'),
        api.getSetting<SpeedMode>('player.speed_mode'),
        api.loadPlayerState(),
      ])
      if (typeof volume === 'number') this.volume = volume
      if (speed && speed in speedModes) this.speedMode = speed
      this.applyVolume()
      this.applySpeed()
      if (!saved || !saved.tracks.length || this.current) return
      const { state, tracks } = saved
      const index = Math.max(0, tracks.findIndex((t) => t.ref === state.ref))
      this.tracks = tracks
      this.context = state.context
      this.repeat = state.repeat
      this.shuffle = state.shuffle
      this.order = makeOrder(tracks.length, index, state.shuffle)
      this.pos = state.shuffle ? 0 : index
      this.positionMs = state.position_ms
      this.durationMs = tracks[index].duration_ms
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
