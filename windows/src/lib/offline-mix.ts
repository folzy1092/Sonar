// «Sonar Mix офлайн» (`docs/OFFLINE.md` §6.1, этап 4): микс только из того, что играет без сети.
// Скромно и честно: никаких похожих из сервисов — порядок по своим сигналам (лайк, прослушивания, давность,
// пропуски, теги последних прослушиваний) плюс немного случайности, чтобы микс не был одним и тем же списком.

/** Что Sonar знает о треке (`offline_mix_signals`, store/offline.rs). */
export interface MixSignalLike {
  ref: string
  plays: number
  /** Последнее прослушивание, мс; 0 — не слушали. */
  last_played: number
  skips: number
  tags: readonly string[]
}

export interface MixInput {
  liked: ReadonlySet<string>
  signals: readonly MixSignalLike[]
  /** Теги последних прослушиваний (с повторами — чем чаще, тем весомее). */
  recentTags: readonly string[]
  now: number
  /** Случайность — снаружи, чтобы тесты были повторяемыми. */
  rand: () => number
}

/** Меньше — микс не предлагаем: на пяти треках «умная» волна — враньё. */
export const MIX_MIN_POOL = 20
/** Сколько треков в одном миксе. */
export const MIX_LENGTH = 50

const WEIGHT = { liked: 1.5, plays: 0.5, recency: 0.8, justPlayed: 1, skips: 1.5, tags: 1.2, jitter: 1 }
const DAY_MS = 86_400_000
/** За сколько дней бонус давности падает вдвое. */
const RECENCY_HALF_LIFE_DAYS = 14
/** Только что игравшее в начало микса не ставим. */
const JUST_PLAYED_MS = 2 * 3_600_000

/** Доля тегов трека, которые звучали недавно (0…1). */
export function tagAffinity(tags: readonly string[], recent: ReadonlySet<string>): number {
  if (!tags.length || !recent.size) return 0
  return tags.filter((tag) => recent.has(tag)).length / tags.length
}

/** Очки трека без случайности: чем выше, тем раньше в миксе. */
export function mixScore(signal: MixSignalLike | undefined, liked: boolean, recent: ReadonlySet<string>, now: number): number {
  const likedBonus = liked ? WEIGHT.liked : 0
  if (!signal) return likedBonus
  const plays = Math.log1p(signal.plays) * WEIGHT.plays
  const age = signal.last_played > 0 ? now - signal.last_played : Infinity
  const recency = Number.isFinite(age) ? WEIGHT.recency * 0.5 ** (age / DAY_MS / RECENCY_HALF_LIFE_DAYS) : 0
  const justPlayed = age < JUST_PLAYED_MS ? WEIGHT.justPlayed : 0
  const skipRatio = signal.skips / (signal.plays + signal.skips || 1)
  const tags = tagAffinity(signal.tags, recent) * WEIGHT.tags
  return likedBonus + plays + recency - justPlayed - skipRatio * WEIGHT.skips + tags
}

/** Тот же исполнитель два раза подряд — следующий другой подтягивается вперёд (порядок остальных тот же). */
export function spreadArtists<T extends { artist: string }>(tracks: readonly T[]): T[] {
  const rest = [...tracks]
  const out: T[] = []
  while (rest.length) {
    const prev = out.at(-1)?.artist.toLowerCase()
    const i = rest.findIndex((x) => x.artist.toLowerCase() !== prev)
    out.push(rest.splice(i < 0 ? 0 : i, 1)[0])
  }
  return out
}

/** Микс из доступных треков: очки + случайность, сверху лучшие, исполнители вперемешку. */
export function rankOfflineMix<T extends { ref: string; artist: string }>(pool: readonly T[], input: MixInput): T[] {
  const byRef = new Map(input.signals.map((s) => [s.ref, s]))
  const recent = new Set(input.recentTags)
  const scored = pool.map((track) => ({
    track,
    score: mixScore(byRef.get(track.ref), input.liked.has(track.ref), recent, input.now) + input.rand() * WEIGHT.jitter,
  }))
  const top = [...scored].sort((a, b) => b.score - a.score).slice(0, MIX_LENGTH)
  return spreadArtists(top.map((x) => x.track))
}
