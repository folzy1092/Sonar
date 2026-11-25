// Вкус по артистам: «Больше» · «Меньше» · «Никогда» (docs/TASTE_ROOMS_PROMPT.md §1, настройка `wave.artist_prefs`).
// Чистая часть без Svelte: ключи артистов — ровно как `wave.rs` `artist_keys` (Rust читает ту же настройку
// и по ней фильтрует и оценивает порцию Sonar Mix), уровень трека и правка словаря.
import type { Track } from './api'

export type ArtistLevel = 'more' | 'less' | 'never'
export interface ArtistPref {
  /** Имя как на экране (ключ — в нижнем регистре). */
  name: string
  level: ArtistLevel
}
export type ArtistPrefs = Record<string, ArtistPref>

export const LEVELS: readonly ArtistLevel[] = ['more', 'less', 'never']

/** Ключ артиста: нижний регистр без крайних пробелов. */
export const artistKey = (name: string) => name.trim().toLowerCase()

/** Все артисты трека, главный первый: имена из `artists`, а если списка нет — строка `artist` целиком
 *  (по запятым и & не режем) — зеркало `wave.rs` `artist_names`. */
export function trackKeys(t: Pick<Track, 'artist' | 'artists'>): string[] {
  const out: string[] = []
  for (const a of t.artists ?? []) {
    const k = artistKey(a.name)
    if (k && !out.includes(k)) out.push(k)
  }
  if (!out.length) out.push(artistKey(t.artist))
  return out
}

/** Главный артист трека для меню: имя и ключ. */
export function mainArtist(t: Pick<Track, 'artist' | 'artists'>): { key: string; name: string } {
  const a = (t.artists ?? []).find((x) => artistKey(x.name))
  const name = (a?.name ?? t.artist).trim()
  return { key: artistKey(name), name }
}

const isLevel = (v: unknown): v is ArtistLevel => v === 'more' || v === 'less' || v === 'never'

/** Уровень трека по всем соавторам: `never` любого — `never`, иначе `more` перебивает `less` (как Rust `pref_of`). */
export function levelFor(prefs: ArtistPrefs, t: Pick<Track, 'artist' | 'artists'>): ArtistLevel | null {
  let best: ArtistLevel | null = null
  for (const k of trackKeys(t)) {
    const l = prefs[k]?.level
    if (!isLevel(l)) continue
    if (l === 'never') return 'never'
    if (l === 'more') best = 'more'
    else if (!best) best = 'less'
  }
  return best
}

/** Уровень одного артиста по имени. */
export const levelOf = (prefs: ArtistPrefs, name: string): ArtistLevel | null => {
  const l = prefs[artistKey(name)]?.level
  return isLevel(l) ? l : null
}

/** Новый словарь с уровнем артиста; `null` — убрать запись. Пустое имя — без изменений. */
export function withLevel(prefs: ArtistPrefs, name: string, level: ArtistLevel | null): ArtistPrefs {
  const key = artistKey(name)
  if (!key) return prefs
  const next = { ...prefs }
  if (level) next[key] = { name: name.trim(), level }
  else delete next[key]
  return next
}

/** Записи для страницы «Вкус»: битые выкинуты, по имени, с поиском по подстроке. */
export function prefList(prefs: ArtistPrefs, query = ''): { key: string; name: string; level: ArtistLevel }[] {
  const q = query.trim().toLowerCase()
  return Object.entries(prefs ?? {})
    .filter(([, p]) => p && isLevel(p.level))
    .map(([key, p]) => ({ key, name: p.name?.trim() || key, level: p.level }))
    .filter((p) => !q || p.name.toLowerCase().includes(q))
    .sort((a, b) => a.name.localeCompare(b.name))
}
