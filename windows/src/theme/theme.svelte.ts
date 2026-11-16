// Тема под обложку (SPEC §4.4, `appearance.cover_theme`): цвет текущей обложки → акцент, фон и
// текст на акценте. Обложка идёт через локальный `/cover` (CORS и кэш на диске), цвета меняются
// плавно (CSS @property в tokens.css). Выключено — готовая тема (`appearance.preset`), обложка
// серая — монохромная.
import { api } from '../lib/api'
import { isTauri } from '../lib/tauri'
import { player } from '../player/player.svelte'
import { css, pickAccent, themeFrom, type RGB } from './palette'
import { settings } from '../lib/settings.svelte'
import { setAnimations } from '../lib/motion'
import { CUSTOM_PREFIX, fontStack, RADII } from './look'
import { loadCustomFont } from './custom-font'

let port: number | null = null

/** Адрес обложки через локальный сервер (для canvas нужен CORS). */
export async function proxied(url: string): Promise<string> {
  if (!isTauri) return url
  port ??= await api.streamPort()
  return `http://127.0.0.1:${port}/cover?u=${encodeURIComponent(url)}`
}

const cache = new Map<string, RGB | null>()

/** Акцентный цвет картинки (кэш в памяти). */
export async function colorOf(url: string): Promise<RGB | null> {
  if (cache.has(url)) return cache.get(url)!
  const src = await proxied(url)
  const color = await new Promise<RGB | null>((resolve) => {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.onload = () => {
      try {
        const c = document.createElement('canvas')
        c.width = c.height = 64
        const g = c.getContext('2d', { willReadFrequently: true })!
        g.drawImage(img, 0, 0, 64, 64)
        resolve(pickAccent(g.getImageData(0, 0, 64, 64).data))
      } catch {
        resolve(null)
      }
    }
    img.onerror = () => resolve(null)
    img.src = src
  })
  if (cache.size > 300) cache.clear()
  cache.set(url, color)
  return color
}

/** Готовые темы (`appearance.preset`, pc/Screenshot_1): акцент; фон — его оттенок. */
export const PRESETS: { id: string; title: string; accent: RGB | null; black?: boolean }[] = [
  { id: 'neutral', title: 'Neutral', accent: null },
  { id: 'amoled', title: 'AMOLED', accent: null, black: true },
  { id: 'crimson', title: 'Crimson', accent: [229, 72, 77] },
  { id: 'nord', title: 'Nord', accent: [136, 192, 208] },
  { id: 'sky', title: 'Sky', accent: [76, 154, 255] },
  { id: 'mint', title: 'Mint', accent: [62, 207, 142] },
  { id: 'violet', title: 'Violet', accent: [169, 112, 255] },
  { id: 'blossom', title: 'Blossom', accent: [240, 84, 122] },
  { id: 'sakura', title: 'Sakura', accent: [244, 166, 196] },
  { id: 'terminal', title: 'Terminal', accent: [34, 229, 90] },
  { id: 'aqua', title: 'Aqua', accent: [46, 196, 182] },
  { id: 'sunset', title: 'Sunset', accent: [255, 138, 61] },
  { id: 'slate', title: 'Slate', accent: [107, 140, 255] },
]

class Theme {
  /** Цвет текущей обложки (для образца «Под трек» в настройках). */
  accent = $state<RGB | null>(null)
  private started = false
  private seq = 0

  get enabled() {
    return settings.get('appearance.cover_theme')
  }

  init() {
    if (this.started) return
    this.started = true
    void settings.load()
    $effect.root(() => {
      $effect(() => {
        const on = settings.get('appearance.cover_theme')
        const preset = settings.get('appearance.preset')
        const url = on ? (player.current?.cover_url ?? null) : null
        void this.apply(on, url, preset)
      })
      $effect(() => {
        setAnimations(settings.get('appearance.animations'))
      })
      // шрифт и скругления (Интерфейс → Вид)
      // шрифт меняет весь интерфейс, включая заголовок «Моя волна» (у Dotify он оставался прежним)
      $effect(() => {
        const name = settings.get('appearance.font')
        if (name.startsWith(CUSTOM_PREFIX)) void loadCustomFont()
        const root = document.documentElement
        const st = root.style
        const f = fontStack(name)
        root.classList.toggle('custom-font', !!f)
        for (const k of ['--font', '--font-display', '--font-wave']) {
          if (f) st.setProperty(k, f)
          else st.removeProperty(k)
        }
      })
      // размер и жирность текста (Интерфейс → Вид)
      $effect(() => {
        const st = document.documentElement.style
        const size = settings.get('appearance.font_size')
        const weight = settings.get('appearance.font_weight')
        if (size && size !== 16) st.setProperty('--fs', String(size / 16))
        else st.removeProperty('--fs')
        if (weight && weight !== 'auto') st.setProperty('--fw', weight)
        else st.removeProperty('--fw')
      })
      $effect(() => {
        const r = RADII[settings.get('appearance.corner_radius')] ?? RADII.rounded
        const st = document.documentElement.style
        ;(['--radius-s', '--radius-m', '--radius-l', '--radius-xl'] as const).forEach((k, i) => st.setProperty(k, `${r[i]}px`))
      })
    })
  }

  setEnabled(on: boolean) {
    settings.set('appearance.cover_theme', on)
  }

  /** Готовая тема выключает «Под трек». */
  setPreset(id: string) {
    settings.set('appearance.preset', id)
    settings.set('appearance.cover_theme', false)
  }

  private async apply(cover: boolean, url: string | null, preset: string) {
    const my = ++this.seq
    const p = PRESETS.find((x) => x.id === preset) ?? PRESETS[0]
    const c = cover ? (url ? await colorOf(url) : null) : p.accent
    if (my !== this.seq) return
    if (cover) this.accent = c
    const root = document.documentElement
    root.classList.toggle('amoled', !cover && !!p.black)
    const st = root.style
    if (!c) {
      for (const k of ['--accent', '--accent-ink', '--accent-soft', '--tint']) st.removeProperty(k)
      return
    }
    const t = themeFrom(c)
    st.setProperty('--accent', css(t.accent))
    st.setProperty('--accent-ink', css(t.ink))
    st.setProperty('--accent-soft', css(t.accent, 0.14))
    st.setProperty('--tint', css(t.bg))
  }
}

export const theme = new Theme()
