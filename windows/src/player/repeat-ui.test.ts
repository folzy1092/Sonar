import { describe, expect, it, vi } from 'vitest'

let lang = 'ru'
vi.mock('../lib/settings.svelte', () => ({ settings: { get: () => lang } }))

const { repeatIcon, repeatLabel, shuffleLabel } = await import('./repeat-ui')
const { togglePop } = await import('../lib/toggle-pop')

describe('кнопки повтора и перемешивания', () => {
  it('у трёх состояний повтора — свой значок и подпись', () => {
    lang = 'ru'
    expect(['off', 'all', 'one'].map((r) => repeatIcon(r as never))).toEqual(['repeatOff', 'repeat', 'repeatOnce'])
    expect(repeatLabel('off')).toBe('Повтор: выкл')
    expect(repeatLabel('all')).toBe('Повтор: всё')
    expect(repeatLabel('one')).toBe('Повтор: один трек')
    expect(shuffleLabel(true)).toBe('Перемешивание: вкл')
  })

  it('подписи переведены', () => {
    lang = 'en'
    expect(repeatLabel('one')).toBe('Repeat: one track')
    expect(shuffleLabel(false)).toBe('Shuffle: off')
    lang = 'uk'
    expect(repeatLabel('off')).toBe('Повтор: вимк.')
    lang = 'ru'
  })
})

describe('togglePop', () => {
  function fakeNode() {
    const classes = new Set<string>()
    const listeners = new Map<string, () => void>()
    return {
      classes,
      listeners,
      node: {
        classList: { add: (c: string) => classes.add(c), remove: (c: string) => classes.delete(c) },
        addEventListener: (e: string, f: () => void) => listeners.set(e, f),
        removeEventListener: (e: string) => listeners.delete(e),
        offsetWidth: 0,
      } as unknown as HTMLElement,
    }
  }

  it('играет только при смене состояния, не при первом показе', () => {
    const { node, classes, listeners } = fakeNode()
    const action = togglePop(node, 'repeat:true')
    expect(classes.has('toggle-pop')).toBe(false)
    action.update('repeat:true')
    expect(classes.has('toggle-pop')).toBe(false)
    action.update('repeatOnce:true')
    expect(classes.has('toggle-pop')).toBe(true)
    listeners.get('animationend')?.()
    expect(classes.has('toggle-pop')).toBe(false)
    action.destroy()
    expect(listeners.size).toBe(0)
  })
})
