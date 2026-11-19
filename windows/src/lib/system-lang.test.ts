import { describe, expect, it } from 'vitest'
import { systemLang } from './system-lang'

describe('systemLang', () => {
  it('берёт первый язык системы, который есть в Sonar', () => {
    expect(systemLang(['de-AT', 'en-US'])).toBe('de')
    expect(systemLang(['fr-FR', 'pl-PL', 'en'])).toBe('pl')
    expect(systemLang(['es_MX'])).toBe('es')
    expect(systemLang(['uk-UA'])).toBe('uk')
    expect(systemLang(['en-GB'])).toBe('en')
  })
  it('нет знакомого — русский', () => {
    expect(systemLang([])).toBe('ru')
    expect(systemLang(['fr-FR', 'ja'])).toBe('ru')
  })
})
