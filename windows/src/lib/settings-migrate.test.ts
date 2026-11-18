import { describe, expect, it } from 'vitest'
import { migrateSettings } from './settings-migrate'

describe('старые значения настроек', () => {
  it('сохранённое «Незнакомое» (wave.mode = new) читается как «Обычное»', () => {
    const stored = { 'wave.mode': 'new', 'ui.theme': 'dark' }
    const out = migrateSettings(stored)
    expect(out['wave.mode']).toBe('own')
    expect(out['ui.theme']).toBe('dark')
    expect(stored['wave.mode']).toBe('new')
  })

  it('новые настроения и чужие ключи не трогает', () => {
    for (const mode of ['own', 'night', 'sleep', 'popular', 'focus']) {
      expect(migrateSettings({ 'wave.mode': mode })['wave.mode']).toBe(mode)
    }
    const same = { other: 'new' }
    expect(migrateSettings(same)).toBe(same)
  })
})
