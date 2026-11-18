// Значки сервисов для SourceIcon. Файлы в assets/services — байтовые копии brand/icon/ (их не правим).
// Яндекс Музыка — прежняя разметка из SourceIcon (официальный значок 2023, Wikimedia Commons): файл
// бренда другой (рамка 48, #FCBE2D, другой контур) и поменял бы вид.
import type { ServiceId } from './services'
import scSvg from '../assets/services/sc.svg?raw'
import scMonoSvg from '../assets/services/sc-mono.svg?raw'
import ytSvg from '../assets/services/yt.svg?raw'
import ytMonoSvg from '../assets/services/yt-mono.svg?raw'
import vkSvg from '../assets/services/vk.svg?raw'
import vkMonoSvg from '../assets/services/vk-mono.svg?raw'
import spSvg from '../assets/services/sp.svg?raw'
import spMonoSvg from '../assets/services/sp-mono.svg?raw'
import amSvg from '../assets/services/am.svg?raw'
import amMonoSvg from '../assets/services/am-mono.svg?raw'

export interface ServiceIcon {
  /** Цветной знак на обложке (у Яндекса — звезда в тёмном круге). */
  badge: string
  /** Цветной знак без круга (переключатель поиска, карточки настроек). */
  plain: string
  /** Одним цветом — currentColor. */
  mono: string
  /** Размер знака на плитке «Лайки» в Медиатеке. */
  likeArtSize: number
  /** Размер знака в шапке карточки Настройки → Сервисы. */
  cardSize: number
}

/** Корневой <svg>: без width/height (размер задаёт обёртка) и скрыт от скринридера (подпись — у обёртки). */
function prepare(svg: string): string {
  return svg.trim().replace(/^<svg\b[^>]*>/, (root) => root.replace(/\s(?:width|height)="[^"]*"/g, '').replace(/>$/, ' aria-hidden="true">'))
}

// Звезда центрируется по своей «массе» (центр тяжести 12.5, 9.7), а не по рамке — иначе она
// смотрится сдвинутой вверх-вправо; без круга — крупнее.
const YM_STAR =
  'M21.79,8.39l-.09-.43-3.63-.63,2.11-2.85-.25-.27-3.1,1.49.39-3.95-.32-.18-1.89,3.19L12.91,0h-.37l.5,4.6L7.71.33l-.45.13,4.11,5.16L3.24,2.91l-.37.41,7.26,4.13L.11,8.29l-.11.62,10.41,1.13L1.73,17.22l.37.5,10.33-5.62-2.05,9.9h.63l3.96-9.31,2.41,7.29.43-.33-.99-7.41,3.76,4.27.25-.39-2.88-5.29,4.02,1.49.04-.45-3.6-2.66,3.4-.82Z'
const YM_PLAIN_TRANSFORM = 'translate(1.25 3.65) scale(0.86)'
const ymStar = (fill: string, transform: string) => `<path fill="${fill}" transform="${transform}" d="${YM_STAR}" />`
const ymSvg = (body: string) => `<svg viewBox="0 0 24 24" aria-hidden="true">${body}</svg>`

const LIKE_ART_SIZE = 54
const CARD_SIZE = 24

export const ICONS: Record<ServiceId, ServiceIcon | null> = {
  sc: { badge: prepare(scSvg), plain: prepare(scSvg), mono: prepare(scMonoSvg), likeArtSize: 56, cardSize: CARD_SIZE },
  ym: {
    badge: ymSvg(`<circle cx="12" cy="12" r="12" fill="#1c1c1e" />${ymStar('#ffbc0d', 'translate(2.5 4.62) scale(0.76)')}`),
    plain: ymSvg(ymStar('#ffbc0d', YM_PLAIN_TRANSFORM)),
    mono: ymSvg(ymStar('currentColor', YM_PLAIN_TRANSFORM)),
    likeArtSize: 52,
    cardSize: 26,
  },
  yt: { badge: prepare(ytSvg), plain: prepare(ytSvg), mono: prepare(ytMonoSvg), likeArtSize: LIKE_ART_SIZE, cardSize: CARD_SIZE },
  vk: { badge: prepare(vkSvg), plain: prepare(vkSvg), mono: prepare(vkMonoSvg), likeArtSize: LIKE_ART_SIZE, cardSize: CARD_SIZE },
  sp: { badge: prepare(spSvg), plain: prepare(spSvg), mono: prepare(spMonoSvg), likeArtSize: LIKE_ART_SIZE, cardSize: CARD_SIZE },
  local: null,
}

/** Apple Music — не сервис Sonar (слушать оттуда нельзя), только источник импорта по ссылке:
 *  значок для экрана импорта и карточки ссылки. */
export const APPLE_MUSIC_ICON: Pick<ServiceIcon, 'badge' | 'plain' | 'mono'> = {
  badge: prepare(amSvg),
  plain: prepare(amSvg),
  mono: prepare(amMonoSvg),
}

const escapeRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

/** Делает id внутри svg уникальными (маска `m` у YouTube Music и т. п., когда значков на странице несколько). */
export function uniquifyIds(svg: string, suffix: string): string {
  const ids = [...svg.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1])
  return [...new Set(ids)].reduce((out, id) => {
    const re = escapeRe(id)
    const next = `${id}-${suffix}`
    return out
      .replace(new RegExp(`(\\s)id="${re}"`, 'g'), `$1id="${next}"`)
      .replace(new RegExp(`url\\(#${re}\\)`, 'g'), `url(#${next})`)
      .replace(new RegExp(`href="#${re}"`, 'g'), `href="#${next}"`)
  }, svg)
}
