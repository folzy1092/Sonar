import { describe, expect, it } from 'vitest'
import { betaAllowed, updateChannel } from './beta'

describe('бета только владельцу', () => {
  it('свой логин — можно, в любом регистре и с пробелами', () => {
    expect(betaAllowed('folzy')).toBe(true)
    expect(betaAllowed(' Folzy ')).toBe(true)
  })
  it('чужой, пустой и без входа — нельзя', () => {
    for (const login of ['mira', 'folzy2', 'xfolzy', '', null, undefined]) expect(betaAllowed(login)).toBe(false)
  })
  it('канал: бета — и включена, и свой логин; остальное — релиз', () => {
    expect(updateChannel('beta', 'folzy')).toBe('beta')
    expect(updateChannel('beta', 'mira')).toBe('release')       // включил «Бета» в старой версии — всё равно релиз
    expect(updateChannel('beta', null)).toBe('release')
    expect(updateChannel('stable', 'folzy')).toBe('release')
    expect(updateChannel(undefined, 'folzy')).toBe('release')
  })
})
