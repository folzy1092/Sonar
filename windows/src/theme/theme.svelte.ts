// Тема под обложку (SPEC §4.4, `appearance.cover_theme`): цвет текущей обложки → акцент, фон и
// текст на акценте. Обложка идёт через локальный `/cover` (CORS и кэш на диске), цвета меняются
// плавно (CSS @property в tokens.css). Выключено — готовая тема (`appearance.preset`), обложка
// серая — монохромная.
import { api } from '../lib/api'
import { isTauri } from '../lib/tauri'
import { player } from '../player/player.svelte'
import { DECOR_VARS, pickAccent, themeFrom, type RGB, type Surface } from './palette'
import { settings } from '../lib/settings.svelte'
import { setAnimations } from '../lib/motion'
import { CUSTOM_PREFIX, fontStack, RADII, WIDE_FONTS } from './look'
import { DISPLAY_TUNING, WDTH_FONTS } from './style'
import { loadCustomFont } from './custom-font'

let port: number | null = null

const SURFACE_IDS = { echo: 1, signal: 1, edge: 1, tactile: 1, monolith: 1 }

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
        const surface = settings.get('appearance.surface')
        const url = on ? (player.current?.cover_url ?? null) : null
        void this.apply(on, url, preset, surface)
      })
      $effect(() => {
        setAnimations(settings.get('appearance.animations'))
      })
      // шрифты (Интерфейс → Стиль): интерфейса — `appearance.font`, заголовков («Моя волна»,
      // названия страниц и разделов) — `appearance.font_display` со своей шириной, жирностью и
      // трекингом (style.ts DISPLAY_TUNING). Заголовков нет — те же, что у интерфейса.
      $effect(() => {
        const name = settings.get('appearance.font')
        const display = settings.get('appearance.font_display')
        if (name.startsWith(CUSTOM_PREFIX) || display.startsWith(CUSTOM_PREFIX)) void loadCustomFont()
        const root = document.documentElement
        const st = root.style
        const f = fontStack(name)
        const d = fontStack(display) ?? f
        root.classList.toggle('custom-font', !!f)
        root.classList.toggle('display-font', !!d)
        root.classList.toggle('display-wide', WIDE_FONTS.has(display))
        // у шрифта заголовков есть ось ширины — заголовок «дышит» при смене трека (стиль «Эхо»)
        root.classList.toggle('display-wdth', WDTH_FONTS.has(display))
        const set = (k: string, v: string | null | undefined) => (v ? st.setProperty(k, v) : st.removeProperty(k))
        set('--font', f)
        set('--font-display', d)
        set('--font-wave', d)
        const tune = DISPLAY_TUNING[display] ?? {}
        set('--display-wdth', tune.wdth ? String(tune.wdth) : null)
        set('--display-weight', tune.weight ? String(tune.weight) : null)
        set('--display-tracking', tune.tracking)
      })
      // толщина линий иконок и как отмечен выбранный раздел левой панели (Интерфейс → Стиль)
      $effect(() => {
        const root = document.documentElement
        root.style.setProperty('--icon-stroke', String(settings.get('appearance.icon_stroke') || 2))
        root.dataset.nav = settings.get('appearance.anim_nav')
      })
      // оформление заголовков: как есть или «журнальное» (капсом, крупно, номера разделов)
      $effect(() => {
        document.documentElement.classList.toggle('title-editorial', settings.get('appearance.title_style') === 'editorial')
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
      // скругление капсул и обложки мини-плеера (Плеер → Мини плеер → Форма / Обложка)
      $effect(() => {
        const st = document.documentElement.style
        st.setProperty('--cap-k', String(Math.max(0, Math.min(100, settings.get('mini.shape_round'))) / 100))
        st.setProperty('--cover-k', String(Math.max(0, Math.min(100, settings.get('mini.cover_round'))) / 100))
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

  private async apply(cover: boolean, url: string | null, preset: string, surface: Surface) {
    const my = ++this.seq
    const p = PRESETS.find((x) => x.id === preset) ?? PRESETS[0]
    const c = cover ? (url ? await colorOf(url) : null) : p.accent
    if (my !== this.seq) return
    if (cover) this.accent = c
    const root = document.documentElement
    root.classList.toggle('amoled', !cover && !!p.black)
    const st = root.style
    const SHADE = ['--bg', '--surface-0', '--surface-1', '--surface-2', '--surface-3']
    // все цвета — по формулам OKLCH выбранной поверхности (palette.ts): обложка или готовая тема
    // дают оттенок, серая — монохром
    const t = themeFrom(c, surface in SURFACE_IDS ? surface : 'monolith')
    root.dataset.surface = surface
    for (const k of DECOR_VARS) if (!(k in t.vars)) st.removeProperty(k)
    // AMOLED — свой чистый чёрный фон и поверхности (tokens.css), их не трогаем
    const black = root.classList.contains('amoled')
    for (const [k, v] of Object.entries(t.vars)) {
      if (black && SHADE.includes(k)) st.removeProperty(k)
      else st.setProperty(k, v)
    }
  }
}

export const theme = new Theme()
