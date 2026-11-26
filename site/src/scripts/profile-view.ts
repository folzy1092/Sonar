// Разделы публичного профиля (`/@username`) под шапкой: сейчас играет, статистика, витрина, частые
// исполнители, Любимые, плейлисты. Пустой раздел не рисуется вовсе — никаких рядов нулей. Всё из сервера
// кладётся через textContent и https-картинки (`safeImage` в lib/profile.ts), разметку из данных не собираем.
import { useT, type Lang } from '../i18n'
import {
  formatDuration,
  hasContent,
  listenParts,
  type ProfileStats,
  type PublicPlaylist,
  type PublicProfile,
  type PublicTrack,
  type ShowcaseItem,
  type TopArtist,
} from '../lib/profile'

type T = ReturnType<typeof useT>
const STREAK_MIN = 2
const EQ_BARS = 4
const COLLAGE = 4

function el<K extends keyof HTMLElementTagNameMap>(tag: K, cls: string, text?: string): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag)
  node.className = cls
  if (text !== undefined) node.textContent = text
  return node
}

/** Обложка или заглушка с первой буквой; битая картинка сама уходит — остаётся заглушка. */
function cover(url: string | null, label: string, cls = 'pf-cover'): HTMLElement {
  const box = el('div', cls)
  box.append(el('span', 'pf-cover__ph', (label.trim()[0] ?? '♪').toUpperCase()))
  if (!url) return box
  const img = el('img', 'pf-cover__img')
  img.alt = ''
  img.loading = 'lazy'
  img.decoding = 'async'
  img.referrerPolicy = 'no-referrer'
  img.addEventListener('error', () => img.remove(), { once: true })
  img.addEventListener('load', () => img.classList.add('is-loaded'), { once: true })
  img.src = url
  box.append(img)
  return box
}

function section(title: string, meta?: string): HTMLElement {
  const sec = el('section', 'pf-sec')
  const head = el('header', 'pf-sec__head')
  head.append(el('h2', 'pf-sec__title', title))
  if (meta) head.append(el('span', 'pf-sec__meta', meta))
  sec.append(head)
  return sec
}

function nowPlaying(t: T, track: PublicTrack): HTMLElement {
  const card = el('section', 'pf-sec pf-now')
  const eq = el('span', 'pf-eq')
  eq.setAttribute('aria-hidden', 'true')
  for (let i = 0; i < EQ_BARS; i++) eq.append(el('span', 'pf-eq__bar'))
  const info = el('div', 'pf-now__info')
  const label = el('p', 'pf-now__label')
  label.append(eq, document.createTextNode(t.t('Сейчас слушает')))
  info.append(label, el('p', 'pf-now__title', track.title))
  if (track.artist) info.append(el('p', 'pf-now__artist', track.artist))
  card.append(cover(track.coverUrl, track.title, 'pf-cover pf-cover--lg'), info)
  if (track.durationMs) card.append(el('span', 'pf-now__time', formatDuration(track.durationMs)))
  return card
}

function tile(value: string, label: string): HTMLElement {
  const box = el('div', 'pf-tile')
  box.append(el('span', 'pf-tile__value', value), el('span', 'pf-tile__label', label))
  return box
}

function stats(t: T, nf: Intl.NumberFormat, s: ProfileStats): HTMLElement {
  const sec = section(t.t('Статистика'))
  const grid = el('div', 'pf-tiles')
  const listen = listenParts(s.totalMs)
  // Нули не рисуем: старые прослушивания без длины не дают «1 минуту», серия в один день — не серия.
  const time: [number, string] =
    listen.unit === 'h'
      ? [listen.n, t.tn(listen.n, 'час музыки|часа музыки|часов музыки')]
      : [listen.n, t.tn(listen.n, 'минута музыки|минуты музыки|минут музыки')]
  const tiles: [number, string][] = [
    [s.plays, t.tn(s.plays, 'прослушивание|прослушивания|прослушиваний')],
    [s.totalMs > 0 ? time[0] : 0, time[1]],
    [s.tracks, t.tn(s.tracks, 'трек|трека|треков')],
    [s.artists, t.tn(s.artists, 'исполнитель|исполнителя|исполнителей')],
    [s.streakDays >= STREAK_MIN ? s.streakDays : 0, t.tn(s.streakDays, 'день подряд|дня подряд|дней подряд')],
  ]
  tiles
    .filter(([n]) => n > 0)
    .forEach(([n, label], j) => {
      const box = tile(nf.format(n), label)
      box.style.setProperty('--j', String(j))
      grid.append(box)
    })
  sec.append(grid)
  return sec
}

function topArtists(t: T, artists: readonly TopArtist[]): HTMLElement {
  const sec = section(t.t('Чаще всего слушает'))
  const ol = el('ol', 'pf-artists')
  const max = Math.max(1, ...artists.map((a) => a.plays))
  artists.forEach((a, i) => {
    const li = el('li', 'pf-artist')
    li.style.setProperty('--j', String(i))
    li.style.setProperty('--share', String(a.plays / max))
    li.append(el('span', 'pf-artist__rank', String(i + 1)), el('span', 'pf-artist__name', a.name))
    if (a.plays) li.append(el('span', 'pf-artist__plays', t.tn(a.plays, '{n} раз|{n} раза|{n} раз')))
    li.append(el('span', 'pf-artist__bar'))
    ol.append(li)
  })
  sec.append(ol)
  return sec
}

function trackRow(track: PublicTrack, i: number): HTMLElement {
  const li = el('li', 'pf-track')
  li.style.setProperty('--j', String(i))
  const text = el('div', 'pf-track__text')
  text.append(el('span', 'pf-track__title', track.title))
  if (track.artist) text.append(el('span', 'pf-track__artist', track.artist))
  li.append(cover(track.coverUrl, track.title), text)
  if (track.durationMs) li.append(el('span', 'pf-track__time', formatDuration(track.durationMs)))
  return li
}

function likes(t: T, likes: NonNullable<PublicProfile['likes']>): HTMLElement {
  const sec = section(t.t('Любимые'), t.tn(likes.count, '{n} трек|{n} трека|{n} треков'))
  if (likes.tracks.length) {
    const ul = el('ul', 'pf-tracks')
    likes.tracks.forEach((track, i) => ul.append(trackRow(track, i)))
    sec.append(ul)
  }
  return sec
}

function collage(p: PublicPlaylist): HTMLElement {
  if (p.covers.length < COLLAGE) return cover(p.covers[0] ?? null, p.name, 'pf-cover pf-cover--sq')
  const box = el('div', 'pf-collage')
  for (const url of p.covers.slice(0, COLLAGE)) box.append(cover(url, p.name, 'pf-cover pf-cover--cell'))
  return box
}

function playlists(t: T, lists: readonly PublicPlaylist[], total: number): HTMLElement {
  const sec = section(t.t('Плейлисты'), t.tn(total, '{n} плейлист|{n} плейлиста|{n} плейлистов'))
  const grid = el('ul', 'pf-cards')
  lists.forEach((p, i) => {
    const li = el('li', 'pf-card')
    li.style.setProperty('--j', String(i))
    const meta = [t.tn(p.trackCount, '{n} трек|{n} трека|{n} треков')]
    if (p.durationMs) meta.push(formatDuration(p.durationMs))
    li.append(collage(p), el('span', 'pf-card__title', p.name || t.t('Плейлист')), el('span', 'pf-card__meta', meta.join(' · ')))
    grid.append(li)
  })
  sec.append(grid)
  return sec
}

function showcase(t: T, items: readonly ShowcaseItem[]): HTMLElement {
  const sec = section(t.t('Витрина'))
  const grid = el('ul', 'pf-cards')
  items.forEach((s, i) => {
    const li = el('li', 'pf-card')
    li.style.setProperty('--j', String(i))
    li.append(cover(s.coverUrl, s.title, 'pf-cover pf-cover--sq'), el('span', 'pf-card__title', s.title))
    if (s.subtitle) li.append(el('span', 'pf-card__meta', s.subtitle))
    grid.append(li)
  })
  sec.append(grid)
  return sec
}

function note(cls: string, text: string): HTMLElement {
  return el('p', `pf-sec pf-note ${cls}`, text)
}

/** Собрать разделы профиля в `host` (старое содержимое заменяется). */
export function renderProfileSections(host: HTMLElement, lang: Lang, p: PublicProfile): void {
  const t = useT(lang)
  const nf = new Intl.NumberFormat(lang)
  const blocks: HTMLElement[] = []
  if (p.nowPlaying) blocks.push(nowPlaying(t, p.nowPlaying))
  if (p.stats) blocks.push(stats(t, nf, p.stats))
  if (p.showcase.length) blocks.push(showcase(t, p.showcase))
  const pair: HTMLElement[] = []
  if (p.likes) pair.push(likes(t, p.likes))
  if (p.topArtists.length) pair.push(topArtists(t, p.topArtists))
  if (pair.length) {
    const row = el('div', `pf-pair${pair.length === 2 ? ' pf-pair--two' : ''}`)
    row.append(...pair)
    blocks.push(row)
  }
  if (p.playlists) blocks.push(playlists(t, p.playlists, p.playlistCount))
  if (!hasContent(p) && !p.private.length) {
    blocks.push(note('pf-note--empty', t.t('Тут пока тихо: прослушиваний, лайков и плейлистов ещё нет.')))
  }
  if (p.private.length) blocks.push(note('pf-note--private', t.t('Часть профиля скрыта настройками приватности.')))
  blocks.forEach((b, i) => b.style.setProperty('--i', String(i)))
  host.replaceChildren(...blocks)
  host.hidden = blocks.length === 0
}
