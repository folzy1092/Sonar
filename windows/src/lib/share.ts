// «Поделиться» треком: ссылка на страницу сайта `try-sonar.ru/t/#…` (docs/SPACE_SHARE_PROMPT.md §3).
// Формат — `share-link.ts` (копия файла сайта, байт в байт); здесь — сборка данных из трека и двойников.
import type { ShareTwins, Track } from './api'
import { isShareService, pickPlay, scPath, shareUrl, validCover, validId, type ShareData, type ShareService } from './share-link'

const ref = (r: string) => {
  const i = r.indexOf(':')
  return i < 0 ? null : { service: r.slice(0, i), id: r.slice(i + 1) }
}

/** Трек + найденные двойники → данные ссылки. Локальный файл и чужие ref — null (делиться нечем). */
export function shareData(track: Track, twins?: ShareTwins | null): ShareData | null {
  const own = ref(track.ref)
  if (!own || !isShareService(own.service) || !validId(own.service, own.id)) return null
  const src: ShareService = own.service
  const ids: ShareData['ids'] = { [src]: own.id }
  for (const r of Object.values(twins?.refs ?? {})) {
    const p = ref(r)
    if (p && isShareService(p.service) && !ids[p.service] && validId(p.service, p.id)) ids[p.service] = p.id
  }
  const scUrl = src === 'sc' ? track.url : twins?.urls.sc
  const data: ShareData = {
    t: track.title,
    a: track.artist,
    src,
    ids,
    d: track.duration_ms > 0 ? Math.round(track.duration_ms / 1000) : undefined,
    c: validCover(track.cover_url) ? track.cover_url : undefined,
    sl: scPath(scUrl),
    play: pickPlay(ids, twins?.sc_full ?? false),
  }
  return data
}

export function shareLink(track: Track, twins: ShareTwins | null | undefined, lang: string): string | null {
  const data = shareData(track, twins)
  return data ? shareUrl(data, lang) : null
}

/** Можно ли делиться треком (кнопка в меню): локальным файлом — нет. */
export const canShare = (track: Track) => shareData(track) !== null
