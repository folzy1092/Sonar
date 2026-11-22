// Каждая строка интерфейса `t('…')` и `tn(n, ['…', '…', '…'])` из исходников есть в словарях en и uk
// (es / de / pl сверяются с en в i18n.test.ts). Без этого теста забытый перевод тихо показывал русский.
import { describe, expect, it, vi } from 'vitest'

vi.mock('./settings.svelte', () => ({ settings: { get: () => 'ru' } }))

const { dictionary } = await import('./i18n.svelte')

const sources = import.meta.glob(['../**/*.{ts,svelte}', '!../**/*.test.ts', '!../i18n/**'], {
  query: '?raw',
  import: 'default',
  eager: true,
}) as Record<string, string>

const unescape = (s: string) => s.replace(/\\(['"`\\])/g, '$1')
/** t('строка') / t("строка") / t(`строка без ${…}`) — первый аргумент-литерал. */
const T_CALL = /\bt\(\s*(['"`])((?:\\.|(?!\1).)*?)\1\s*[,)]/g
/** tn(n, ['форма', 'формы', 'форм']) — три формы в ключе через «|». */
const TN_CALL = /\btn\(\s*[^,()]+(?:\([^()]*\))?\s*,\s*\[\s*(['"])([^'"]*)\1\s*,\s*(['"])([^'"]*)\3\s*,\s*(['"])([^'"]*)\5\s*\]/g
const CYRILLIC = /[а-яё]/i

export function usedKeys(files: Record<string, string>): Map<string, string> {
  const keys = new Map<string, string>()
  for (const [file, src] of Object.entries(files)) {
    for (const m of src.matchAll(T_CALL)) {
      if (m[1] === '`' && m[2].includes('${')) continue
      const key = unescape(m[2])
      if (CYRILLIC.test(key)) keys.set(key, file)
    }
    for (const m of src.matchAll(TN_CALL)) keys.set(`${m[2]}|${m[4]}|${m[6]}`, file)
  }
  return keys
}

describe('покрытие переводов', () => {
  it('сканер находит t() и tn() в исходниках', () => {
    const keys = usedKeys({ 'a.ts': "t('Раз') t(\"Два\", { x }) t(`Три`) tn(n, ['трек', 'трека', 'треков']) t(`с ${x}`)" })
    expect([...keys.keys()]).toEqual(['Раз', 'Два', 'Три', 'трек|трека|треков'])
  })
  it('в исходниках сотни строк — сканер не сломался', () => {
    expect(usedKeys(sources).size).toBeGreaterThan(500)
  })
  for (const l of ['en', 'uk'] as const) {
    it(`каждая строка из кода переведена: ${l}`, () => {
      const dict = dictionary(l)
      const missing = [...usedKeys(sources)].filter(([k]) => !(k in dict)).map(([k, f]) => `${k}  ← ${f}`)
      expect(missing).toEqual([])
    })
  }
})
