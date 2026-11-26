import { describe, expect, test } from 'vitest'
import { compareVersions, latestEntry, megabytes, parseUpdateManifest, windowsVersionFromTag, type ChangelogEntry } from './releases'

const entry = (version: string, platform: 'windows' | 'ios'): ChangelogEntry => ({
  version,
  platform,
  date: '2026-11-18',
  title: version,
  changes: [],
})

describe('windowsVersionFromTag', () => {
  test('берёт версию из тега релиза Windows', () => {
    expect(windowsVersionFromTag('windows-v0.1.23')).toBe('0.1.23')
  })
  test('не путает с релизами iOS и мусором', () => {
    expect(windowsVersionFromTag('ios-build-295')).toBeNull()
    expect(windowsVersionFromTag('windows-v0.1')).toBeNull()
    expect(windowsVersionFromTag(42)).toBeNull()
  })
})

describe('compareVersions', () => {
  test('сравнивает по числам, а не по строке', () => {
    expect(compareVersions('0.1.10', '0.1.9')).toBeGreaterThan(0)
    expect(compareVersions('0.2.0', '0.10.0')).toBeLessThan(0)
    expect(compareVersions('1.0.0', '1.0.0')).toBe(0)
  })
})

describe('latestEntry', () => {
  test('выбирает самую новую версию нужной платформы', () => {
    const list = [entry('0.1.0', 'windows'), entry('0.1.10', 'windows'), entry('0.1.2', 'windows'), entry('0.9.0', 'ios')]
    expect(latestEntry('windows', list)?.version).toBe('0.1.10')
    expect(latestEntry('ios', list)?.version).toBe('0.9.0')
  })
  test('пустой список → null', () => {
    expect(latestEntry('ios', [])).toBeNull()
  })
  test('в настоящем changelog есть запись для Windows', () => {
    expect(latestEntry('windows')).not.toBeNull()
  })
})

describe('megabytes', () => {
  test('одна цифра после запятой', () => {
    expect(megabytes(12 * 1024 * 1024 + 400 * 1024)).toBe('12.4')
    expect(megabytes(0)).toBe('0.0')
  })
})

describe('parseUpdateManifest', () => {
  test('версия из ответа сервера (формат tauri-plugin-updater)', () => {
    expect(parseUpdateManifest({ version: '0.3.12', notes: 'x', platforms: {} })).toBe('0.3.12')
  })
  test('сборки нет, мусор или чужая версия → null', () => {
    expect(parseUpdateManifest(null)).toBeNull()
    expect(parseUpdateManifest({ error: { code: 'not_found' } })).toBeNull()
    expect(parseUpdateManifest({ version: 12 })).toBeNull()
    expect(parseUpdateManifest({ version: 'v1; drop' })).toBeNull()
    expect(parseUpdateManifest({ version: '1.2' })).toBeNull()
  })
})
