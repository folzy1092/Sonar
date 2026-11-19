// Язык при первом запуске: первый из языков системы, который есть в Sonar, иначе русский.
// Пока владелец сам не выбрал язык в «Система → Общее → Язык», он и остаётся по умолчанию.
export type Lang = 'ru' | 'en' | 'uk' | 'es' | 'de' | 'pl'

const KNOWN: readonly Lang[] = ['ru', 'en', 'uk', 'es', 'de', 'pl']

/** `['de-AT', 'en-US']` → `'de'`; ничего знакомого — `'ru'`. */
export function systemLang(preferred: readonly string[]): Lang {
  for (const tag of preferred) {
    const base = tag.toLowerCase().split(/[-_]/)[0]
    const hit = KNOWN.find((l) => l === base)
    if (hit) return hit
  }
  return 'ru'
}

/** Языки системы из WebView (в тестах и вне браузера — пусто). */
export function preferredLanguages(): readonly string[] {
  if (typeof navigator === 'undefined') return []
  return navigator.languages?.length ? navigator.languages : navigator.language ? [navigator.language] : []
}
