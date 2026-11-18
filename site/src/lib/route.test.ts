import { describe, expect, test } from 'vitest'
import { parseMissingRoute, restorePath } from './route'

describe('parseMissingRoute', () => {
  test('recognises a profile path and normalises the name', () => {
    expect(parseMissingRoute('/@Folzy')).toEqual({ kind: 'profile', username: 'folzy' })
    expect(parseMissingRoute('/@folzy_92/')).toEqual({ kind: 'profile', username: 'folzy_92' })
  })

  test('decodes an encoded @', () => {
    expect(parseMissingRoute('/%40folzy')).toEqual({ kind: 'missing' })
    expect(parseMissingRoute('/@fo%6Czy')).toEqual({ kind: 'profile', username: 'folzy' })
  })

  test('treats invalid names and other paths as a plain 404', () => {
    expect(parseMissingRoute('/@ab')).toEqual({ kind: 'missing' })
    expect(parseMissingRoute('/@имя')).toEqual({ kind: 'missing' })
    expect(parseMissingRoute('/@folzy/likes')).toEqual({ kind: 'missing' })
    expect(parseMissingRoute('/@%E0%A4%A')).toEqual({ kind: 'missing' })
    expect(parseMissingRoute('/nope')).toEqual({ kind: 'missing' })
  })
})

describe('restorePath', () => {
  test('accepts only a same-language site path', () => {
    expect(restorePath('/en/@folzy', 'en')).toBe('/en/@folzy')
    expect(restorePath('/uk/x?y=1#z', 'uk')).toBe('/uk/x?y=1#z')
  })

  test('rejects missing, foreign or odd paths', () => {
    expect(restorePath(null, 'en')).toBeNull()
    expect(restorePath('/uk/@folzy', 'en')).toBeNull()
    expect(restorePath('//evil.example/en/', 'en')).toBeNull()
    expect(restorePath('https://evil.example/en/', 'en')).toBeNull()
    expect(restorePath('/en/\\evil', 'en')).toBeNull()
  })
})
