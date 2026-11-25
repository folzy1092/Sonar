import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { actionFor, comboFrom, comboLabel, globalMap, hasCommandMod, HOTKEY_ACTIONS, isLocalAction, spaceAction, takesText, windowOnly, withCombo, withoutCombo } from './hotkeys-core'
import { DEFAULTS } from './settings.svelte'

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
  it('одно сочетание — одно действие: у других снимается', () => {
    const map = { toggle: 'Ctrl+KeyK', next: 'Ctrl+Alt+KeyN' }
    expect(withCombo(map, 'next', 'Ctrl+KeyK')).toEqual({ toggle: '', next: 'Ctrl+KeyK' })
    expect(withoutCombo(map, 'Ctrl+KeyK')).toEqual({ toggle: '', next: 'Ctrl+Alt+KeyN' })
    expect(map.toggle).toBe('Ctrl+KeyK')
  })
  it('пустое сочетание ничего не снимает', () => {
    const map = { toggle: '', next: 'Ctrl+Alt+KeyN' }
    expect(withoutCombo(map, '')).toEqual(map)
    expect(withCombo(map, 'next', '')).toEqual({ toggle: '', next: '' })
  })
  it('«Вернуть по умолчанию» не ставит команде сочетание быстрого окна', () => {
    const quick = 'Ctrl+Alt+KeyS'
    const map = withoutCombo(DEFAULTS['hotkeys.map'], quick)
    expect(map.window).toBe('')
    expect(Object.values(map)).not.toContain(quick)
    expect(map.toggle).toBe(DEFAULTS['hotkeys.map'].toggle)
    expect(DEFAULTS['hotkeys.map'].window).toBe(quick)
  })

  it('голая клавиша — только для действий внутри окна', () => {
    expect(comboFrom(press('Slash', '/'), true)).toBe('Slash')
    expect(comboFrom(press('Slash', '/'))).toBeNull()
    expect(comboLabel('Slash')).toEqual(['/'])
    expect(comboLabel('Ctrl+Comma')).toEqual(['Ctrl', ','])
  })

  it('при наборе текста срабатывают только сочетания с Ctrl, Alt или Win', () => {
    expect(hasCommandMod('Ctrl+KeyL')).toBe(true)
    expect(hasCommandMod('Shift+Alt+KeyL')).toBe(true)
    expect(hasCommandMod('Slash')).toBe(false)
    expect(hasCommandMod('Shift+KeyL')).toBe(false)
  })

  it('по всей системе — по области; действия внутри окна туда не попадают', () => {
    const map = { toggle: 'Ctrl+Alt+Space', search: 'Slash', lyrics: 'Ctrl+KeyL', next: '' }
    expect(globalMap(map, 'app', true)).toEqual({})
    expect(globalMap(map, 'top', false)).toEqual({})
    expect(globalMap(map, 'top', true)).toEqual({ toggle: 'Ctrl+Alt+Space' })
    expect(globalMap(map, 'global', false)).toEqual({ toggle: 'Ctrl+Alt+Space' })
    expect(map.search).toBe('Slash')
  })

  it('одна клавиша (пробел) — любой команде, но только внутри окна: по всей системе не ставится', () => {
    expect(comboFrom(press('Space', ' '), true)).toBe('Space')
    expect(windowOnly('Space')).toBe(true)
    expect(windowOnly('Shift+Space')).toBe(true)
    expect(windowOnly('Ctrl+Alt+Space')).toBe(false)
    expect(windowOnly('')).toBe(false)
    const map = { toggle: 'Space', next: 'Ctrl+Alt+ArrowRight' }
    expect(globalMap(map, 'global', false)).toEqual({ next: 'Ctrl+Alt+ArrowRight' })
    expect(actionFor(map, 'Space')).toBe('toggle')
  })

  it('нажатие внутри окна находит действие, кроме «только по всей системе»', () => {
    const map = { toggle: 'Ctrl+Alt+Space', window: 'Ctrl+Alt+KeyS', search: 'Slash' }
    expect(actionFor(map, 'Slash')).toBe('search')
    expect(actionFor(map, 'Ctrl+Alt+Space')).toBe('toggle')
    expect(actionFor(map, 'Ctrl+Alt+KeyS')).toBeNull()
    expect(actionFor(map, 'Ctrl+KeyZ')).toBeNull()
    expect(actionFor(map, null)).toBeNull()
  })

  it('у каждого действия есть сочетание по умолчанию, у системных — с Ctrl+Alt', () => {
    const defaults = DEFAULTS['hotkeys.map']
    for (const a of HOTKEY_ACTIONS) {
      expect(defaults).toHaveProperty(a.id)
      const combo = defaults[a.id]
      // голый Ctrl+O / Ctrl+T по всей системе отнял бы «Открыть» и «Новую вкладку» у других программ
      if (combo && !isLocalAction(a.id)) expect(combo.startsWith('Ctrl+Alt+')).toBe(true)
    }
    const combos = Object.values(defaults).filter(Boolean)
    expect(new Set(combos).size).toBe(combos.length)
    expect(combos).not.toContain(DEFAULTS['hotkeys.quick'])
  })

  it('Rust знает каждое действие, которое может работать по всей системе', () => {
    const rs = readFileSync(new URL('../../src-tauri/src/hotkeys.rs', import.meta.url), 'utf8')
    const list = rs.match(/pub const ACTIONS: &\[&str\] = &\[([^\]]*)\]/)?.[1] ?? ''
    const rust = [...list.matchAll(/"([a-z_]+)"/g)].map((m) => m[1])
    expect(rust).toEqual(HOTKEY_ACTIONS.filter((a) => !isLocalAction(a.id)).map((a) => a.id))
  })
  it('пробел без назначения — «Играть / пауза»', () => {
    expect(spaceAction(DEFAULTS['hotkeys.map'])).toBe('toggle')
    expect(spaceAction({ toggle: 'Ctrl+Alt+Space', like: 'Space' })).toBe('like')
  })
  it('текст печатают в полях, а галочки и ползунки пробел не забирают', () => {
    expect(takesText({ tagName: 'INPUT', type: 'text' })).toBe(true)
    expect(takesText({ tagName: 'INPUT' })).toBe(true)
    expect(takesText({ tagName: 'INPUT', type: 'search' })).toBe(true)
    expect(takesText({ tagName: 'TEXTAREA' })).toBe(true)
    expect(takesText({ tagName: 'DIV', isContentEditable: true })).toBe(true)
    expect(takesText({ tagName: 'INPUT', type: 'checkbox' })).toBe(false)
    expect(takesText({ tagName: 'INPUT', type: 'range' })).toBe(false)
    expect(takesText({ tagName: 'BUTTON' })).toBe(false)
    expect(takesText(null)).toBe(false)
  })
})
