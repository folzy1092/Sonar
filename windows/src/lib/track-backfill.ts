// Дозаполнение карточек треков (docs/NOW_ACCURACY_PROMPT.md §2): у треков из Dotify нет обложки и длительности.
// Чистые правила — какой трек добивать, что брать из свежей карточки, в каком порядке спрашивать.
// Правила менять в обоих местах: здесь и на iPhone `ios/Sonar/Core/Library/TrackBackfill.swift`
// (и слияние в Rust `src-tauri/src/store/backfill.rs` `merge_missing`, префиксы — `services/backfill.rs`).

/** Сколько ref за один запрос к сервису. */
export const BATCH_SIZE = 20
/** Пауза между пачками, мс. */
export const BATCH_PAUSE_MS = 1500
/** Каким сервисам умеем дозаполнять — тем же, что играют трек. */
export const BACKFILL_PREFIXES = ['sc:', 'ym:'] as const

interface Card {
  ref: string
  cover_url?: string | null
  duration_ms?: number | null
}

export function canBackfill(ref: string): boolean {
  return BACKFILL_PREFIXES.some((p) => ref.startsWith(p) && ref.length > p.length)
}

/** Нет обложки (пусто или null) или длительность ≤ 0. */
export function needsBackfill(t: Card): boolean {
  return !t.cover_url || !((t.duration_ms ?? 0) > 0)
}

/** Старая карточка + только недостающее из свежей: обложка — если своей нет, длительность — если своя ≤ 0.
 *  Добавить нечего — тот же объект (по ссылке), иначе новый. */
export function mergeMissing<T extends Card>(old: T, fresh: Card): T {
  const cover = !old.cover_url && fresh.cover_url ? fresh.cover_url : null
  const duration = !((old.duration_ms ?? 0) > 0) && (fresh.duration_ms ?? 0) > 0 ? fresh.duration_ms! : null
  if (cover === null && duration === null) return old
  return { ...old, ...(cover !== null && { cover_url: cover }), ...(duration !== null && { duration_ms: duration }) }
}

/** Кого спрашивать: текущий трек первым, дальше список по порядку, без повторов; только `sc:` / `ym:`,
 *  только недозаполненные и не из `skip` (сервис уже ничего не вернул). */
export function planQueue(
  tracks: readonly Card[],
  opts: { current?: Card | null; skip?: ReadonlySet<string> } = {},
): string[] {
  const skip = opts.skip ?? new Set<string>()
  const seen = new Set<string>()
  const out: string[] = []
  for (const t of opts.current ? [opts.current, ...tracks] : tracks) {
    if (seen.has(t.ref)) continue
    seen.add(t.ref)
    if (canBackfill(t.ref) && needsBackfill(t) && !skip.has(t.ref)) out.push(t.ref)
  }
  return out
}

/** Пачки по `BATCH_SIZE`. */
export function batches(refs: readonly string[], size = BATCH_SIZE): string[][] {
  const out: string[][] = []
  for (let i = 0; i < refs.length; i += size) out.push(refs.slice(i, i + size))
  return out
}

/** Что запомнить до перезапуска и больше не спрашивать: всё спрошенное, кроме `failed` (сеть, ключи — спросим
 *  снова). Сюда попадают и ref, по которым сервис ничего не вернул, и те, что вернулись без обложки или
 *  длительности, — иначе каждый заход в «Любимые» спрашивал бы их по новой. */
export function settledRefs(asked: readonly string[], failed: readonly string[]): string[] {
  const bad = new Set(failed)
  return asked.filter((r) => !bad.has(r))
}
