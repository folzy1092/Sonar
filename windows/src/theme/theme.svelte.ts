// Тема под обложку (SPEC §4.4, `appearance.cover_theme`): цвет текущей обложки → акцент, фон и
// текст на акценте. Обложка идёт через локальный `/cover` (CORS и кэш на диске), цвета меняются
// плавно (CSS @property в tokens.css). Выключено или обложка серая — монохромная тема.
import { api } from '../lib/api'
import { isTauri } from '../lib/tauri'
import { player } from '../player/player.svelte'
import { css, pickAccent, themeFrom, type RGB } from './palette'

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

class Theme {
  /** `appearance.cover_theme` */
  enabled = $state(true)
  accent = $state<RGB | null>(null)
  private started = false
  private seq = 0

  init() {
    if (this.started) return
    this.started = true
    void api
      .getSetting<boolean>('appearance.cover_theme')
      .then((v) => {
        if (typeof v === 'boolean') this.enabled = v
      })
      .catch(() => {})
    $effect.root(() => {
      $effect(() => {
        const url = this.enabled ? player.current?.cover_url : null
        void this.apply(url ?? null)
      })
    })
  }

  setEnabled(on: boolean) {
    this.enabled = on
    void api.setSetting('appearance.cover_theme', on).catch(() => {})
  }

  private async apply(url: string | null) {
    const my = ++this.seq
    const c = url ? await colorOf(url) : null
    if (my !== this.seq) return
    this.accent = c
    const root = document.documentElement.style
    if (!c) {
      for (const k of ['--accent', '--accent-ink', '--accent-soft', '--tint']) root.removeProperty(k)
      return
    }
    const t = themeFrom(c)
    root.setProperty('--accent', css(t.accent))
    root.setProperty('--accent-ink', css(t.ink))
    root.setProperty('--accent-soft', css(t.accent, 0.14))
    root.setProperty('--tint', css(t.bg))
  }
}

export const theme = new Theme()
