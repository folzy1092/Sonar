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

  it('включённые горячие клавиши по всей системе становятся областью «Везде»', () => {
    expect(migrateSettings({ 'hotkeys.enabled': true })['hotkeys.scope']).toBe('global')
    expect(migrateSettings({ 'hotkeys.enabled': false })['hotkeys.scope']).toBe('app')
  })

  it('уже выбранную область старый переключатель не перетирает', () => {
    const stored = { 'hotkeys.enabled': true, 'hotkeys.scope': 'top' }
    expect(migrateSettings(stored)['hotkeys.scope']).toBe('top')
    expect(migrateSettings({})).toEqual({})
  })
})
