// Тема под обложку (SPEC §4.4, `appearance.cover_theme`): цвет текущей обложки → акцент, фон и
// текст на акценте. Обложка идёт через локальный `/cover` (CORS и кэш на диске), цвета меняются
// плавно (CSS @property в tokens.css). Выключено — готовая тема (`appearance.preset`), обложка
// серая — монохромная.
import { api } from '../lib/api'
import { isTauri } from '../lib/tauri'
import { player } from '../player/player.svelte'
import { DECOR_VARS, oklch, pickAccent, themeFrom, type RGB, type Surface } from './palette'
import { settings } from '../lib/settings.svelte'
import { setAnimations } from '../lib/motion'
import { CUSTOM_PREFIX, fontStack, RADII, WIDE_FONTS } from './look'
import { AXES, axisKey, CUSTOM_STYLE_PREFIX, DISPLAY_TUNING, matchStyle, newCustom, styleAxes, WDTH_FONTS, type StyleAxes } from './style'
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
    if (typeof matchMedia === 'function') {
      const mq = matchMedia('(prefers-color-scheme: light)')
      mq.addEventListener('change', (e) => (this.systemLight = e.matches))
    }
    void settings.load()
    $effect.root(() => {
      $effect(() => {
        const on = settings.get('appearance.cover_theme')
        const preset = settings.get('appearance.preset')
        const surface = settings.get('appearance.surface')
        const light = this.light
        const glass = settings.get('appearance.glass') ? Math.max(0.15, Math.min(1, settings.get('appearance.opacity') / 100)) : 1
        const url = on ? (player.current?.cover_url ?? null) : null
        void this.apply(on, url, preset, surface, light, glass)
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
      // прозрачность окна: системный эффект под окном (Mica / Acrylic, glass.rs) и размытие у панелей
      $effect(() => {
        const on = settings.get('appearance.glass')
        const root = document.documentElement
        root.classList.toggle('glass', on)
        root.style.setProperty('--glass-blur', `${settings.get('appearance.glass_blur')}px`)
        // меню и подсказки размываются так же, как стекло
        if (on) root.style.setProperty('--menu-blur', `${Math.max(6, settings.get('appearance.glass_blur'))}px`)
        else root.style.removeProperty('--menu-blur')
        if (isTauri) void api.setGlass(on).catch(() => {})
      })
      // язык документа — для переносов, чтения с экрана и шрифтов
      $effect(() => {
        document.documentElement.lang = settings.get('general.language')
      })
      // кэш треков на диске (Система → Хранилище) — настройки уходят в Rust при запуске и при смене
      $effect(() => {
        const on = settings.get('storage.cache_tracks')
        const limit = settings.get('storage.cache_limit_mb')
        if (isTauri) void api.setTrackCache(on, limit).catch(() => {})
      })
      // выбранный стиль следит за осями: ручная правка любой оси (в «Стиле» или «Виде») — «Свой»,
      // оси совпали с готовым или сохранённым стилем — он
      $effect(() => {
        const axes = this.axes
        const cur = settings.get('appearance.style')
        const next = matchStyle(cur, axes, settings.get('appearance.custom_styles'))
        if (next !== cur) settings.set('appearance.style', next)
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

  /** Текущие оси стиля из настроек. */
  get axes(): StyleAxes {
    return Object.fromEntries(AXES.map((a) => [a, settings.get(axisKey(a))])) as unknown as StyleAxes
  }

  /** Выбрать готовый или свой стиль — ставит все оси. */
  applyStyle(id: string) {
    const axes = styleAxes(id, settings.get('appearance.custom_styles'))
    if (!axes) return
    for (const a of AXES) settings.set(axisKey(a), axes[a] as never)
    settings.set('appearance.style', id)
  }

  /** Сохранить текущие оси своим стилем; вернёт его id (`custom:<id>`). */
  saveStyle(name: string): string {
    const list = settings.get('appearance.custom_styles')
    const own = newCustom(name, this.axes, list)
    settings.set('appearance.custom_styles', [...list, own])
    settings.set('appearance.style', CUSTOM_STYLE_PREFIX + own.id)
    return CUSTOM_STYLE_PREFIX + own.id
  }

  renameStyle(id: string, name: string) {
    const clean = name.trim().slice(0, 40)
    if (!clean) return
    settings.set(
      'appearance.custom_styles',
      settings.get('appearance.custom_styles').map((c) => (CUSTOM_STYLE_PREFIX + c.id === id ? { ...c, name: clean } : c)),
    )
  }

  deleteStyle(id: string) {
    settings.set(
      'appearance.custom_styles',
      settings.get('appearance.custom_styles').filter((c) => CUSTOM_STYLE_PREFIX + c.id !== id),
    )
    if (settings.get('appearance.style') === id) settings.set('appearance.style', 'custom')
  }

  setEnabled(on: boolean) {
    settings.set('appearance.cover_theme', on)
  }

  /** Готовая тема выключает «Под трек». */
  setPreset(id: string) {
    settings.set('appearance.preset', id)
    settings.set('appearance.cover_theme', false)
  }

  /** Системная тема светлая (для «Как в системе»), следим на лету. */
  private systemLight = $state(typeof matchMedia === 'function' && matchMedia('(prefers-color-scheme: light)').matches)

  /** Светлая ли сейчас тема (Интерфейс → Вид → Тема). */
  get light() {
    const mode = settings.get('appearance.mode')
    return mode === 'light' || (mode === 'system' && this.systemLight)
  }

  /** `glass` — альфа фона и поверхностей при прозрачности окна (1 — непрозрачно). */
  private async apply(cover: boolean, url: string | null, preset: string, surface: Surface, light: boolean, glass = 1) {
    const my = ++this.seq
    const p = PRESETS.find((x) => x.id === preset) ?? PRESETS[0]
    const c = cover ? (url ? await colorOf(url) : null) : p.accent
    if (my !== this.seq) return
    if (cover) this.accent = c
    const root = document.documentElement
    // AMOLED — чистый чёрный, в светлой теме его нет
    root.classList.toggle('amoled', !cover && !!p.black && !light)
    root.classList.toggle('light', light)
    root.style.colorScheme = light ? 'light' : 'dark'
    const st = root.style
    const SHADE = ['--bg', '--surface-0', '--surface-1', '--surface-2', '--surface-3']
    // все цвета — по формулам OKLCH выбранной поверхности (palette.ts): обложка или готовая тема
    // дают оттенок, серая — монохром
    const t = themeFrom(c, surface in SURFACE_IDS ? surface : 'monolith', light)
    root.dataset.surface = surface
    for (const k of DECOR_VARS) if (!(k in t.vars)) st.removeProperty(k)
    // прозрачность: фон окна — с альфой непрозрачности, карточки чуть плотнее (текст читается)
    if (glass < 1) {
      t.vars['--bg'] = oklch(t.lch.bg, glass)
      t.vars['--surface-0'] = oklch(t.lch.s0, Math.min(1, glass + 0.08))
      t.vars['--surface-1'] = oklch(t.lch.s1, Math.min(1, glass + 0.12))
      t.vars['--surface-2'] = oklch(t.lch.s2, Math.min(1, glass + 0.16))
      t.vars['--surface-3'] = oklch(t.lch.s3, Math.min(1, glass + 0.2))
    }
    // AMOLED — свой чистый чёрный фон и поверхности (tokens.css), их не трогаем
    const black = root.classList.contains('amoled')
    for (const [k, v] of Object.entries(t.vars)) {
      if (black && SHADE.includes(k)) st.removeProperty(k)
      else st.setProperty(k, v)
    }
  }
}

export const theme = new Theme()
