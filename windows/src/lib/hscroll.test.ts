import { describe, expect, it } from 'vitest'
import { arrowsFor, pageDelta } from './hscroll'

describe('arrowsFor', () => {
  it('ряд влез целиком — стрелок нет', () => {
    expect(arrowsFor({ scrollLeft: 0, clientWidth: 800, scrollWidth: 800 })).toEqual({ left: false, right: false })
    expect(arrowsFor({ scrollLeft: 0, clientWidth: 800, scrollWidth: 600 })).toEqual({ left: false, right: false })
  })

  it('лишние 1–2 px от дробной ширины — тоже не край', () => {
    expect(arrowsFor({ scrollLeft: 0, clientWidth: 800, scrollWidth: 801.5 })).toEqual({ left: false, right: false })
    expect(arrowsFor({ scrollLeft: 0, clientWidth: 800, scrollWidth: 802 })).toEqual({ left: false, right: false })
  })

  it('в начале — только вправо, в конце — только влево, посередине — обе', () => {
    const box = { clientWidth: 800, scrollWidth: 2000 }
    expect(arrowsFor({ ...box, scrollLeft: 0 })).toEqual({ left: false, right: true })
    expect(arrowsFor({ ...box, scrollLeft: 1199 })).toEqual({ left: true, right: false })
    expect(arrowsFor({ ...box, scrollLeft: 600 })).toEqual({ left: true, right: true })
  })

  it('почти у края (в пределах допуска) — край', () => {
    const box = { clientWidth: 800, scrollWidth: 2000 }
    expect(arrowsFor({ ...box, scrollLeft: 1.5 }).left).toBe(false)
    expect(arrowsFor({ ...box, scrollLeft: 1198.4 }).right).toBe(false)
  })

  it('прокрутка за пределами (резинка, отрицательная) не ломает ответ', () => {
    const box = { clientWidth: 800, scrollWidth: 2000 }
    expect(arrowsFor({ ...box, scrollLeft: -20 })).toEqual({ left: false, right: true })
    expect(arrowsFor({ ...box, scrollLeft: 1300 })).toEqual({ left: true, right: false })
  })

  it('свой допуск', () => {
    expect(arrowsFor({ scrollLeft: 0, clientWidth: 800, scrollWidth: 805 }, 10).right).toBe(false)
    expect(arrowsFor({ scrollLeft: 0, clientWidth: 800, scrollWidth: 805 }, 1).right).toBe(true)
  })
})

describe('pageDelta', () => {
  it('видимая ширина, округлённая до целых карточек', () => {
    // карточка 160 + зазор 18: в 800 px влезает 4 (4·178 − 18 = 694)
    expect(pageDelta(800, 160, 18)).toBe(4 * 178)
  })

  it('ровно влезающая последняя карточка считается', () => {
    expect(pageDelta(694, 160, 18)).toBe(4 * 178)
    expect(pageDelta(693, 160, 18)).toBe(4 * 178)
    expect(pageDelta(690, 160, 18)).toBe(3 * 178)
  })

  it('узкий ряд — хотя бы одна карточка', () => {
    expect(pageDelta(100, 160, 18)).toBe(178)
  })

  it('ширина карточки неизвестна — листаем на ширину ряда', () => {
    expect(pageDelta(800, 0, 0)).toBe(800)
    expect(pageDelta(0, 160, 18)).toBe(0)
  })
})
