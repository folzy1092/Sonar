// Серая подсказка-дописывание в строке поиска: набрал «Onda» — серым «andar». Чистая часть (тесты —
// autocomplete.test.ts): сбор кандидатов из того, что уже есть у пользователя, выбор подсказки,
// раскладка и решение по клавише. Без Svelte и сети. Порт на iPhone — ios/Sonar/Core/Search/Autocomplete.swift.
import { cyrToEn, enToRu, enToUk } from './quick-core'

/** Подсказку показываем от стольких набранных символов. */
export const MIN_TYPED = 2
/** Кандидат длиннее — пропускаем: такой хвост всё равно не влезет в поле. */
export const MAX_CANDIDATE = 60

/** Трек в том виде, в каком он нужен подсказке (Track из api.ts подходит как есть). */
export interface CandidateTrack {
  title: string
  artist: string
  artists?: { name: string }[]
}

/** Запись истории поиска (SearchEntry из search-history.svelte.ts подходит как есть). */
export interface CandidateHistory {
  kind: string
  query: string
  title?: string | null
}

export interface CandidateSources {
  /** Любимые — каждый трек со своими артистами. */
  liked: readonly CandidateTrack[]
  /** История поиска, новые сверху. */
  history: readonly CandidateHistory[]
  /** Недавно игравшие, новые сверху. */
  recent: readonly CandidateTrack[]
}

function artistNames(t: CandidateTrack): string[] {
  const names = t.artists?.map((a) => a.name).filter(Boolean) ?? []
  return names.length ? names : [t.artist]
}

/** Артисты Любимых: у кого больше лайкнутых треков — выше; при равенстве — кто раньше в списке. */
export function likedArtists(liked: readonly CandidateTrack[]): string[] {
  const counts = new Map<string, { name: string; n: number; first: number }>()
  liked.forEach((t, i) => {
    for (const name of artistNames(t)) {
      const key = name.trim().toLowerCase()
      if (!key) continue
      const was = counts.get(key)
      counts.set(key, was ? { ...was, n: was.n + 1 } : { name: name.trim(), n: 1, first: i })
    }
  })
  return [...counts.values()].sort((a, b) => b.n - a.n || a.first - b.first).map((c) => c.name)
}

function historyText(e: CandidateHistory): string {
  return (e.kind === 'query' ? e.query : (e.title ?? '')).trim()
}

/** Один список кандидатов по приоритету: Любимые → история → недавнее. Без дублей (регистр не важен),
 *  без пустых и слишком длинных. */
export function buildCandidates(src: CandidateSources): string[] {
  const all = [...likedArtists(src.liked), ...src.history.map(historyText), ...src.recent.flatMap((t) => [...artistNames(t), t.title])]
  const seen = new Set<string>()
  const out: string[] = []
  for (const raw of all) {
    const text = raw.trim()
    const key = text.toLowerCase()
    if (!text || text.length > MAX_CANDIDATE || seen.has(key)) continue
    seen.add(key)
    out.push(text)
  }
  return out
}

export interface Suggestion {
  /** Кандидат целиком, в регистре оригинала — им заменяется текст при принятии. */
  full: string
  /** Что дописать серым после набранного. При другой раскладке — пусто (показываем `full`). */
  tail: string
  /** Набрано в другой раскладке: «щтвф» → «Onda Andar»; при принятии заменяется весь текст. */
  relayout: boolean
}

function firstStartingWith(candidates: readonly string[], typed: string): string | undefined {
  const q = typed.toLowerCase()
  return candidates.find((c) => c.length > typed.length && c.toLowerCase().startsWith(q))
}

/** Подсказка к набранному: только по началу всей строки (по второму слову серый хвост соврал бы). */
export function suggest(candidates: readonly string[], typed: string): Suggestion | null {
  if (typed.trim().length < MIN_TYPED) return null
  const direct = firstStartingWith(candidates, typed)
  if (direct) return { full: direct, tail: direct.slice(typed.length), relayout: false }
  for (const alt of [cyrToEn(typed), enToRu(typed), enToUk(typed)]) {
    if (alt === typed.toLowerCase()) continue
    const hit = firstStartingWith(candidates, alt)
    if (hit) return { full: hit, tail: '', relayout: true }
  }
  return null
}

/** Где курсор в поле и идёт ли ввод через IME. */
export interface FieldState {
  value: string
  selectionStart: number | null
  selectionEnd: number | null
  composing: boolean
}

/** Подсказку можно показывать: курсор в конце, выделения нет, не идёт ввод через IME. */
export function canSuggest(f: FieldState): boolean {
  if (f.composing) return false
  if (f.selectionStart !== f.selectionEnd) return false
  return f.selectionStart === f.value.length
}

export type KeyDecision =
  /** Принять подсказку: текст = `value`, курсор в конец, сразу искать. */
  | { kind: 'accept'; value: string }
  /** Искать то, что реально набрано. */
  | { kind: 'search'; value: string }
  /** Убрать подсказку (первый Esc). */
  | { kind: 'dismiss' }
  /** Клавиша не наша — пусть работает как обычно (Tab без подсказки — фокус дальше). */
  | { kind: 'pass' }

/** Что делать по клавише в поле поиска. `suggestion` — то, что сейчас показано (или null). */
export function decideKey(key: string, f: FieldState, suggestion: Suggestion | null, mods: { shift?: boolean; ctrl?: boolean; alt?: boolean } = {}): KeyDecision {
  if (mods.ctrl || mods.alt) return { kind: 'pass' }
  if (key === 'Enter') return { kind: 'search', value: f.value }
  if (!suggestion || !canSuggest(f)) return { kind: 'pass' }
  if (key === 'Tab' && !mods.shift) return { kind: 'accept', value: suggestion.full }
  if (key === 'ArrowRight' && !mods.shift) return { kind: 'accept', value: suggestion.full }
  if (key === 'Escape') return { kind: 'dismiss' }
  return { kind: 'pass' }
}
