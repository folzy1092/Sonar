// Стиль интерфейса (Интерфейс → Стиль, reference/design/STYLE_PROMPT.md): набор независимых осей —
// поверхности, шрифты, оформление заголовков, толщина линий, анимации смены трека / лайка / выбора
// раздела, вид прогресса и загрузки. Готовый стиль ставит все оси; изменение любой оси вручную
// делает стиль «Своим» (без сохранения), его можно сохранить под своим именем.
import type { Surface } from './palette'

export type AnimTrack = Surface | 'fade'
export type AnimLike = Surface | 'pop'
export type AnimNav = 'dot' | 'capsule' | 'plate' | 'inset'
export type ProgressLook = 'line' | 'wave' | 'groove'
export type LoadingLook = 'color' | 'ring'
export type TitleStyle = 'plain' | 'editorial'
export type IconStroke = 1.5 | 1.75 | 2

/** Оси стиля и их ключи в настройках. Скругления (`corner_radius`) — тоже ось «Своего», но готовые
 *  стили их не меняют: форму задаёт пользователь. */
export interface StyleAxes {
  surface: Surface
  font: string
  font_display: string
  title_style: TitleStyle
  icon_stroke: IconStroke
  anim_track: AnimTrack
  anim_like: AnimLike
  anim_nav: AnimNav
  progress_look: ProgressLook
  loading: LoadingLook
}

export type AxisName = keyof StyleAxes

export const AXES: AxisName[] = ['surface', 'font', 'font_display', 'title_style', 'icon_stroke', 'anim_track', 'anim_like', 'anim_nav', 'progress_look', 'loading']

export const axisKey = <A extends AxisName>(a: A) => `appearance.${a}` as const

export interface StylePreset {
  id: string
  title: string
  axes: StyleAxes
}

/** Готовые стили (таблица в STYLE_PROMPT.md). Шрифты — имена из theme/look.ts. */
export const STYLES: StylePreset[] = [
  {
    id: 'sonar',
    title: 'Sonar',
    axes: { surface: 'monolith', font: 'Golos Text Variable', font_display: 'Unbounded Variable', title_style: 'plain', icon_stroke: 2, anim_track: 'edge', anim_like: 'signal', anim_nav: 'dot', progress_look: 'line', loading: 'color' },
  },
  {
    id: 'echo',
    title: 'Эхо',
    axes: { surface: 'echo', font: 'Onest Variable', font_display: 'Science Gothic Variable', title_style: 'plain', icon_stroke: 1.75, anim_track: 'echo', anim_like: 'echo', anim_nav: 'dot', progress_look: 'line', loading: 'ring' },
  },
  {
    id: 'signal',
    title: 'Сигнал',
    axes: { surface: 'signal', font: 'Golos Text Variable', font_display: 'Unbounded Variable', title_style: 'plain', icon_stroke: 2, anim_track: 'signal', anim_like: 'signal', anim_nav: 'capsule', progress_look: 'wave', loading: 'ring' },
  },
  {
    id: 'edge',
    title: 'Грань',
    axes: { surface: 'edge', font: 'Geist Variable', font_display: 'Geist Variable', title_style: 'plain', icon_stroke: 1.75, anim_track: 'edge', anim_like: 'edge', anim_nav: 'plate', progress_look: 'line', loading: 'color' },
  },
  {
    id: 'tactile',
    title: 'Тактиль',
    axes: { surface: 'tactile', font: 'IBM Plex Sans Variable', font_display: 'IBM Plex Sans Variable', title_style: 'plain', icon_stroke: 2, anim_track: 'tactile', anim_like: 'tactile', anim_nav: 'inset', progress_look: 'groove', loading: 'ring' },
  },
  {
    id: 'monolith',
    title: 'Монолит',
    axes: { surface: 'monolith', font: 'Inter Tight Variable', font_display: 'Inter Tight Variable', title_style: 'plain', icon_stroke: 2, anim_track: 'monolith', anim_like: 'monolith', anim_nav: 'dot', progress_look: 'line', loading: 'color' },
  },
]

export const DEFAULT_STYLE = STYLES[0]

/** Свой сохранённый стиль (`appearance.custom_styles`). */
export interface CustomStyle {
  id: string
  name: string
  axes: StyleAxes
}

export const CUSTOM_STYLE_PREFIX = 'custom:'

/** Особые настройки шрифта заголовков у стилей: ширина (ось wdth) и жирность. */
export const DISPLAY_TUNING: Record<string, { wdth?: number; weight?: number; tracking?: string }> = {
  'Science Gothic Variable': { wdth: 165, weight: 800 },
  'IBM Plex Sans Variable': { wdth: 78, weight: 700 },
  'Inter Tight Variable': { weight: 900, tracking: '-0.05em' },
  'Geist Variable': { weight: 800, tracking: '-0.045em' },
  'Unbounded Variable': { weight: 700, tracking: '-0.01em' },
  'Sofia Sans Extra Condensed Variable': { weight: 900 },
}

/** Шрифты с осью ширины `wdth` — у них заголовок «дышит» при смене трека (anim_track echo). */
export const WDTH_FONTS = new Set(['Science Gothic Variable', 'IBM Plex Sans Variable', 'Roboto Flex Variable', 'Sofia Sans Variable', 'Open Sans Variable'])

export function sameAxes(a: StyleAxes, b: StyleAxes): boolean {
  return AXES.every((k) => String(a[k]) === String(b[k]))
}

export const SURFACE_LABELS: Record<Surface, string> = {
  echo: 'Эхо',
  signal: 'Сигнал',
  edge: 'Грань',
  tactile: 'Тактиль',
  monolith: 'Монолит',
}

/** Значение `appearance.style` для несохранённого «Своего». */
export const UNSAVED = 'custom'

/** Оси выбранного стиля: готового, своего сохранённого; несохранённый «Свой» — null. */
export function styleAxes(id: string, customs: CustomStyle[]): StyleAxes | null {
  if (id.startsWith(CUSTOM_STYLE_PREFIX)) return customs.find((c) => CUSTOM_STYLE_PREFIX + c.id === id)?.axes ?? null
  return STYLES.find((s) => s.id === id)?.axes ?? null
}

/**
 * Какой стиль сейчас: выбранный, если его оси совпадают с текущими; иначе готовый или свой с такими
 * же осями; иначе несохранённый «Свой». Так любая ручная правка оси (в «Стиле» или в «Виде»)
 * переключает на «Свой», а возврат к значениям стиля — снова на него.
 */
export function matchStyle(current: string, axes: StyleAxes, customs: CustomStyle[]): string {
  const cur = styleAxes(current, customs)
  if (cur && sameAxes(cur, axes)) return current
  const preset = STYLES.find((s) => sameAxes(s.axes, axes))
  if (preset) return preset.id
  const own = customs.find((c) => sameAxes(c.axes, axes))
  if (own) return CUSTOM_STYLE_PREFIX + own.id
  return UNSAVED
}

/** Готовый стиль, ближайший к осям (больше всего совпадений) — для «Сбросить к стилю …». */
export function nearestPreset(axes: StyleAxes): StylePreset {
  let best = DEFAULT_STYLE
  let score = -1
  for (const s of STYLES) {
    const n = AXES.filter((k) => String(s.axes[k]) === String(axes[k])).length
    if (n > score) {
      score = n
      best = s
    }
  }
  return best
}

/** Новый свой стиль с уникальным id; имя обрезано, пустое — «Мой стиль N». */
export function newCustom(name: string, axes: StyleAxes, customs: CustomStyle[], rand = Math.random): CustomStyle {
  const base = name.trim().slice(0, 40) || `Мой стиль ${customs.length + 1}`
  let id = ''
  do id = Math.floor(rand() * 36 ** 6).toString(36).padStart(6, '0')
  while (customs.some((c) => c.id === id))
  return { id, name: base, axes: { ...axes } }
}
