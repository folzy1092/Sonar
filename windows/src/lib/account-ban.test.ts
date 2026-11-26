import { describe, expect, it } from 'vitest'
import { parseBan, sessionEnded, untilText } from './account-ban'

describe('parseBan', () => {
  it('разбирает срок и причину', () => {
    expect(parseBan('banned:{"until":1795000000000,"reason":"спам"}')).toEqual({ until: 1795000000000, reason: 'спам' })
    expect(parseBan(new Error('banned:{"until":null,"reason":null}'))).toEqual({ until: null, reason: null })
  })
  it('пустая причина — null, длинная обрезается', () => {
    expect(parseBan('banned:{"until":null,"reason":"   "}')?.reason).toBeNull()
    expect(parseBan(`banned:{"until":null,"reason":"${'я'.repeat(300)}"}`)?.reason).toHaveLength(200)
  })
  it('мусор после префикса — всё равно блокировка, но без подробностей', () => {
    expect(parseBan('banned:не json')).toEqual({ until: null, reason: null })
    expect(parseBan('banned:{"until":"завтра"}')).toEqual({ until: null, reason: null })
  })
  it('не блокировка', () => {
    for (const e of ['signed_out', 'Неверный логин или пароль', '', null, undefined, 42]) expect(parseBan(e)).toBeNull()
  })
})

describe('sessionEnded', () => {
  it('выход и блокировка — конец сессии, остальное нет', () => {
    expect(sessionEnded('signed_out')).toBe(true)
    expect(sessionEnded('banned:{"until":null,"reason":null}')).toBe(true)
    expect(sessionEnded(new Error('signed_out'))).toBe(true)
    expect(sessionEnded('Нет связи с сервером Sonar')).toBe(false)
  })
})

describe('untilText', () => {
  it('навсегда — null, срок — дата и время', () => {
    expect(untilText({ until: null, reason: null })).toBeNull()
    const text = untilText({ until: Date.UTC(2026, 10, 27, 12, 5), reason: null }, 'en-GB')
    expect(text).toMatch(/2026/)
    expect(text).toMatch(/\d{2}:\d{2}/)
  })
})
