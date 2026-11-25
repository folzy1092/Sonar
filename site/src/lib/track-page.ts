// Страница трека `/t/#…`: куда ведут кнопки сервисов, что встраивать, текст lrclib. Чистые функции —
// разметку и сеть делает `scripts/track.ts`.
import type { ShareData, ShareService } from './share-link'

export type LinkService = ShareService | 'am'
/** Порядок кнопок «Где послушать». */
export const LINK_ORDER: readonly LinkService[] = ['ym', 'sp', 'am', 'yt', 'sc']

export interface ServiceLink {
  readonly service: LinkService
  readonly href: string
  /** Прямая ссылка на трек (а не поиск в сервисе). */
  readonly direct: boolean
}

export const query = (d: Pick<ShareData, 't' | 'a'>) => [d.a, d.t].filter(Boolean).join(' ')

function direct(service: LinkService, d: ShareData): string | null {
  const id = service === 'am' ? undefined : d.ids[service]
  switch (service) {
    case 'ym':
      return id ? `https://music.yandex.ru/track/${id}` : null
    case 'sp':
      return id ? `https://open.spotify.com/track/${id}` : null
    case 'yt':
      return id ? `https://music.youtube.com/watch?v=${id}` : null
    case 'sc':
      return d.sl ? `https://soundcloud.com/${d.sl}` : null
    case 'am':
      return null
  }
}

function search(service: LinkService, q: string): string {
  const e = encodeURIComponent(q)
  switch (service) {
    case 'ym':
      return `https://music.yandex.ru/search?text=${e}`
    case 'sp':
      return `https://open.spotify.com/search/${e}`
    case 'am':
      return `https://music.apple.com/search?term=${e}`
    case 'yt':
      return `https://music.youtube.com/search?q=${e}`
    case 'sc':
      return `https://soundcloud.com/search/sounds?q=${e}`
  }
}

/** Кнопки: найденные — прямыми ссылками и первыми, остальные — поиском в сервисе. */
export function serviceLinks(d: ShareData): ServiceLink[] {
  const q = query(d)
  const all = LINK_ORDER.map((service) => {
    const href = direct(service, d)
    return href ? { service, href, direct: true } : { service, href: search(service, q), direct: false }
  })
  return [...all.filter((l) => l.direct), ...all.filter((l) => !l.direct)]
}

/** Встройка плеера. YouTube — без cookie до нажатия (`youtube-nocookie.com`), JS API — по postMessage. */
export function embedUrl(d: ShareData, origin: string): string | null {
  if (d.play === 'yt' && d.ids.yt) {
    const p = new URLSearchParams({ enablejsapi: '1', origin, playsinline: '1', rel: '0', autoplay: '1' })
    return `https://www.youtube-nocookie.com/embed/${d.ids.yt}?${p}`
  }
  if (d.play === 'sc' && d.ids.sc) {
    const p = new URLSearchParams({
      url: `https://api.soundcloud.com/tracks/${d.ids.sc}`,
      auto_play: 'true',
      visual: 'false',
      show_comments: 'false',
      show_user: 'false',
      show_reposts: 'false',
      show_teaser: 'false',
      hide_related: 'true',
      buying: 'false',
      sharing: 'false',
      download: 'false',
    })
    return `https://w.soundcloud.com/player/?${p}`
  }
  return null
}

/** Обложка: из ссылки, иначе превью YouTube (оно есть у любого ролика), иначе нет. */
export function coverUrl(d: ShareData): string | null {
  if (d.c) return d.c
  if (d.ids.yt) return `https://i.ytimg.com/vi/${d.ids.yt}/hqdefault.jpg`
  return null
}

/** `sonar://track/<ref>` — открыть в приложении. Ref — того сервиса, откуда делились. */
export function appLink(d: ShareData): string | null {
  const id = d.ids[d.src]
  return id ? `sonar://track/${d.src}:${id}` : null
}

// ——— текст ———

export interface LrcLine {
  /** Начало строки, с. */
  readonly at: number
  readonly text: string
}

const LRC_TIME = /\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/g

/** LRC → строки по времени. Несколько меток у строки — строка повторяется. Пустые строки — паузы. */
export function parseLrc(lrc: string): LrcLine[] {
  const out: LrcLine[] = []
  for (const raw of lrc.split(/\r?\n/)) {
    const stamps = [...raw.matchAll(LRC_TIME)]
    if (!stamps.length) continue
    const text = raw.replace(LRC_TIME, '').trim()
    for (const m of stamps) out.push({ at: Number(m[1]) * 60 + Number(m[2].replace(':', '.')), text })
  }
  return out.sort((a, b) => a.at - b.at)
}

/** Номер текущей строки (−1 — до первой). Двоичный поиск: вызывается на каждом кадре. */
export function lineAt(lines: readonly LrcLine[], t: number): number {
  let lo = 0
  let hi = lines.length - 1
  let ans = -1
  while (lo <= hi) {
    const mid = (lo + hi) >> 1
    if (lines[mid].at <= t + 0.15) {
      ans = mid
      lo = mid + 1
    } else hi = mid - 1
  }
  return ans
}

const DASH_SPLIT = /\s+[-‐-―−]\s+/
/** Хвосты названия, которые мешают lrclib: «(slowed)», «[Official Video]», «prod. …», «feat. …». */
const TITLE_TAILS = [
  /\s*[([][^()[\]]*(?:slowed|sped|speed|reverb|nightcore|official|video|audio|lyrics?|visualizer|prod|remaster)[^()[\]]*[)\]]\s*$/i,
  /\s+(?:prod(?:uced)?\.?|feat\.?|ft\.?)\s.*$/i,
  /\.(?:mp3|wav|flac|m4a)\s*$/i,
]

export function cleanTitle(title: string): string {
  let t = title.trim()
  for (let i = 0; i < 4; i++) {
    const before = t
    for (const re of TITLE_TAILS) t = t.replace(re, '').trim()
    if (t === before) break
  }
  return t || title.trim()
}

/**
 * Пары (артист, название) для lrclib по очереди. Перезаливы «АРТИСТ - ТРЕК» на SoundCloud — облегчённый
 * разбор (полный — `lyrics/title_split.rs` в приложении): левая часть — артист, правая — название.
 */
export function lyricsPairs(d: Pick<ShareData, 't' | 'a'>): Array<[string, string]> {
  const out: Array<[string, string]> = []
  const add = (a: string, t: string) => {
    const pair: [string, string] = [a.trim(), cleanTitle(t)]
    if (pair[0] && pair[1] && !out.some((p) => p[0].toLowerCase() === pair[0].toLowerCase() && p[1].toLowerCase() === pair[1].toLowerCase()))
      out.push(pair)
  }
  add(d.a, d.t)
  const parts = d.t.split(DASH_SPLIT)
  if (parts.length === 2) add(parts[0], parts[1])
  return out
}

export interface LrclibHit {
  readonly duration?: number
  readonly syncedLyrics?: string | null
  readonly plainLyrics?: string | null
  readonly instrumental?: boolean
}

/** Из выдачи `/api/search` — лучшая: длительность ±3 с (если знаем), синхронный текст — выше. */
export function bestHit<T extends LrclibHit>(hits: readonly T[], duration?: number): T | null {
  const ok = hits.filter((h) => (h.syncedLyrics || h.plainLyrics) && (!duration || !h.duration || Math.abs(h.duration - duration) <= 3))
  return ok.find((h) => h.syncedLyrics) ?? ok[0] ?? null
}

export function formatTime(sec: number): string {
  const s = Math.max(0, Math.floor(sec))
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}
