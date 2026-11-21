import { describe, expect, it } from 'vitest'
import { CUSTOM_STYLE_PREFIX, DEFAULT_STYLE, matchStyle, nearestPreset, newCustom, STYLES, UNSAVED, type StyleAxes } from './style'
import { DEFAULTS } from '../lib/settings.svelte'

const classic = DEFAULT_STYLE.axes

describe('стили', () => {
  it('значения по умолчанию — ровно «Классика»', () => {
    const axes = {
      surface: DEFAULTS['appearance.surface'],
      font: DEFAULTS['appearance.font'],
      font_display: DEFAULTS['appearance.font_display'],
      title_style: DEFAULTS['appearance.title_style'],
      icon_stroke: DEFAULTS['appearance.icon_stroke'],
      anim_track: DEFAULTS['appearance.anim_track'],
      anim_like: DEFAULTS['appearance.anim_like'],
      anim_nav: DEFAULTS['appearance.anim_nav'],
      progress_look: DEFAULTS['appearance.progress_look'],
      loading: DEFAULTS['appearance.loading'],
    } as StyleAxes
    expect(DEFAULT_STYLE.id).toBe('classic')
    expect(matchStyle('classic', axes, [])).toBe('classic')
  })

  it('правка оси — «Свой», возврат к значениям — снова стиль', () => {
    const changed = { ...classic, anim_like: 'echo' as const }
    expect(matchStyle('classic', changed, [])).toBe(UNSAVED)
    expect(matchStyle(UNSAVED, classic, [])).toBe('classic')
  })

  it('собранный из частей и сохранённый — узнаётся как свой', () => {
    const mix: StyleAxes = { ...STYLES[6].axes, font: 'Golos Text Variable', anim_track: 'edge', anim_like: 'signal', surface: 'monolith' }
    const own = newCustom('  Мой  ', mix, [], () => 0.5)
    expect(own.name).toBe('Мой')
    expect(matchStyle(UNSAVED, mix, [own])).toBe(CUSTOM_STYLE_PREFIX + own.id)
    expect(newCustom('', mix, [own]).name).toBe('Мой стиль 2')
  })

  it('ближайший готовый стиль', () => {
    expect(nearestPreset({ ...STYLES[4].axes, anim_like: 'pop' }).id).toBe('edge')
  })

  it('у готовых стилей разные оси', () => {
    const keys = STYLES.map((s) => JSON.stringify(s.axes))
    expect(new Set(keys).size).toBe(STYLES.length)
  })
})
