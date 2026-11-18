// FAQ (SITE.md §5): разметка ответов и поиск по вопросам. Ответы — абзацы с ссылками `[текст](адрес)`;
// адрес с «/» — страница сайта (получит префикс языка), остальное — внешняя ссылка.

export type Inline = { kind: 'text'; text: string } | { kind: 'link'; text: string; href: string; external: boolean }

const LINK_RE = /\[([^\]]+)\]\(([^)\s]+)\)/g

/** Разбирает абзац на текст и ссылки. Чужую разметку не понимает — всё прочее остаётся текстом. */
export function parseInline(src: string): Inline[] {
  const out: Inline[] = []
  let last = 0
  for (const m of src.matchAll(LINK_RE)) {
    const at = m.index ?? 0
    if (at > last) out.push({ kind: 'text', text: src.slice(last, at) })
    const href = m[2]
    out.push({ kind: 'link', text: m[1], href, external: !href.startsWith('/') && !href.startsWith('#') })
    last = at + m[0].length
  }
  if (last < src.length) out.push({ kind: 'text', text: src.slice(last) })
  return out
}

/** Текст абзаца без разметки ссылок — для поиска. */
export function plainText(src: string): string {
  return src.replace(LINK_RE, '$1')
}

/** Нижний регистр, «ё» → «е», без знаков препинания и лишних пробелов. */
export function normalize(s: string): string {
  return s
    .toLowerCase()
    .replace(/ё/g, 'е')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
}

/** Подходит ли текст под запрос: каждое слово запроса встречается в тексте. Пустой запрос — подходит всё. */
export function matches(haystack: string, query: string): boolean {
  const words = normalize(query).split(' ').filter(Boolean)
  if (words.length === 0) return true
  const text = normalize(haystack)
  return words.every((w) => text.includes(w))
}
