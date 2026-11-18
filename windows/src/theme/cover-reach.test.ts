import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import mini from '../app/MiniPlayer.svelte?raw'
import row from '../components/TrackRow.svelte?raw'
import header from '../components/CollectionHeader.svelte?raw'
import logo from '../components/LogoMark.svelte?raw'
import navIcon from '../components/NavIcon.svelte?raw'
import iconButton from '../components/IconButton.svelte?raw'
import { DECOR_VARS, themeFrom } from './palette'

// Этап 0 п. 10–11: цвет обложки доходит до всего интерфейса, и меняется он плавно.

// CSS через ?raw в vitest приходит пустым (обработка CSS выключена) — читаем файлом
const read = (rel: string) => readFileSync(new URL(rel, import.meta.url), 'utf8')
const tokens = read('./tokens.css')
const appCss = read('../app.css')

/** Тело CSS-правила по селектору (первое совпадение). */
function rule(src: string, selector: string): string {
  const at = src.indexOf(`${selector} {`)
  if (at < 0) return ''
  return src.slice(at, src.indexOf('}', at))
}

describe('cover colour reaches the interface', () => {
  it('every colour token of the theme animates through @property', () => {
    const colorVars = Object.keys(themeFrom([28, 36, 104], 'echo', false, { strength: 'strong', lightness: 0.1 }).vars).filter((k) => !DECOR_VARS.includes(k))
    for (const name of colorVars) {
      expect(tokens, name).toContain(`@property ${name} {`)
      expect(tokens, name).toMatch(new RegExp(`${name} 0\\.6s`))
    }
  })

  it('logo and selected nav icon take the accent', () => {
    expect(logo).toContain('var(--accent)')
    expect(rule(navIcon, '.fill')).toContain('var(--accent)')
  })

  it('big heart of the collection takes the accent', () => {
    expect(rule(header, '.cover.heart')).toContain('var(--accent)')
  })

  it('indicator line under tabs takes the accent', () => {
    expect(rule(appCss, '.tab-ind.line')).toContain('var(--accent)')
  })

  it('current track title and equalizer take the accent', () => {
    expect(rule(row, '.current .title')).toContain('var(--accent)')
    expect(rule(row, '.eq i')).toContain('var(--accent)')
  })

  it('repeat, shuffle and like in the mini player light up with the accent', () => {
    expect(rule(iconButton, '.icon-btn.active')).toContain('var(--accent)')
    for (const icon of ['heart', 'shuffle']) expect(mini).toMatch(new RegExp(`icon="${icon}"[^>]*active=`))
    expect(mini).toMatch(/active=\{player\.repeat !== 'off'\}/)
  })

  it('mini player has a soft cover glow on the left', () => {
    expect(rule(mini, '.cover-glow')).toContain('var(--glow)')
    expect(mini).toContain("class:on={!!track && settings.get('appearance.cover_theme')")
  })

  it('mini player glow stays around the cover and fades out before the title and artist', () => {
    // под текстом свечения нет — --text-3 читается на чистом фоне плеера (AA), без примеси --glow
    const glow = rule(mini, '.cover-glow').match(/radial-gradient\((\d+)px [^)]*at calc\((\d+)px \+ 4px \* var\(--cap-k, 1\)\)/)
    expect(glow).not.toBeNull()
    const [radius, centre] = [Number(glow![1]), Number(glow![2])]
    const pad = Number(rule(mini, '.mini').match(/padding-left: calc\((\d+)px \+ 4px \* var\(--cap-k, 1\)\)/)![1])
    const nowPad = Number(rule(mini, '.now').match(/padding: (\d+)px/)![1])
    const gap = Number(rule(mini, '.now').match(/gap: (\d+)px/)![1])
    const cover = Number(mini.match(/<Cover url=\{track\?\.cover_url\} size=\{(\d+)\}/)![1])
    // центр — середина обложки, край ореола — не дальше начала колонки текста
    expect(centre).toBe(pad + nowPad + cover / 2)
    expect(centre + radius).toBeLessThanOrEqual(pad + nowPad + cover + gap)
    // и за края обложки он всё же выходит — иначе его не видно
    expect(radius).toBeGreaterThan(cover / 2)
  })
})
