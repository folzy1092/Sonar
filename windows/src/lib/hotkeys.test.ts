import { describe, expect, it } from 'vitest'
import { comboFrom, comboLabel } from './hotkeys-core'

type Mods = Partial<Record<'ctrlKey' | 'altKey' | 'shiftKey' | 'metaKey', boolean>>
const press = (code: string, key: string, mods: Mods = {}) => ({ ctrlKey: false, altKey: false, shiftKey: false, metaKey: false, ...mods, code, key })

describe('горячие клавиши', () => {
  it('сочетание — модификаторы и код клавиши', () => {
    expect(comboFrom(press('KeyL', 'l', { ctrlKey: true, altKey: true }))).toBe('Ctrl+Alt+KeyL')
    expect(comboFrom(press('ArrowRight', 'ArrowRight', { shiftKey: true, metaKey: true }))).toBe('Shift+Win+ArrowRight')
  })
  it('без модификатора и одни модификаторы — не сочетание', () => {
    expect(comboFrom(press('KeyL', 'l'))).toBeNull()
    expect(comboFrom(press('ControlLeft', 'Control', { ctrlKey: true }))).toBeNull()
  })
  it('подпись — по-человечески', () => {
    expect(comboLabel('Ctrl+Alt+KeyL')).toEqual(['Ctrl', 'Alt', 'L'])
    expect(comboLabel('Ctrl+Alt+ArrowUp')).toEqual(['Ctrl', 'Alt', '↑'])
    expect(comboLabel('Alt+Digit1')).toEqual(['Alt', '1'])
  })
})
