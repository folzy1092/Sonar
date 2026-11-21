// Текст текущего трека: загрузка (Rust: кэш → lrclib → Genius), память на ~100 треков,
// предзагрузка следующего в очереди, сдвиг на трек, настройки вида (LYRICS.md §5–7).
import { mapAnnotations, type Annotation } from './core/annotations'
import { untrack } from 'svelte'
import { api, type Track } from '../lib/api'
import { player } from '../player/player.svelte'
import { lang, t } from '../lib/i18n.svelte'
import { toast } from '../lib/toast.svelte'
import { clampOffset, fromMs, toMs } from './core/offset'
import type { Lyrics } from './core/types'

export const lyricsSizes = ['S', 'M', 'L', 'XL'] as const
export type LyricsSize = (typeof lyricsSizes)[number]
export const sizeRem: Record<LyricsSize, number> = { S: 1.25, M: 1.6, L: 2, XL: 2.5 }

export const lyricsStyles = {
  normal: 'Без эффектов',
  scale: 'Текущая крупнее',
  blur: 'Размытие вокруг',
  cinema: 'Разреженные буквы',
  shift: 'Текущая со сдвигом',
} as const
export type LyricsStyle = keyof typeof lyricsStyles

/** Все анимации Dotify (LYRICS.md §6): смена строки и проявление слов в караоке. */
export const lyricsAnimations = {
  normal: 'Простая',
  fade: 'Затухание',
  blur: 'Размытие',
  flip3d: 'Поворот в 3D',
  bounce: 'С отскоком',
  wave: 'Волна',
  float: 'Всплытие',
  drift: 'Наклон',
  zoom: 'Приближение',
  /** Строки подтягиваются вверх лесенкой — каждая следующая чуть позже («магнит», как в Liner). */
  ladder: 'Лесенка',
} as const
export type LyricsAnimation = keyof typeof lyricsAnimations

export type LyricsMode = 'words' | 'lines'
export type LyricsViewMode = 'both' | 'cover' | 'lyrics'

const MEMORY_MAX = 100

class LyricsStore {
  /** Для какого трека `data` и `status`. */
  ref = $state<string | null>(null)
  data = $state<Lyrics | null>(null)
  /** Аннотации Genius: номер строки → пояснение (core/annotations.ts). */
  notes = $state<Map<number, Annotation>>(new Map())
  private notesCache = new Map<string, Annotation[]>()
  status = $state<'idle' | 'loading' | 'ready' | 'none'>('idle')
  /** Сдвиг текущего трека, секунды. */
  offset = $state(0)

  /** Перевод включён (меню текста → «Перевести»): держится и для следующих треков. */
  translateOn = $state(false)
  /** Перевод строк текущего текста (та же длина, что `data.lines`), `null` — ещё нет. */
  translation = $state<string[] | null>(null)
  translating = $state(false)
  private trCache = new Map<string, string[]>()

  mode = $state<LyricsMode>('words')
  size = $state<LyricsSize>('L')
  style = $state<LyricsStyle>('blur')
  animation = $state<LyricsAnimation>('normal')

  /** Полноэкранный плеер открыт. `view` — «глаза» в меню: обложка и текст / только обложка /
   *  только текст (`lyrics.view`). */
  fullscreen = $state(false)
  /** Текущая строка синхронного текста (−1 — вступление): по ней сдвигается фокус фона. */
  line = $state(-1)
  view = $state<LyricsViewMode>('both')

  /** Есть ли у текста пословный тайминг — без него «По словам» неактивно. */
  hasWords = $derived(!!this.data?.lines.some((l) => l.words?.length))
  /** Есть что показать справа в полноэкранном плеере. */
  shown = $derived(this.view !== 'cover' && this.status === 'ready' && !!this.data?.lines.length)
  /** Колонка с обложкой: нет её только в режиме «только текст», когда текст есть. */
  coverShown = $derived(this.view !== 'lyrics' || !this.shown)

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
        api.getSetting<LyricsViewMode>('lyrics.view'),
      ])
      if (mode === 'words' || mode === 'lines') this.mode = mode
      if (size && lyricsSizes.includes(size)) this.size = size
      if (style && style in lyricsStyles) this.style = style
      if (animation && animation in lyricsAnimations) this.animation = animation
      if (visible === 'both' || visible === 'cover' || visible === 'lyrics') this.view = visible
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
    this.notes = new Map()
    this.translation = null
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
      if (l?.lines.length) void this.loadNotes(t, l)
      if (l?.lines.length && this.translateOn) void this.translate(true)
    } catch {
      // сеть не ответила — тихо «Текст не найден», без тостов (LYRICS.md §7)
      if (this.ref === ref) this.status = 'none'
    }
  }

  /** Аннотации Genius к строкам — в фоне, после текста; нет на Genius — без кавычек. */
  private async loadNotes(t: Track, l: Lyrics) {
    let anns = this.notesCache.get(t.ref)
    if (!anns) {
      try {
        anns = await api.lyricsAnnotations(t)
      } catch {
        return
      }
      this.notesCache.set(t.ref, anns)
      if (this.notesCache.size > 30) this.notesCache.delete(this.notesCache.keys().next().value!)
    }
    if (this.ref !== t.ref) return
    this.notes = mapAnnotations(
      l.lines.map((x) => x.text),
      anns,
    )
  }

  /** Включить / выключить перевод текста на язык интерфейса. */
  toggleTranslate() {
    this.translateOn = !this.translateOn
    if (this.translateOn) void this.translate(false)
  }

  /** `quiet` — для следующего трека: без тоста «уже на этом языке». */
  private async translate(quiet: boolean) {
    const ref = this.ref
    const lines = this.data?.lines
    if (!ref || !lines?.length) return
    const to = lang()
    const key = `${ref}:${to}`
    const hit = this.trCache.get(key)
    if (hit) {
      this.translation = hit
      return
    }
    this.translating = true
    try {
      const r = await api.lyricsTranslate(
        lines.map((x) => x.text),
        to,
      )
      if (this.ref !== ref) return
      // текст уже на языке интерфейса — переводить нечего
      if (r.source === to) {
        this.translation = null
        if (!quiet) toast.show(t('Текст уже на этом языке'))
        return
      }
      this.trCache.set(key, r.lines)
      if (this.trCache.size > 30) this.trCache.delete(this.trCache.keys().next().value!)
      this.translation = r.lines
    } catch {
      if (this.ref === ref && !quiet) toast.show(t('Перевод не удался — попробуй позже'))
    } finally {
      if (this.ref === ref) this.translating = false
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

  setView(v: LyricsViewMode) {
    this.view = v
    void api.setSetting('lyrics.view', v).catch(() => {})
  }

  cycleStyle() {
    const keys = Object.keys(lyricsStyles) as LyricsStyle[]
    this.setStyle(keys[(keys.indexOf(this.style) + 1) % keys.length])
  }

  cycleAnimation() {
    const keys = Object.keys(lyricsAnimations) as LyricsAnimation[]
    this.setAnimation(keys[(keys.indexOf(this.animation) + 1) % keys.length])
  }

  setSize(s: LyricsSize) {
    this.size = s
    void api.setSetting('lyrics.size', s).catch(() => {})
  }

  open() {
    if (player.current) this.fullscreen = true
  }

  close() {
    this.fullscreen = false
  }
}

export const lyrics = new LyricsStore()
