// Быстрое окно (Ctrl+K) — чистая часть поиска (тесты в quick-core.test.ts): нормализация, раскладка
// (ghbdtn → привет) и нечёткое совпадение по началам слов («мв» → «Моя волна», «тайм сна» →
// «Таймер сна»). Без Svelte и API — только строки.

const EN = "`qwertyuiop[]asdfghjkl;'zxcvbnm,."
const RU = 'ёйцукенгшщзхъфывапролджэячсмитьбю'
const UK = "'йцукенгшщзхїфівапролджєячсмитьбю"

const toMap = (from: string, to: string) => new Map([...from].map((c, i) => [c, to[i]] as const))
const EN_RU = toMap(EN, RU)
const EN_UK = toMap(EN, UK)
// обратно: русские и украинские буквы → латиница той же клавиши (общие буквы совпадают)
const CYR_EN = new Map([...toMap(UK, EN), ...toMap(RU, EN)])

function convert(text: string, map: Map<string, string>): string {
  return [...text.toLowerCase()].map((c) => map.get(c) ?? c).join('')
}

/** Набрано в английской раскладке, а думал по-русски: `ghbdtn` → `привет`. */
export const enToRu = (text: string) => convert(text, EN_RU)
/** То же для украинской раскладки: `ghbdsn` → `привіт`. */
export const enToUk = (text: string) => convert(text, EN_UK)
/** Обратно: `руддщ` → `hello`. */
export const cyrToEn = (text: string) => convert(text, CYR_EN)

/** Нижний регистр, ё → е, пробелы схлопнуты. */
export function normalize(text: string): string {
  return text.toLowerCase().replace(/ё/g, 'е').replace(/\s+/g, ' ').trim()
}

/** Слова строки (буквы и цифры любого алфавита). */
export function words(text: string): string[] {
  return normalize(text).match(/[\p{L}\p{N}]+/gu) ?? []
}

/** Тот же запрос в других раскладках — без повторов и без самого запроса. */
export function altLayouts(query: string): string[] {
  const q = normalize(query)
  const out = [enToRu(q), enToUk(q), cyrToEn(q)].map(normalize)
  return [...new Set(out)].filter((v) => v && v !== q)
}

/** Ниже этого запрос ищется только по началам слов — по подстроке слишком шумно. */
const MIN_SUBSTRING = 3
/** Раскладка угадана, а не набрана — чуть ниже прямого совпадения. */
const LAYOUT_PENALTY = 1

type Split = { count: number; first: number; skipped: number }

/** Минимум кусков, на которые делится `token`, чтобы каждый был началом очередного слова
 *  (слова можно пропускать). `null` — не делится. Ещё — первое слово и сколько слов пропущено.
 *  Перебор с запоминанием по (позиция в запросе, слово) — длинные названия не тормозят. */
function chunks(token: string, ws: string[]): Split | null {
  const better = (a: Split, b: Split | null) => {
    if (!b) return true
    if (a.count !== b.count) return a.count < b.count
    if (a.skipped !== b.skipped) return a.skipped < b.skipped
    return a.first < b.first
  }
  const memo = new Map<number, Split | null>()

  // лучший раздел хвоста `token` с позиции `pos`, первый кусок — в слове не раньше `from`
  const rest = (pos: number, from: number): Split | null => {
    if (pos === token.length) return { count: 0, first: from, skipped: 0 }
    const key = pos * (ws.length + 1) + from
    if (memo.has(key)) return memo.get(key)!
    let best: Split | null = null
    for (let w = from; w < ws.length; w++) {
      const word = ws[w]
      let k = 0
      while (k < word.length && pos + k < token.length && word[k] === token[pos + k]) k++
      for (let len = k; len >= 1; len--) {
        const tail = rest(pos + len, w + 1)
        if (!tail) continue
        const cand = { count: tail.count + 1, first: w, skipped: tail.skipped + (tail.count ? tail.first - (w + 1) : 0) }
        if (better(cand, best)) best = cand
      }
    }
    memo.set(key, best)
    return best
  }
  return rest(0, 0)
}

/** Насколько `text` подходит под `query` (больше — лучше), `null` — не подходит. Каждое слово
 *  запроса должно найтись: целиком или по кускам — началами слов текста, а от 3 букв — хотя бы
 *  подстрокой (слабо). Выше: совпадение с первого слова, меньше кусков, текст начинается с запроса. */
export function fuzzyScore(query: string, text: string): number | null {
  const q = normalize(query)
  if (!q) return 0
  const t = normalize(text)
  const ws = words(t)
  const qs = words(q)
  if (!qs.length) return t.includes(q) ? 1 : null
  let score = 0
  for (const token of qs) {
    const m = chunks(token, ws)
    if (m) {
      score += 10 - 2 * (m.count - 1) - (m.first === 0 ? 0 : 1) - 0.5 * m.skipped
      if (ws.includes(token)) score += 2
    } else if (token.length >= MIN_SUBSTRING && t.includes(token)) {
      score += 2
    } else {
      return null
    }
  }
  if (t === q) score += 10
  else if (t.startsWith(q)) score += 5
  // при прочих равных — короче текст, точнее попадание
  return score - 0.1 * ws.length
}

/** Лучший счёт по нескольким строкам элемента (название, ключевые слова) и по раскладкам. */
export function bestScore(query: string, texts: readonly string[]): number | null {
  const variants = [{ q: query, penalty: 0 }, ...altLayouts(query).map((q) => ({ q, penalty: LAYOUT_PENALTY }))]
  let best: number | null = null
  for (const { q, penalty } of variants) {
    for (const text of texts) {
      const s = fuzzyScore(q, text)
      if (s !== null && (best === null || s - penalty > best)) best = s - penalty
    }
  }
  return best
}

/** Подходящие элементы — лучшие первыми (при равенстве — исходный порядок). Пустой запрос — все как есть. */
export function rank<T>(items: readonly T[], query: string, textsOf: (item: T) => readonly string[], limit = Infinity): T[] {
  if (!normalize(query)) return items.slice(0, limit)
  return items
    .map((item, i) => ({ item, i, s: bestScore(query, textsOf(item)) }))
    .filter((r): r is { item: T; i: number; s: number } => r.s !== null)
    .sort((a, b) => b.s - a.s || a.i - b.i)
    .slice(0, limit)
    .map((r) => r.item)
}

/** Следующая / предыдущая строка по кругу. */
export function step(index: number, delta: number, length: number): number {
  if (length <= 0) return -1
  return (((index + delta) % length) + length) % length
}

/** Tab — к первой строке следующей группы (Shift+Tab — предыдущей), по кругу. `starts` — индексы
 *  первых строк групп по порядку. */
export function jumpGroup(index: number, starts: readonly number[], back: boolean): number {
  if (!starts.length) return -1
  let g = 0
  for (let i = 0; i < starts.length; i++) if (starts[i] <= index) g = i
  // назад из середины группы — к её началу, как в обычных списках
  if (back && index > starts[g]) return starts[g]
  return starts[step(g, back ? -1 : 1, starts.length)]
}

/** Чередует списки: первый из каждого, потом второй… — сервисы вперемешку, а не один за другим. */
export function interleave<T>(lists: readonly (readonly T[])[]): T[] {
  const out: T[] = []
  const longest = Math.max(0, ...lists.map((l) => l.length))
  for (let i = 0; i < longest; i++) for (const l of lists) if (i < l.length) out.push(l[i])
  return out
}

/** Без повторов по `ref` — первый остаётся на своём месте. */
export function uniqueByRef<T extends { ref: string }>(list: readonly T[]): T[] {
  const seen = new Set<string>()
  return list.filter((x) => !seen.has(x.ref) && !!seen.add(x.ref))
}
