import { describe, expect, it } from 'vitest'
import { pickStep, TITLE_STEPS } from './fit-title'

describe('pickStep — ступень шрифта названия', () => {
  it('влезает в полном размере — шрифт не меняется', () => {
    expect(pickStep(() => true)).toBe(1)
  })

  it('берёт первую ступень, на которой текст влез', () => {
    expect(pickStep((s) => s <= 0.86)).toBe(0.86)
  })

  it('не влезло нигде — самая мелкая ступень, дальше многоточие', () => {
    expect(pickStep(() => false)).toBe(TITLE_STEPS[TITLE_STEPS.length - 1])
  })

  it('пробует ступени по порядку и останавливается на первой подходящей', () => {
    const tried: number[] = []
    pickStep((s) => {
      tried.push(s)
      return s < 1
    })
    expect(tried).toEqual([1, 0.86])
  })
})
