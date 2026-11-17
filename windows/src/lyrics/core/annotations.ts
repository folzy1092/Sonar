// Аннотации Genius к строкам текста (решение владельца 2026-11-16, уточнено 2026-11-17): одна
// аннотация показывается один раз — на первой найденной строке своего фрагмента, а не на каждой
// строке (иначе 8 строк подряд с одним и тем же пояснением). Сопоставление — по похожести строк: регистр,
// знаки, скобки бэк-вокала и лишние пробелы не важны. Чистые функции — покрыты тестами.

export interface Annotation {
  lines: string[]
  body: string
  reviewed: boolean
}

/** Строка для сравнения: нижний регистр, без скобок с бэк-вокалом, только буквы и цифры. */
export function key(s: string): string {
  return s
    .toLowerCase()
    .replace(/\([^)]*\)|\[[^\]]*\]/g, ' ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
}

/** Похожесть строк 0…1 по общим словам (Дайс), чтобы «леса (Леса)» и «леса» совпали. */
export function likeness(a: string, b: string): number {
  const wa = key(a).split(' ').filter(Boolean)
  const wb = key(b).split(' ').filter(Boolean)
  if (!wa.length || !wb.length) return 0
  const rest = [...wb]
  let common = 0
  for (const w of wa) {
    const i = rest.indexOf(w)
    if (i >= 0) {
      common++
      rest.splice(i, 1)
    }
  }
  return (2 * common) / (wa.length + wb.length)
}

/** Номер строки текста → аннотация. Строки фрагмента по порядку ищут лучшую строку текста (≥ 0.7);
 *  аннотация встаёт на первую найденную. Строка уже занята другой — берётся следующая строка
 *  фрагмента (фрагмент — подряд идущие строки, поэтому поиск следующей начинается дальше). */
export function mapAnnotations(lines: string[], anns: Annotation[]): Map<number, Annotation> {
  const out = new Map<number, Annotation>()
  for (const a of anns) {
    let from = 0
    for (const frag of a.lines) {
      let best = -1
      let score = 0.7
      for (let i = from; i < lines.length; i++) {
        const s = likeness(frag, lines[i])
        if (s > score) {
          score = s
          best = i
          if (s === 1) break
        }
      }
      if (best >= 0) {
        if (!out.has(best)) {
          out.set(best, a)
          break
        }
        from = best + 1
      }
    }
  }
  return out
}
