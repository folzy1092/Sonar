import { describe, expect, it } from 'vitest'
import { windowButtonsLook } from './window-buttons'

describe('windowButtonsLook', () => {
  it('keeps an explicit choice whatever the platform', () => {
    expect(windowButtonsLook('macos', 'Win32')).toBe('macos')
    expect(windowButtonsLook('windows', 'MacIntel')).toBe('windows')
  })

  it('follows the platform on auto', () => {
    expect(windowButtonsLook('auto', 'Win32')).toBe('windows')
    expect(windowButtonsLook('auto', 'MacIntel')).toBe('macos')
    expect(windowButtonsLook('auto', '')).toBe('windows')
  })
})
