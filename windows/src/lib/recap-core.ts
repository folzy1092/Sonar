// Итоги месяца и года (NEXT_PROMPT «Этап 11») — чистая логика без DOM: какие карточки показать,
// когда звать на Главной, цвета из обложки, листание и перенос строк для картинки. Тесты — recap-core.test.ts.
import type { ArtistStat, Recap, RecapPeriods, TrackStat } from './api'
import { contrast, inkFor, oklchToRgb, rgbToOklch, type RGB } from '../theme/palette'

export type RecapKind = 'month' | 'year'

/** Какие итоги: месяц (`month` 1–12) или год (`month` = null). */
export interface RecapRef {
  kind: RecapKind
  year: number
  month: number | null
}

/** На Главной зовём, только если за период наслушано хотя бы столько. */
export const MIN_INVITE_MS = 30 * 60_000
/** Первые дни месяца, когда на Главной приглашение на итоги прошлого месяца. */
export const INVITE_DAYS = 7
const DECEMBER = 11
const JANUARY = 0

/** Ключ итогов — для `stats.recap_seen` и имени файла: `month-2026-11`, `year-2026`. */
export function recapId(r: RecapRef): string {
  return r.kind === 'year' ? `year-${r.year}` : `month-${r.year}-${String(r.month).padStart(2, '0')}`
}

const monthRef = (year: number, month: number): RecapRef => ({ kind: 'month', year, month })
const yearRef = (year: number): RecapRef => ({ kind: 'year', year, month: null })

/** Какие итоги звать на Главной сейчас: весь декабрь — итоги года; первые `INVITE_DAYS` дней месяца —
 *  прошлый месяц (в начале января — прошлый год целиком). Мало слушал или уже открывал — null. */
export function inviteFor(now: Date, periods: RecapPeriods, seen: string | null): RecapRef | null {
  const y = now.getFullYear()
  const m = now.getMonth()
  let ref: RecapRef | null = null
  if (m === DECEMBER) ref = yearRef(y)
  else if (now.getDate() <= INVITE_DAYS) ref = m === JANUARY ? yearRef(y - 1) : monthRef(y, m)
  if (!ref || recapId(ref) === seen) return null
  const list = ref.kind === 'year' ? periods.years : periods.months
  const found = list.find((p) => p.year === ref.year && p.month === ref.month)
  return found && found.total_ms >= MIN_INVITE_MS ? ref : null
}

export type RecapCard =
  | { kind: 'intro' }
  | { kind: 'minutes'; minutes: number; delta: number | null; days: number; plays: number }
  | { kind: 'tracks'; items: TrackStat[] }
  | { kind: 'artists'; items: ArtistStat[] }
  | { kind: 'new_artist'; artist: ArtistStat; firstPlayed: string }
  | { kind: 'hour'; hour: number; hours: number[] }
  | { kind: 'day'; date: string; minutes: number; plays: number }
  | { kind: 'repeat'; track: TrackStat; count: number; date: string }
  | { kind: 'services'; items: { service: string; ms: number; pct: number }[] }

export type RecapCardKind = RecapCard['kind']

const minutes = (ms: number) => Math.round(ms / 60_000)

/** Карточки по порядку; без данных карточки нет. Совсем пусто — пустой список. */
export function buildCards(r: Recap): RecapCard[] {
  if (r.total_ms <= 0) return []
  const cards: (RecapCard | null)[] = [
    { kind: 'intro' },
    { kind: 'minutes', minutes: minutes(r.total_ms), delta: r.delta_pct, days: r.active_days, plays: r.plays },
    r.top_tracks.length ? { kind: 'tracks', items: r.top_tracks } : null,
    r.top_artists.length ? { kind: 'artists', items: r.top_artists } : null,
    r.new_artist ? { kind: 'new_artist', artist: r.new_artist.artist, firstPlayed: r.new_artist.first_played } : null,
    r.peak_hour !== null ? { kind: 'hour', hour: r.peak_hour, hours: r.hours } : null,
    r.longest_day ? { kind: 'day', date: r.longest_day.date, minutes: minutes(r.longest_day.ms), plays: r.longest_day.plays } : null,
    r.repeat ? { kind: 'repeat', track: r.repeat.track, count: r.repeat.count, date: r.repeat.date } : null,
    r.services.length ? { kind: 'services', items: r.services } : null,
  ]
  return cards.filter((c): c is RecapCard => c !== null)
}

/** Обложка, от которой берутся цвета итогов: первый трек топа, иначе трек на повторе. */
export function coverOf(r: Recap): string | null {
  return r.top_tracks.find((t) => t.cover_url)?.cover_url ?? r.repeat?.track.cover_url ?? null
}

/** Листание: следующий индекс в пределах `0…n-1`. */
export function step(index: number, delta: number, n: number): number {
  if (n <= 0) return 0
  return Math.max(0, Math.min(n - 1, index + delta))
}

/** Клавиша → куда листать: на сколько карточек, `first` / `last`; не наша клавиша — null. */
export function keyMove(key: string): number | 'first' | 'last' | null {
  switch (key) {
    case 'ArrowRight':
    case 'ArrowDown':
    case 'PageDown':
    case ' ':
      return 1
    case 'ArrowLeft':
    case 'ArrowUp':
    case 'PageUp':
      return -1
    case 'Home':
      return 'first'
    case 'End':
      return 'last'
    default:
      return null
  }
}

/** Колесо мыши: одно листание на жест — пока не прошло `WHEEL_GAP_MS` с прошлого. */
export const WHEEL_GAP_MS = 450
const WHEEL_MIN_DELTA = 4

export function wheelMove(deltaY: number, deltaX: number, now: number, last: number): number {
  const d = Math.abs(deltaY) >= Math.abs(deltaX) ? deltaY : deltaX
  if (Math.abs(d) < WHEEL_MIN_DELTA || now - last < WHEEL_GAP_MS) return 0
  return d > 0 ? 1 : -1
}

export interface RecapColors {
  /** Фон карточки: градиент от `bg` к `bg2`. */
  bg: RGB
  bg2: RGB
  accent: RGB
  /** Текст на акценте. */
  accentInk: RGB
  /** Основной текст на фоне. */
  ink: RGB
}

/** Нет обложки или она серая — спокойный сине-фиолетовый. */
const NEUTRAL = { c: 0.05, h: 280 }
const BG_L = 0.27
const BG2_L = 0.15
const ACCENT_L = 0.8
const MAX_BG_C = 0.11
const MIN_ACCENT_C = 0.09
const MAX_ACCENT_C = 0.17
const BG2_HUE_SHIFT = 30
const INK: RGB = [246, 246, 248]

/** Цвета итогов из цвета обложки (`colorOf`): тёмный фон её оттенка, светлый акцент, белый текст. */
export function recapColors(cover: RGB | null): RecapColors {
  const src = cover ? rgbToOklch(cover) : null
  const h = src && src.c > 0.02 ? src.h : NEUTRAL.h
  const c = src && src.c > 0.02 ? src.c : NEUTRAL.c
  const bg = oklchToRgb({ l: BG_L, c: Math.min(c, MAX_BG_C), h })
  const bg2 = oklchToRgb({ l: BG2_L, c: Math.min(c, MAX_BG_C) * 0.7, h: (h + BG2_HUE_SHIFT) % 360 })
  const accent = oklchToRgb({ l: ACCENT_L, c: Math.max(MIN_ACCENT_C, Math.min(c, MAX_ACCENT_C)), h })
  return { bg, bg2, accent, accentInk: inkFor(accent), ink: INK }
}

/** Текст читается на обоих краях фона (WCAG AA для крупного текста — 3, для обычного — 4.5). */
export function readableOn(c: RecapColors): boolean {
  return contrast(c.ink, c.bg) >= 4.5 && contrast(c.ink, c.bg2) >= 4.5 && contrast(c.accentInk, c.accent) >= 4.5
}

const ELLIPSIS = '…'

/** Перенос по словам в ширину `max` (ширину считает `measure` — на canvas это `measureText`);
 *  не влезло в `maxLines` — последняя строка обрезается с «…». Слово длиннее строки режется. */
export function wrapLines(text: string, max: number, measure: (s: string) => number, maxLines: number): string[] {
  const words = text.trim().split(/\s+/).filter(Boolean)
  const lines: string[] = []
  let line = ''
  for (const word of words) {
    const next = line ? `${line} ${word}` : word
    if (measure(next) <= max) {
      line = next
      continue
    }
    if (line) lines.push(line)
    line = word
  }
  if (line) lines.push(line)
  const fitted = lines.map((l) => (measure(l) <= max ? l : ellipsize(l, max, measure)))
  if (fitted.length <= maxLines) return fitted
  const kept = fitted.slice(0, maxLines)
  kept[maxLines - 1] = ellipsize(`${kept[maxLines - 1]}${ELLIPSIS}`, max, measure)
  return kept
}

/** Обрезать строку с конца, пока с «…» не влезет в `max`. */
export function ellipsize(text: string, max: number, measure: (s: string) => number): string {
  if (measure(text) <= max) return text
  let s = text.endsWith(ELLIPSIS) ? text.slice(0, -1) : text
  while (s && measure(`${s.trimEnd()}${ELLIPSIS}`) > max) s = s.slice(0, -1)
  return `${s.trimEnd()}${ELLIPSIS}`
}

/** Имя файла картинки: `Sonar month-2026-11 03-tracks`. */
export function imageName(ref: RecapRef, index: number, kind: RecapCardKind): string {
  return `Sonar ${recapId(ref)} ${String(index + 1).padStart(2, '0')}-${kind}`
}

/** Часть суток по часу: 0 — ночь (0–5), 1 — утро (6–11), 2 — день (12–17), 3 — вечер (18–23). */
export function partOfDay(hour: number): 0 | 1 | 2 | 3 {
  return Math.floor((((hour % 24) + 24) % 24) / 6) as 0 | 1 | 2 | 3
}
