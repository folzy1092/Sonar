// Карточка итогов картинкой: тот же текст, что на экране (recap-text.ts), рисуется на canvas
// 1080×1350 (4:5 — так её не режут ни Telegram, ни истории). Обложки — через локальный сервер
// (`proxied`), иначе canvas «испорчен» и PNG не получить.
import type { Recap } from './api'
import { durationText } from './format'
import { byId } from './services'
import { SITE_URL } from './site'
import { cardText, numberText, periodTitle, recapKindTitle, serviceTitle } from './recap-text'
import { wrapLines, type RecapCard, type RecapColors, type RecapRef } from './recap-core'
import { css } from '../theme/palette'
import { proxied } from '../theme/theme.svelte'

export const CARD_W = 1080
export const CARD_H = 1350
const PAD = 96
const INNER = CARD_W - PAD * 2
const EYEBROW_Y = 250
const BODY_Y = 330
const FOOTER_Y = CARD_H - 80
const ROW_H = 172
const ROW_COVER = 128
const FALLBACK_FONT = 'system-ui, sans-serif'
/** Начертания, которыми рисуется карточка: их грузим заранее, иначе canvas молча возьмёт запасной шрифт. */
const WEIGHTS = [500, 600, 700, 800]

type Ctx = CanvasRenderingContext2D
type Images = Map<string, HTMLImageElement>

interface Scene {
  g: Ctx
  card: RecapCard
  ref: RecapRef
  colors: RecapColors
  images: Images
  font: string
}

function fontFamily(): string {
  const v = getComputedStyle(document.documentElement).getPropertyValue('--font-display').trim()
  return v || FALLBACK_FONT
}

const setFont = (s: Scene, size: number, weight = 600) => (s.g.font = `${weight} ${size}px ${s.font}`)
const ink = (s: Scene, a = 1) => css(s.colors.ink, a)

/** Начертания `WEIGHTS` с кириллицей; не загрузилось — рисуем тем, что есть (картинка важнее шрифта). */
async function loadFonts(family: string): Promise<void> {
  const fonts = document.fonts
  if (!fonts?.load) return
  await Promise.all(WEIGHTS.map((w) => fonts.load(`${w} 40px ${family}`, 'Aa Яя').catch(() => [])))
  await fonts.ready
}

async function loadImage(url: string): Promise<HTMLImageElement | null> {
  const src = await proxied(url)
  return new Promise((resolve) => {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.onload = () => resolve(img)
    img.onerror = () => resolve(null)
    img.src = src
  })
}

/** Какие картинки нужны карточке. */
function imageUrls(card: RecapCard, data: Recap): string[] {
  const urls = (() => {
    switch (card.kind) {
      case 'intro':
        return [data.top_tracks[0]?.cover_url]
      case 'tracks':
        return card.items.map((t) => t.cover_url)
      case 'artists':
        return card.items.map((a) => a.avatar_url)
      case 'new_artist':
        return [card.artist.avatar_url]
      case 'repeat':
        return [card.track.cover_url]
      default:
        return []
    }
  })()
  return urls.filter((u): u is string => !!u)
}

async function loadImages(urls: string[]): Promise<Images> {
  const loaded = await Promise.all(urls.map(async (u) => [u, await loadImage(u)] as const))
  return new Map(loaded.filter((e): e is [string, HTMLImageElement] => e[1] !== null))
}

function roundRect(g: Ctx, x: number, y: number, w: number, h: number, r: number) {
  g.beginPath()
  g.roundRect(x, y, w, h, r)
}

/** Картинка с обрезкой по форме (`round` — круг); нет картинки — плашка цвета текста. */
function picture(s: Scene, url: string | null, x: number, y: number, size: number, round = false) {
  const { g } = s
  g.save()
  if (round) {
    g.beginPath()
    g.arc(x + size / 2, y + size / 2, size / 2, 0, Math.PI * 2)
  } else roundRect(g, x, y, size, size, size * 0.12)
  g.clip()
  const img = url ? s.images.get(url) : undefined
  if (img) g.drawImage(img, x, y, size, size)
  else {
    g.fillStyle = ink(s, 0.12)
    g.fillRect(x, y, size, size)
  }
  g.restore()
}

/** Текст в ширину `max` по строкам; вернёт y под последней строкой. */
function paragraph(s: Scene, text: string, x: number, y: number, max: number, size: number, maxLines: number, color: string, weight = 600) {
  setFont(s, size, weight)
  s.g.fillStyle = color
  const lines = wrapLines(text, max, (t) => s.g.measureText(t).width, maxLines)
  lines.forEach((line, i) => s.g.fillText(line, x, y + i * size * 1.15))
  return y + lines.length * size * 1.15
}

function background(s: Scene) {
  const { g, colors } = s
  const grad = g.createLinearGradient(0, 0, CARD_W, CARD_H)
  grad.addColorStop(0, css(colors.bg))
  grad.addColorStop(1, css(colors.bg2))
  g.fillStyle = grad
  g.fillRect(0, 0, CARD_W, CARD_H)
  const glow = g.createRadialGradient(CARD_W * 0.85, CARD_H * 0.1, 0, CARD_W * 0.85, CARD_H * 0.1, CARD_W * 0.8)
  glow.addColorStop(0, css(colors.accent, 0.32))
  glow.addColorStop(1, css(colors.accent, 0))
  g.fillStyle = glow
  g.fillRect(0, 0, CARD_W, CARD_H)
}

function chrome(s: Scene, eyebrow: string) {
  const { g } = s
  g.textBaseline = 'alphabetic'
  setFont(s, 40, 800)
  g.fillStyle = css(s.colors.accent)
  g.fillText('SONAR', PAD, 150)
  setFont(s, 36, 500)
  g.fillStyle = ink(s, 0.7)
  g.textAlign = 'right'
  g.fillText(periodTitle(s.ref), CARD_W - PAD, 150)
  g.textAlign = 'left'
  paragraph(s, eyebrow.toUpperCase(), PAD, EYEBROW_Y, INNER, 38, 1, css(s.colors.accent), 700)
  setFont(s, 30, 500)
  g.fillStyle = ink(s, 0.55)
  g.fillText(`${recapKindTitle(s.ref)} · ${SITE_URL.replace(/^https:\/\//, '')}`, PAD, FOOTER_Y)
}

/** Крупное число с подписью; вернёт y под ним. */
function bigValue(s: Scene, value: number, unit: string, y: number) {
  const { g } = s
  setFont(s, 220, 800)
  g.fillStyle = css(s.colors.accent)
  const text = numberText(value)
  g.fillText(text, PAD, y + 190)
  return paragraph(s, unit, PAD, y + 270, INNER, 60, 2, ink(s), 600) + 20
}

function lines(s: Scene, list: string[], y: number) {
  let at = y
  for (const line of list) at = paragraph(s, line, PAD, at + 46, INNER, 44, 2, ink(s, 0.75), 500) + 10
  return at
}

function rankedRows(s: Scene, rows: { title: string; sub: string; image: string | null }[], round: boolean) {
  rows.forEach((row, i) => {
    const y = BODY_Y + 40 + i * ROW_H
    setFont(s, 52, 800)
    s.g.fillStyle = i === 0 ? css(s.colors.accent) : ink(s, 0.5)
    s.g.fillText(String(i + 1), PAD, y + ROW_COVER / 2 + 18)
    picture(s, row.image, PAD + 70, y, ROW_COVER, round)
    const x = PAD + 70 + ROW_COVER + 36
    const max = CARD_W - PAD - x
    paragraph(s, row.title, x, y + 54, max, 46, 1, ink(s), 700)
    paragraph(s, row.sub, x, y + 106, max, 36, 1, ink(s, 0.65), 500)
  })
}

function hourBars(s: Scene, hours: number[], peak: number) {
  const top = BODY_Y + 420
  const height = 380
  const gap = 10
  const w = (INNER - gap * 23) / 24
  const max = Math.max(1, ...hours)
  hours.forEach((ms, h) => {
    const bh = Math.max(8, (ms / max) * height)
    s.g.fillStyle = h === peak ? css(s.colors.accent) : ink(s, 0.22)
    roundRect(s.g, PAD + h * (w + gap), top + height - bh, w, bh, w / 2)
    s.g.fill()
  })
  setFont(s, 30, 500)
  s.g.fillStyle = ink(s, 0.55)
  for (const h of [0, 6, 12, 18]) s.g.fillText(`${h}:00`, PAD + h * (w + gap), top + height + 50)
}

function serviceBars(s: Scene, items: { service: string; pct: number }[]) {
  items.slice(0, 5).forEach((it, i) => {
    const y = BODY_Y + 180 + i * 150
    setFont(s, 48, 700)
    s.g.fillStyle = ink(s)
    s.g.fillText(serviceTitle(it.service), PAD, y)
    s.g.textAlign = 'right'
    s.g.fillText(`${it.pct}%`, CARD_W - PAD, y)
    s.g.textAlign = 'left'
    s.g.fillStyle = ink(s, 0.12)
    roundRect(s.g, PAD, y + 30, INNER, 28, 14)
    s.g.fill()
    s.g.fillStyle = byId(it.service)?.color ?? css(s.colors.accent)
    roundRect(s.g, PAD, y + 30, Math.max(28, (INNER * it.pct) / 100), 28, 14)
    s.g.fill()
  })
}

function body(s: Scene, data: Recap) {
  const { card } = s
  const text = cardText(card, s.ref)
  switch (card.kind) {
    case 'intro': {
      const cover = data.top_tracks[0]?.cover_url ?? null
      picture(s, cover, PAD, BODY_Y + 20, 520)
      const y = paragraph(s, text.title, PAD, BODY_Y + 700, INNER, 130, 2, ink(s), 800)
      lines(s, text.lines, y)
      return
    }
    case 'tracks':
      return rankedRows(s, card.items.map((t) => ({ title: t.title, sub: t.artist, image: t.cover_url })), false)
    case 'artists':
      return rankedRows(s, card.items.map((a) => ({ title: a.name, sub: durationText(a.ms), image: a.avatar_url })), true)
    case 'new_artist': {
      picture(s, card.artist.avatar_url, PAD, BODY_Y + 20, 460, true)
      const y = paragraph(s, text.title, PAD, BODY_Y + 600, INNER, 100, 2, ink(s), 800)
      lines(s, text.lines, y)
      return
    }
    case 'hour': {
      const y = paragraph(s, text.title, PAD, BODY_Y + 160, INNER, 150, 1, ink(s), 800)
      lines(s, text.lines, y)
      return hourBars(s, card.hours, card.hour)
    }
    case 'repeat': {
      picture(s, card.track.cover_url, PAD, BODY_Y + 20, 360)
      const y = bigValue(s, text.value ?? 0, text.unit, BODY_Y + 400)
      const after = paragraph(s, text.title, PAD, y + 50, INNER, 56, 2, ink(s), 700)
      return lines(s, text.lines, after - 10)
    }
    case 'services':
      return serviceBars(s, card.items)
    default: {
      // минуты и самый длинный день: большое число, заголовок, строки
      let y = bigValue(s, text.value ?? 0, text.unit, BODY_Y + 60)
      if (text.title) y = paragraph(s, text.title, PAD, y + 60, INNER, 60, 2, ink(s), 700)
      lines(s, text.lines, y)
    }
  }
}

/** Нарисовать карточку на новом canvas 1080×1350. */
export async function renderCard(card: RecapCard, ref: RecapRef, data: Recap, colors: RecapColors): Promise<HTMLCanvasElement> {
  const font = fontFamily()
  await loadFonts(font)
  const images = await loadImages(imageUrls(card, data))
  const canvas = document.createElement('canvas')
  canvas.width = CARD_W
  canvas.height = CARD_H
  const g = canvas.getContext('2d')
  if (!g) throw new Error('Не удалось нарисовать картинку')
  const s: Scene = { g, card, ref, colors, images, font }
  background(s)
  chrome(s, cardText(card, ref).eyebrow)
  body(s, data)
  return canvas
}

/** Карточка в PNG. */
export async function cardPng(card: RecapCard, ref: RecapRef, data: Recap, colors: RecapColors): Promise<Blob> {
  const canvas = await renderCard(card, ref, data, colors)
  return new Promise((resolve, reject) =>
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('Не удалось нарисовать картинку'))), 'image/png'),
  )
}

