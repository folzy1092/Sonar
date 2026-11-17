/** Экспорт плейлиста в файл (NEXT_PROMPT, этап 8): M3U8, CSV и JSON. Здесь — только чистые
 *  функции: текст файла по списку треков и безопасное имя файла. Сохраняет файл Rust
 *  (`src-tauri/src/export.rs`, окно «Сохранить как»); та же логика на iPhone —
 *  `ios/Sonar/Core/Export/PlaylistExport.swift`. */
import type { Track } from './api'
import { parseRef } from './services'

export type ExportFormat = 'm3u8' | 'csv' | 'json'

export const EXPORT_FORMATS: readonly ExportFormat[] = Object.freeze(['m3u8', 'csv', 'json'])

/** Трек для экспорта: поля `Track` из API.md + когда добавлен (мс, у плейлистов сервисов — нет). */
export type ExportTrack = Track & { added_at?: number | null }

/** Длинное имя файла обрезаем (то же число — `MAX_NAME_CHARS` в export.rs). */
export const MAX_NAME_CHARS = 100
/** Имя, если от названия плейлиста ничего не осталось. */
export const FALLBACK_NAME = 'Sonar'
const FORBIDDEN = /[<>:"/\\|?*\p{Cc}]/gu
const RESERVED = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])$/i
/** Начало ячейки, которое Excel и Таблицы считают формулой. */
const FORMULA_START = /^[=+\-@\t\r]/
const CSV_COLUMNS = ['title', 'artist', 'album', 'duration', 'service', 'link', 'added'] as const

/** Название плейлиста → имя файла без расширения: запрещённые знаки и управляющие символы —
 *  пробел, пробелы схлопываются, точки и пробелы по краям убираются, до `MAX_NAME_CHARS`
 *  символов, имя устройства Windows (CON, NUL…) — с `_` в начале, пустое — `Sonar`. */
export function safeFileName(name: string): string {
  const collapsed = name.replace(FORBIDDEN, ' ').split(/\s+/u).filter(Boolean).join(' ')
  const cut = Array.from(collapsed).slice(0, MAX_NAME_CHARS).join('')
  const trimmed = cut.replace(/^[.\s]+|[.\s]+$/gu, '')
  if (!trimmed) return FALLBACK_NAME
  const stem = trimmed.split('.')[0].trim()
  return RESERVED.test(stem) ? `_${trimmed}` : trimmed
}

/** Ссылка на трек на сайте сервиса: своя ссылка трека (если http/https), иначе — по ref из
 *  реестра (§2 «Префиксы ref»). У SoundCloud без ссылки и у локальных файлов — `null`. */
export function trackWebUrl(track: Pick<Track, 'ref' | 'url'>): string | null {
  if (track.url && /^https?:\/\//i.test(track.url)) return track.url
  const parsed = parseRef(track.ref)
  if (!parsed || parsed.kind !== 'track') return null
  const id = encodeURIComponent(track.ref.slice(track.ref.indexOf(':') + 1))
  if (!id) return null
  switch (parsed.service.id) {
    case 'ym':
      return `https://music.yandex.ru/track/${id}`
    case 'yt':
      return `https://music.youtube.com/watch?v=${id}`
    case 'sp':
      return `https://open.spotify.com/track/${id}`
    case 'vk':
      return `https://vk.com/audio${id}`
    default:
      return null
  }
}

/** Название сервиса трека по реестру (как есть, без перевода). */
export function serviceName(ref: string): string {
  return parseRef(ref)?.service.name ?? ''
}

function oneLine(s: string): string {
  return s.replace(/[\r\n]+/g, ' ').trim()
}

function seconds(ms: number): number {
  return Number.isFinite(ms) && ms > 0 ? Math.round(ms / 1000) : 0
}

/** M3U8 (UTF-8): `#EXTINF:<сек>,<артист> - <название>`, следующей строкой — ссылка на трек
 *  (нет ссылки — ref). Неизвестная длительность — `-1`, как велит формат. */
export function toM3u8(name: string, tracks: readonly ExportTrack[]): string {
  const lines = ['#EXTM3U', `#PLAYLIST:${oneLine(name)}`]
  for (const track of tracks) {
    const sec = seconds(track.duration_ms)
    const label = [oneLine(track.artist), oneLine(track.title)].filter(Boolean).join(' - ')
    lines.push(`#EXTINF:${sec > 0 ? sec : -1},${label}`)
    lines.push(oneLine(trackWebUrl(track) ?? track.ref))
  }
  return `${lines.join('\n')}\n`
}

/** Ячейка CSV по RFC 4180: в кавычках, если есть запятая, кавычка или перенос строки; кавычки
 *  удваиваются. `text` — пользовательский текст: начало-формулу гасим апострофом. */
export function csvCell(value: string, text = false): string {
  const safe = text && FORMULA_START.test(value) ? `'${value}` : value
  return /[",\r\n]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe
}

function isoDate(ms: number | null | undefined): string {
  if (ms === null || ms === undefined || !Number.isFinite(ms)) return ''
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z')
}

/** CSV: BOM (чтобы Excel узнал UTF-8), строки через CRLF. `duration` — секунды, `added` —
 *  дата ISO 8601 в UTC (пусто, если неизвестна), `service` — название сервиса (`label`). */
export function toCsv(tracks: readonly ExportTrack[], label: (ref: string) => string = serviceName): string {
  const rows = [CSV_COLUMNS.join(',')]
  for (const track of tracks) {
    rows.push(
      [
        csvCell(track.title, true),
        csvCell(track.artist, true),
        csvCell(track.album?.title ?? '', true),
        String(seconds(track.duration_ms)),
        csvCell(label(track.ref), true),
        csvCell(trackWebUrl(track) ?? ''),
        isoDate(track.added_at),
      ].join(','),
    )
  }
  return `﻿${rows.join('\r\n')}\r\n`
}

/** JSON: массив `Track` в форме и порядке полей API.md + `added_at` (мс или `null`). Лишние
 *  поля клиента (`plays`, `why`) в файл не идут. */
export function toJson(tracks: readonly ExportTrack[]): string {
  const rows = tracks.map((track) => ({
    ref: track.ref,
    title: track.title,
    artist: track.artist,
    artists: track.artists.map((a) => ({ ref: a.ref, name: a.name, avatar_url: a.avatar_url })),
    album: track.album ? { ref: track.album.ref, title: track.album.title } : null,
    duration_ms: track.duration_ms,
    cover_url: track.cover_url,
    url: track.url,
    explicit: track.explicit,
    available: track.available,
    added_at: track.added_at ?? null,
  }))
  return `${JSON.stringify(rows, null, 2)}\n`
}

/** Текст файла в нужном формате. */
export function exportText(
  format: ExportFormat,
  name: string,
  tracks: readonly ExportTrack[],
  label?: (ref: string) => string,
): string {
  if (format === 'm3u8') return toM3u8(name, tracks)
  if (format === 'csv') return toCsv(tracks, label)
  return toJson(tracks)
}
