// «Схожесть» вкуса в профиле друга (docs/NEXT_FRIEND.md §2): процент, подпись, общие исполнители и
// общие треки. Та же формула — на iPhone (`ios/Sonar/Core/Account/TasteMatch.swift`) и на сервере
// (`GET /users/{username}/taste`, docs/API.md): менять — во всех трёх местах и в тестах.
//
// Процент = √(0.7 · исполнители + 0.3 · лайки) · 100, где
//  • исполнители — пересечение долей: Σ min(доля у меня, доля у друга) по общим исполнителям,
//    доля — прослушивания исполнителя / все прослушивания топа (0…1; одинаковые топы — 1);
//  • лайки — общие / max(меньший список, 20): у кого 2000 лайков, а у кого 50 — считаем по меньшему,
//    но пара общих лайков на пятерых не даёт 100 %.
// Корень растягивает середину: у похожих людей пересечение долей редко выше 0.5, а это уже 71 %.
// Нет лайков у кого-то из двоих — только исполнители; нет топа — только лайки; нет ничего — null.
// Исполнители и треки сравниваются по имени (без регистра, ё = е): у друга тот же артист может быть
// с другого сервиса (`sca:` против `yma:`), ref у них разный.

export interface TasteArtist {
  name: string
  ref: string | null
  avatar_url: string | null
  plays: number
}

export interface TasteTrack {
  ref: string
  title: string
  artist: string
}

export interface TasteSide<T extends TasteTrack = TasteTrack> {
  artists: readonly TasteArtist[]
  likes: readonly T[]
}

export type TasteLevel = 'very' | 'similar' | 'different'

export interface TasteMatch<T extends TasteTrack = TasteTrack> {
  /** 0…100. */
  percent: number
  level: TasteLevel
  /** Общие исполнители: сначала те, кого оба слушают больше всего. */
  artists: TasteArtist[]
  /** Общие лайки — мои экземпляры (их можно сыграть), в порядке моих Любимых. */
  tracks: T[]
}

export const TASTE_ARTIST_WEIGHT = 0.7
export const TASTE_LIKES_WEIGHT = 0.3
/** Меньше этого числа лайков знаменатель не опускается. */
export const TASTE_LIKES_FLOOR = 20
export const TASTE_VERY_FROM = 85
export const TASTE_SIMILAR_FROM = 60
/** Сколько общих треков отдаёт расчёт (на экране — 3–5). */
export const TASTE_TRACKS_SHOWN = 5

/** Ключ сравнения имён: без регистра, лишних пробелов, ё = е. */
export function tasteKey(name: string): string {
  return name.toLowerCase().replaceAll('ё', 'е').replace(/\s+/g, ' ').trim()
}

const trackKey = (t: TasteTrack) => `${tasteKey(t.artist)}\u0000${tasteKey(t.title)}`

export function tasteLevel(percent: number): TasteLevel {
  if (percent >= TASTE_VERY_FROM) return 'very'
  if (percent >= TASTE_SIMILAR_FROM) return 'similar'
  return 'different'
}

/** Доли прослушиваний по ключу имени (повторы одного имени складываются). */
function shares(artists: readonly TasteArtist[]): Map<string, number> {
  const total = artists.reduce((sum, a) => sum + Math.max(0, a.plays), 0)
  const out = new Map<string, number>()
  if (total <= 0) return out
  for (const a of artists) {
    const key = tasteKey(a.name)
    if (!key || a.plays <= 0) continue
    out.set(key, (out.get(key) ?? 0) + a.plays / total)
  }
  return out
}

/** Один исполнитель на имя: ref и аватар — мои, чего нет у меня — у друга. */
function artistsByKey(all: readonly TasteArtist[]): Map<string, TasteArtist> {
  const out = new Map<string, TasteArtist>()
  for (const artist of all) {
    const key = tasteKey(artist.name)
    const known = out.get(key)
    out.set(key, known ? { ...known, ref: known.ref ?? artist.ref, avatar_url: known.avatar_url ?? artist.avatar_url } : artist)
  }
  return out
}

function sharedArtists(mine: readonly TasteArtist[], theirs: readonly TasteArtist[]) {
  const a = shares(mine)
  const b = shares(theirs)
  const byKey = artistsByKey([...mine, ...theirs])
  const common = [...a.keys()]
    .filter((key) => b.has(key))
    .map((key) => ({ key, weight: Math.min(a.get(key) ?? 0, b.get(key) ?? 0) }))
    .sort((x, y) => y.weight - x.weight || x.key.localeCompare(y.key))
  return {
    overlap: common.reduce((sum, c) => sum + c.weight, 0),
    list: common.map((c) => byKey.get(c.key)).filter((x): x is TasteArtist => !!x),
    known: a.size > 0 && b.size > 0,
  }
}

function sharedLikes<T extends TasteTrack>(mine: readonly T[], theirs: readonly TasteTrack[]) {
  const refs = new Set(theirs.map((t) => t.ref))
  const keys = new Set(theirs.map(trackKey))
  const seen = new Set<string>()
  const common = mine.filter((t) => {
    const key = trackKey(t)
    if (seen.has(key) || !(refs.has(t.ref) || keys.has(key))) return false
    seen.add(key)
    return true
  })
  const smaller = Math.min(new Set(mine.map(trackKey)).size, new Set(theirs.map(trackKey)).size)
  return {
    overlap: smaller ? Math.min(1, common.length / Math.max(smaller, TASTE_LIKES_FLOOR)) : 0,
    list: common,
    known: mine.length > 0 && theirs.length > 0,
  }
}

/** Схожесть меня и друга; не с чем сравнивать (ни топа, ни лайков у кого-то) — null. */
export function tasteMatch<T extends TasteTrack>(me: TasteSide<T>, friend: TasteSide): TasteMatch<T> | null {
  const artists = sharedArtists(me.artists, friend.artists)
  const likes = sharedLikes(me.likes, friend.likes)
  let raw: number
  if (artists.known && likes.known) raw = TASTE_ARTIST_WEIGHT * artists.overlap + TASTE_LIKES_WEIGHT * likes.overlap
  else if (artists.known) raw = artists.overlap
  else if (likes.known) raw = likes.overlap
  else return null
  const percent = Math.round(Math.sqrt(Math.min(1, Math.max(0, raw))) * 100)
  return {
    percent,
    level: tasteLevel(percent),
    artists: artists.list,
    tracks: likes.list.slice(0, TASTE_TRACKS_SHOWN),
  }
}

/** Сколько исполнителей и лайков берёт демо-друг. */
const DEMO_STEP = 3

/**
 * Демо-друг для предпросмотра «Друг» (`ProfilePage`), пока друзей нет (они — с сервером): часть моих
 * исполнителей с другим порядком прослушиваний, свой исполнитель, которого у меня нет, и каждый третий
 * мой лайк. Детерминированно — процент не прыгает от открытия к открытию.
 */
export function demoFriendTaste(me: TasteSide): TasteSide {
  const artists = me.artists
    .filter((_, i) => i % DEMO_STEP !== DEMO_STEP - 1)
    .map((a, i, all) => ({ ...a, plays: all[all.length - 1 - i]?.plays ?? a.plays }))
  return {
    artists: [...artists, { name: '\u0000demo', ref: null, avatar_url: null, plays: me.artists[0]?.plays ?? 1 }],
    likes: me.likes.filter((_, i) => i % DEMO_STEP === 0),
  }
}
