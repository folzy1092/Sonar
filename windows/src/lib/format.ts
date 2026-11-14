// Подписи с числами по-русски: «217 треков, 6 часов 51 мин», «9.4K подписчиков».

/** Форма слова для числа: plural(5, ['трек', 'трека', 'треков']) → 'треков'. */
export function plural(n: number, forms: [string, string, string]): string {
  const a = Math.abs(n) % 100
  const b = a % 10
  if (a > 10 && a < 20) return forms[2]
  if (b > 1 && b < 5) return forms[1]
  if (b === 1) return forms[0]
  return forms[2]
}

export const tracksText = (n: number) => `${n} ${plural(n, ['трек', 'трека', 'треков'])}`

/** Длительность списка: «51 мин», «6 часов 51 мин». */
export function durationText(ms: number): string {
  const min = Math.round(ms / 60_000)
  const h = Math.floor(min / 60)
  const m = min % 60
  if (!h) return `${m} мин`
  return `${h} ${plural(h, ['час', 'часа', 'часов'])}${m ? ` ${m} мин` : ''}`
}

/** 9400 → «9.4K», 1600000 → «1.6M». */
export function compact(n: number): string {
  if (n < 1000) return String(n)
  if (n < 1_000_000) return `${+(n / 1000).toFixed(n < 10_000 ? 1 : 0)}K`
  return `${+(n / 1_000_000).toFixed(1)}M`
}
