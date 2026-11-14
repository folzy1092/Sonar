// Текст текущего трека: загрузка (Rust: кэш → lrclib → Genius), память на ~100 треков,
// предзагрузка следующего в очереди, сдвиг на трек, настройки вида (LYRICS.md §5–7).
import { untrack } from 'svelte'
import { api, type Track } from '../lib/api'
import { player } from '../player/player.svelte'
import { clampOffset, fromMs, toMs } from './core/offset'
import type { Lyrics } from './core/types'

export const lyricsSizes = ['S', 'M', 'L', 'XL'] as const
export type LyricsSize = (typeof lyricsSizes)[number]
export const sizeRem: Record<LyricsSize, number> = { S: 1.25, M: 1.6, L: 2, XL: 2.5 }

export const lyricsStyles = {
  normal: 'Обычный',
  scale: 'Масштаб',
  blur: 'Размытие',
  cinema: 'Кино',
  shift: 'Сдвиг',
} as const
export type LyricsStyle = keyof typeof lyricsStyles

/** В MVP — три анимации (LYRICS.md §6), остальные из Dotify — потом. */
export const lyricsAnimations = {
  normal: 'Обычная',
  fade: 'Фейд',
  blur: 'Размытие',
} as const
export type LyricsAnimation = keyof typeof lyricsAnimations

export type LyricsMode = 'words' | 'lines'

const MEMORY_MAX = 100

class LyricsStore {
  /** Для какого трека `data` и `status`. */
  ref = $state<string | null>(null)
  data = $state<Lyrics | null>(null)
  status = $state<'idle' | 'loading' | 'ready' | 'none'>('idle')
  /** Сдвиг текущего трека, секунды. */
  offset = $state(0)

  mode = $state<LyricsMode>('words')
  size = $state<LyricsSize>('L')
  style = $state<LyricsStyle>('blur')
  animation = $state<LyricsAnimation>('normal')

  /** Полноэкранный плеер открыт; `visible` — кнопка «T» (показать/скрыть текст). */
  fullscreen = $state(false)
  visible = $state(true)

  /** Есть ли у текста пословный тайминг — без него «По словам» неактивно. */
  hasWords = $derived(!!this.data?.lines.some((l) => l.words?.length))
  /** Есть что показать справа в полноэкранном плеере. */
  shown = $derived(this.visible && this.status === 'ready' && !!this.data?.lines.length)

  private memory = new Map<string, Lyrics | null>()
  private inflight = new Map<string, Promise<Lyrics | null>>()
  private started = false

  /** Один раз из App: следит за текущим треком и грузит его текст. */
  init() {
    if (this.started) return
    this.started = true
    void this.loadSettings()
    $effect.root(() => {
      $effect(() => {
        const t = player.current
        untrack(() => void this.loadFor(t))
      })
      $effect(() => {
        // предзагрузка следующего: текст готов к моменту переключения
        const next = player.upNext[0]
        if (next && player.current) untrack(() => void this.fetch(next).catch(() => {}))
      })
    })
  }

  private async loadSettings() {
    try {
      const [mode, size, style, animation, visible] = await Promise.all([
        api.getSetting<LyricsMode>('lyrics.mode'),
        api.getSetting<LyricsSize>('lyrics.size'),
        api.getSetting<LyricsStyle>('lyrics.style'),
        api.getSetting<LyricsAnimation>('lyrics.animation'),
        api.getSetting<boolean>('lyrics.visible'),
      ])
      if (mode === 'words' || mode === 'lines') this.mode = mode
      if (size && lyricsSizes.includes(size)) this.size = size
      if (style && style in lyricsStyles) this.style = style
      if (animation && animation in lyricsAnimations) this.animation = animation
      if (typeof visible === 'boolean') this.visible = visible
    } catch {
      // вне приложения — значения по умолчанию
    }
  }

  private fetch(t: Track, refresh = false): Promise<Lyrics | null> {
    if (!refresh && this.memory.has(t.ref)) return Promise.resolve(this.memory.get(t.ref) ?? null)
    const running = this.inflight.get(t.ref)
    if (running && !refresh) return running
    const p = api
      .lyrics(t, refresh)
      .then((l) => {
        this.remember(t.ref, l)
        return l
      })
      .finally(() => this.inflight.delete(t.ref))
    this.inflight.set(t.ref, p)
    return p
  }

  private remember(ref: string, l: Lyrics | null) {
    this.memory.delete(ref)
    this.memory.set(ref, l)
    if (this.memory.size > MEMORY_MAX) this.memory.delete(this.memory.keys().next().value!)
  }

  private async loadFor(t: Track | null, refresh = false) {
    if (!t) {
      this.ref = null
      this.data = null
      this.status = 'idle'
      return
    }
    if (t.ref === this.ref && !refresh && this.status !== 'idle') return
    const ref = t.ref
    this.ref = ref
    this.data = null
    this.offset = 0
    this.status = 'loading'
    void api
      .lyricsOffset(ref)
      .then((ms) => {
        if (this.ref === ref) this.offset = fromMs(ms)
      })
      .catch(() => {})
    try {
      const l = await this.fetch(t, refresh)
      if (this.ref !== ref) return
      this.data = l
      this.status = l?.lines.length ? 'ready' : 'none'
    } catch {
      // сеть не ответила — тихо «Текст не найден», без тостов (LYRICS.md §7)
      if (this.ref === ref) this.status = 'none'
    }
  }

  /** Искать текст заново, мимо кэша. */
  reload() {
    void this.loadFor(player.current, true)
  }

  setOffset(sec: number) {
    const ref = this.ref
    if (!ref) return
    this.offset = clampOffset(sec)
    void api.setLyricsOffset(ref, toMs(this.offset)).catch(() => {})
  }

  setMode(m: LyricsMode) {
    this.mode = m
    void api.setSetting('lyrics.mode', m).catch(() => {})
  }

  cycleSize() {
    this.size = lyricsSizes[(lyricsSizes.indexOf(this.size) + 1) % lyricsSizes.length]
    void api.setSetting('lyrics.size', this.size).catch(() => {})
  }

  setStyle(s: LyricsStyle) {
    this.style = s
    void api.setSetting('lyrics.style', s).catch(() => {})
  }

  setAnimation(a: LyricsAnimation) {
    this.animation = a
    void api.setSetting('lyrics.animation', a).catch(() => {})
  }

  toggleVisible() {
    this.visible = !this.visible
    void api.setSetting('lyrics.visible', this.visible).catch(() => {})
  }

  open() {
    if (player.current) this.fullscreen = true
  }

  close() {
    this.fullscreen = false
  }
}

export const lyrics = new LyricsStore()
