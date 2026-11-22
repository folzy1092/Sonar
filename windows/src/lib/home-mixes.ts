// Подборки «Для тебя» на Главной — чистая часть без сети и Svelte: отбор треков из пулов похожего,
// дубли, не больше N треков одного исполнителя, «и ещё N» на карточке, мозаика обложек, кэш на день.
// Сеть и состояние — `mixes.svelte.ts`, страница — `pages/MixPage.svelte`.
import type { ArtistRef, Track } from './api'

/** Какие подборки бывают. `daypart` — «Твой вечер/утро/день/ночь», `like` — «Похоже на трек». */
export type MixId = 'daypart' | 'recent' | 'new' | 'fresh' | 'like'

export const MIX_IDS: readonly MixId[] = ['daypart', 'recent', 'new', 'fresh', 'like']

export function isMixId(v: unknown): v is MixId {
  return typeof v === 'string' && (MIX_IDS as readonly string[]).includes(v)
}

/** Честный признак «малоизвестного»: прослушивания на SoundCloud меньше этого. У Яндекса счётчика нет —
 *  такие треки в «Свежих артистах» не участвуют, а не угадываются. */
export const FRESH_MAX_PLAYS = 50_000
/** …и не меньше этого: ниже — хвост выдачи SoundCloud (случайный трек жанра на десяток прослушиваний), а не
 *  «малоизвестный исполнитель рядом со вкусом». */
export const FRESH_MIN_PLAYS = 1_000
/** Сколько треков одного исполнителя пускаем в подборку. */
export const MAX_PER_ARTIST = 2
/** Длина подборки по умолчанию. */
export const MIX_LIMIT = 40
/** Сколько исполнителей с аватарками на карточке, остальные — «и ещё N». */
export const PREVIEW_ARTISTS = 3
/** Прибавка к весу трека, если его исполнитель — сосед по графу кого-то из любимых. */
const RELATED_BOOST = 2
/** Прибавка за каждую ещё одну затравку, которая советует того же исполнителя. */
const ARTIST_SUPPORT_BOOST = 1.5
/** Исполнителей, которых советует лишь одна затравка и которые не соседи любимых, берём только
 *  добором — если «надёжных» треков меньше этого. Один похожий трек от одной песни — случайность
 *  (так в «Новое» попадали CUPSIZE и Юпи), два независимых совета — уже вкус. */
const MIN_BEFORE_FILL = 12

/** Имя для сравнения: без регистра, лишних пробелов и «ё». */
export function normName(name: string): string {
  return name.trim().toLowerCase().replace(/ё/g, 'е').replace(/\s+/g, ' ')
}

/** Исполнители трека: из `artists`, а если их нет — строка `artist` целиком. */
export function trackArtists(t: Track): ArtistRef[] {
  if (t.artists?.length) return t.artists
  return t.artist ? [{ ref: '', name: t.artist, avatar_url: null }] : []
}

/** Главный исполнитель трека (нормализованный) — по нему ограничиваем «не больше N». */
function mainArtist(t: Track): string {
  return normName(trackArtists(t)[0]?.name ?? t.artist ?? '')
}

/** Без повторов: тот же ref или та же пара «название — исполнитель» (один трек на двух сервисах). */
export function dedupe(tracks: readonly Track[]): Track[] {
  const refs = new Set<string>()
  const names = new Set<string>()
  return tracks.filter((t) => {
    const name = `${normName(t.title)}\u0000${mainArtist(t)}`
    if (refs.has(t.ref) || names.has(name)) return false
    refs.add(t.ref)
    names.add(name)
    return true
  })
}

/** Не больше `max` треков одного исполнителя, порядок сохраняется. */
export function limitPerArtist(tracks: readonly Track[], max = MAX_PER_ARTIST): Track[] {
  const seen = new Map<string, number>()
  return tracks.filter((t) => {
    const a = mainArtist(t)
    const n = seen.get(a) ?? 0
    if (n >= max) return false
    seen.set(a, n + 1)
    return true
  })
}

/** У трека есть честный признак малоизвестного: счётчик SoundCloud известен и мал. */
export function isFresh(t: Track, maxPlays = FRESH_MAX_PLAYS, minPlays = FRESH_MIN_PLAYS): boolean {
  return typeof t.plays === 'number' && Number.isFinite(t.plays) && t.plays >= minPlays && t.plays < maxPlays
}

/** Почему трек в подборке: какие затравки (их исполнители) советуют его исполнителя и чей он сосед по карте. */
export interface MixReason {
  seeds: string[]
  near: string | null
}

export interface Picked {
  track: Track
  why: MixReason
}

export interface PickOptions {
  /** Исполнители, которых пользователь уже знает (прослушивания, Любимые) — их треки отсекаются. */
  known?: Iterable<string>
  /** Refs, которых в подборке быть не должно (сам трек-затравка, недавнее). */
  exclude?: Iterable<string>
  /** Любимые исполнители — у них спрашиваем соседей через `related`. */
  taste?: readonly string[]
  /** Соседи исполнителя по графу; по умолчанию соседей нет. Треки соседей поднимаются выше. */
  related?: (artistName: string) => string[]
  /** Дополнительный отбор (например, `isFresh`). */
  filter?: (t: Track) => boolean
  maxPerArtist?: number
  limit?: number
  /** Подпись затравки каждого пула (исполнитель трека-затравки) — для «почему этот трек». */
  seedLabels?: readonly string[]
  /** Добирать ли одиночными советами, если надёжных мало. `false` — только надёжные, пусть их и мало. */
  fill?: boolean
}

const noRelated = (): string[] => []

/** Вес кандидата: в скольких пулах встретился (чем больше затравок его советуют — тем ближе ко вкусу) и
 *  насколько высоко стоял в каждом (похожее приходит от самого похожего к менее). */
function scorePools(pools: readonly (readonly Track[])[]): Map<string, { track: Track; score: number; first: number }> {
  const scored = new Map<string, { track: Track; score: number; first: number }>()
  let order = 0
  for (const pool of pools) {
    pool.forEach((t, i) => {
      const add = 1 + 1 / (i + 1)
      const prev = scored.get(t.ref)
      if (prev) scored.set(t.ref, { ...prev, score: prev.score + add })
      else scored.set(t.ref, { track: t, score: add, first: order++ })
    })
  }
  return scored
}

/** Соседи любимых исполнителей (нормализованные, без самих любимых) → чей сосед (первый из любимых). */
function neighbours(taste: readonly string[], related: (name: string) => string[], known: Set<string>): Map<string, string> {
  const out = new Map<string, string>()
  for (const name of taste) {
    for (const n of related(name) ?? []) {
      const key = normName(n)
      if (key && !known.has(key) && !out.has(key)) out.set(key, name)
    }
  }
  return out
}

/**
 * Подборка из пулов похожего: без знакомых исполнителей и исключённых refs, без дублей, не больше
 * `maxPerArtist` на исполнителя; выше — те, кого советуют чаще, и соседи любимых по `related`.
 */
export function pickFromPools(pools: readonly (readonly Track[])[], opts: PickOptions = {}): Track[] {
  return pickWithReasons(pools, opts).map((p) => p.track)
}

/** То же, что `pickFromPools`, но у каждого трека — почему он здесь (`MixReason`). */
export function pickWithReasons(pools: readonly (readonly Track[])[], opts: PickOptions = {}): Picked[] {
  const known = new Set([...(opts.known ?? [])].map(normName).filter(Boolean))
  const exclude = new Set(opts.exclude ?? [])
  const near = neighbours(opts.taste ?? [], opts.related ?? noRelated, known)
  // сколько разных затравок советуют исполнителя (а не трек — у Яндекса и SC треки разные)
  const artistPools = new Map<string, Set<number>>()
  pools.forEach((pool, i) => {
    for (const t of pool) {
      for (const a of trackArtists(t)) {
        const key = normName(a.name)
        if (!key) continue
        const set = artistPools.get(key) ?? new Set<number>()
        set.add(i)
        artistPools.set(key, set)
      }
    }
  })
  const support = (t: Track) => trackArtists(t).reduce((m, a) => Math.max(m, artistPools.get(normName(a.name))?.size ?? 0), 0)
  const nearOf = (t: Track) => trackArtists(t).map((a) => near.get(normName(a.name))).find((x) => !!x) ?? null
  const labels = opts.seedLabels ?? []
  const why = (t: Track): MixReason => {
    const idx = new Set<number>()
    for (const a of trackArtists(t)) for (const i of artistPools.get(normName(a.name)) ?? []) idx.add(i)
    const seeds = [...new Set([...idx].sort((a, b) => a - b).map((i) => labels[i]).filter((x): x is string => !!x))]
    return { seeds, near: nearOf(t) }
  }
  const candidates = [...scorePools(pools).values()]
    .filter(({ track }) => !exclude.has(track.ref) && track.available !== false)
    .filter(({ track }) => !trackArtists(track).some((a) => known.has(normName(a.name))))
    .filter(({ track }) => (opts.filter ? opts.filter(track) : true))
    .map((c) => {
      const s = support(c.track)
      const nearBoost = nearOf(c.track) ? RELATED_BOOST : 0
      return { ...c, strong: s >= 2 || nearBoost > 0, score: c.score + nearBoost + Math.max(0, s - 1) * ARTIST_SUPPORT_BOOST }
    })
    .sort((a, b) => b.score - a.score || a.first - b.first)
  const limit = opts.limit ?? MIX_LIMIT
  const max = opts.maxPerArtist ?? MAX_PER_ARTIST
  const withWhy = (list: Track[]) => list.map((track) => ({ track, why: why(track) }))
  const strong = limitPerArtist(dedupe(candidates.filter((c) => c.strong).map((c) => c.track)), max)
  if (opts.fill === false || strong.length >= Math.min(limit, MIN_BEFORE_FILL)) return withWhy(strong.slice(0, limit))
  // надёжных мало — добираем случайными советами, но после надёжных
  const all = limitPerArtist(dedupe([...strong, ...candidates.filter((c) => !c.strong).map((c) => c.track)]), max)
  return withWhy(all.slice(0, Math.min(limit, Math.max(strong.length, MIN_BEFORE_FILL))))
}

/** Пул похожего для подборок: без перезаливов и почти не слушанного хвоста (`cleanSimilar` без добора). */
export function cleanPool(pool: readonly Track[]): Track[] {
  return cleanSimilar(pool, 0)
}

/** Разные исполнители подборки по частоте (кого больше — тот первым), с аватаркой — выше при равенстве. */
export function mixArtists(tracks: readonly Track[]): ArtistRef[] {
  const byName = new Map<string, { artist: ArtistRef; count: number; first: number }>()
  tracks.forEach((t, i) => {
    for (const a of trackArtists(t)) {
      const key = normName(a.name)
      if (!key) continue
      const prev = byName.get(key)
      if (!prev) byName.set(key, { artist: a, count: 1, first: i })
      else byName.set(key, { artist: prev.artist.avatar_url || !a.avatar_url ? prev.artist : a, count: prev.count + 1, first: prev.first })
    }
  })
  return [...byName.values()]
    .sort((a, b) => b.count - a.count || Number(!!b.artist.avatar_url) - Number(!!a.artist.avatar_url) || a.first - b.first)
    .map((x) => x.artist)
}

/** Для карточки: 2–3 исполнителя с аватарками и сколько ещё («и ещё N»). */
export function artistsPreview(tracks: readonly Track[], n = PREVIEW_ARTISTS): { shown: ArtistRef[]; more: number } {
  const all = mixArtists(tracks)
  const shown = all.slice(0, Math.max(0, n))
  return { shown, more: all.length - shown.length }
}

/** Чередует пулы по одному треку («похоже на» сразу нескольких исполнителей, а не первый целиком). */
export function interleave<T>(pools: readonly (readonly T[])[]): T[] {
  const out: T[] = []
  const longest = Math.max(0, ...pools.map((p) => p.length))
  for (let i = 0; i < longest; i++) for (const p of pools) if (i < p.length) out.push(p[i])
  return out
}

/** Затравки для «Похоже на»: последние треки разных исполнителей (у кого есть ref — его можно открыть). */
export function seedArtists(recent: readonly Track[], n = PREVIEW_ARTISTS): { artist: ArtistRef; track: Track }[] {
  const seen = new Set<string>()
  const out: { artist: ArtistRef; track: Track }[] = []
  for (const t of recent) {
    const a = trackArtists(t)[0]
    const key = a ? normName(a.name) : ''
    if (!a || !key || seen.has(key)) continue
    seen.add(key)
    out.push({ artist: a, track: t })
    if (out.length >= n) break
  }
  return out
}

/** Ряд «Похоже на» на Главной: пулы похожего по затравкам вперемешку, без дублей, без уже слышанного
 *  (`exclude`), не больше `MAX_PER_ARTIST` на исполнителя. Треки соседей затравок по карте исполнителей
 *  (`near`) — первыми, порядок внутри сохраняется. */
export function similarRow(
  pools: readonly (readonly Track[])[],
  exclude: Iterable<string> = [],
  limit = MIX_LIMIT,
  near: Iterable<string> = [],
): Track[] {
  const skip = new Set(exclude)
  const close = new Set([...near].map(normName).filter(Boolean))
  const list = limitPerArtist(dedupe(interleave(pools).filter((t) => !skip.has(t.ref) && t.available !== false)))
  const isNear = (t: Track) => trackArtists(t).some((a) => close.has(normName(a.name)))
  return [...list.filter(isNear), ...list.filter((t) => !isNear(t))].slice(0, limit)
}

/** Перезалив: то же название и длина в пределах этого — один трек, залитый разными аккаунтами. */
const REUPLOAD_DURATION_MS = 2000
/** Ниже этой доли от медианы прослушиваний подборки трек — случайный добор SoundCloud, а не похожее. */
const SIMILAR_MEDIAN_SHARE = 0.01
/** И ниже этого — тоже, даже если вся подборка нишевая (но не выше её медианы — см. `cleanSimilar`). */
const SIMILAR_MIN_PLAYS = 100
/** Меньше стольких после чистки — добираем лучшими из выкинутых. */
export const SIMILAR_MIN_KEEP = 15

function median(xs: readonly number[]): number {
  const s = [...xs].sort((a, b) => a - b)
  const m = s.length >> 1
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2
}

/** Без перезаливов: то же название (без регистра) и длина ±2 с — остаётся первый. Длина 0 — не знаем, не склеиваем. */
function dropReuploads(tracks: readonly Track[]): Track[] {
  const kept: Track[] = []
  for (const t of tracks) {
    const title = normName(t.title)
    const dup = t.duration_ms > 0 && kept.some((k) => k.duration_ms > 0 && normName(k.title) === title && Math.abs(k.duration_ms - t.duration_ms) <= REUPLOAD_DURATION_MS)
    if (!dup) kept.push(t)
  }
  return kept
}

/**
 * Чистка «Похоже на трек» (сырой `/tracks/{id}/related` SoundCloud): у нишевого трека хвост выдачи —
 * случайные треки того же жанра на десятки прослушиваний и перезаливы одного трека разными аккаунтами.
 * Склеивает перезаливы и выкидывает почти не слушанное на фоне подборки (порог — 1 % медианы, не меньше
 * 100, но не выше самой медианы: нишевая подборка целиком остаётся). Треки без счётчика (Яндекс) не
 * трогает. Осталось меньше `minKeep` — добирает лучшими из выкинутых; порядок сервиса сохраняется.
 */
export function cleanSimilar(tracks: readonly Track[], minKeep = SIMILAR_MIN_KEEP): Track[] {
  const list = dropReuploads(tracks)
  const counted = list.map((t) => t.plays).filter((p): p is number => typeof p === 'number' && Number.isFinite(p))
  if (!counted.length) return list
  const mid = median(counted)
  const floor = Math.min(mid, Math.max(SIMILAR_MIN_PLAYS, mid * SIMILAR_MEDIAN_SHARE))
  const low = (t: Track) => typeof t.plays === 'number' && t.plays < floor
  const kept = list.filter((t) => !low(t))
  if (kept.length >= minKeep) return kept
  const back = new Set(
    list
      .filter(low)
      .sort((a, b) => (b.plays ?? 0) - (a.plays ?? 0))
      .slice(0, minKeep - kept.length),
  )
  return list.filter((t) => !low(t) || back.has(t))
}

/** Выбор трека для «Похоже на трек»: без повторов, по запросу в названии или исполнителе. */
export function matchTracks(tracks: readonly Track[], query: string, limit = 40): Track[] {
  const q = normName(query)
  const list = dedupe(tracks)
  return (q ? list.filter((t) => normName(`${t.title} ${t.artist}`).includes(q)) : list).slice(0, limit)
}

/** Трек-затравка «Похоже на трек» (настройка `home.similar_seed`). */
export interface SeedTrack {
  ref: string
  title: string
  artist: string
  cover_url: string | null
}

/** Проверка значения из настроек: чужое или битое — `null`. */
export function parseSeed(v: unknown): SeedTrack | null {
  if (!v || typeof v !== 'object') return null
  const o = v as Record<string, unknown>
  if (typeof o.ref !== 'string' || !o.ref || typeof o.title !== 'string') return null
  return {
    ref: o.ref,
    title: o.title,
    artist: typeof o.artist === 'string' ? o.artist : '',
    cover_url: typeof o.cover_url === 'string' ? o.cover_url : null,
  }
}

export function toSeed(t: Pick<Track, 'ref' | 'title' | 'artist' | 'cover_url'>): SeedTrack {
  return { ref: t.ref, title: t.title, artist: t.artist, cover_url: t.cover_url ?? null }
}

/** Ключ дня по местному времени, `YYYY-MM-DD`: кэш подборок живёт до полуночи. */
export function dayKey(now = new Date()): string {
  const p = (n: number) => String(n).padStart(2, '0')
  return `${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())}`
}

/** Кэш тяжёлых подборок (сеть): на сегодня и для этой затравки «Похоже на трек». */
export interface MixCache {
  day: string
  seed: string | null
  new: Track[]
  fresh: Track[]
  like: Track[]
  /** Почему трек в «Новом» и «Свежих» (ref → причина). */
  why: Record<string, MixReason>
}

/** Разбор кэша из хранилища; чужой день или битые данные — `null`. */
export function readCache(raw: string | null, now = new Date()): MixCache | null {
  if (!raw) return null
  try {
    const o = JSON.parse(raw) as Partial<MixCache>
    if (o?.day !== dayKey(now)) return null
    const list = (v: unknown) => (Array.isArray(v) ? (v.filter((t) => t && typeof t.ref === 'string') as Track[]) : [])
    return { day: o.day, seed: typeof o.seed === 'string' ? o.seed : null, new: list(o.new), fresh: list(o.fresh), like: list(o.like), why: reasons(o.why) }
  } catch {
    return null
  }
}

function reasons(v: unknown): Record<string, MixReason> {
  const out: Record<string, MixReason> = {}
  if (!v || typeof v !== 'object') return out
  for (const [ref, r] of Object.entries(v as Record<string, unknown>)) {
    const o = r as Partial<MixReason> | null
    if (!o || typeof o !== 'object') continue
    const seeds = Array.isArray(o.seeds) ? o.seeds.filter((x): x is string => typeof x === 'string') : []
    out[ref] = { seeds, near: typeof o.near === 'string' ? o.near : null }
  }
  return out
}
