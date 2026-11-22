import { describe, expect, it } from 'vitest'
import { demoFriendTaste, tasteKey, tasteLevel, tasteMatch, TASTE_TRACKS_SHOWN, type TasteArtist, type TasteTrack } from './taste-match'

const artist = (name: string, plays: number, ref: string | null = null): TasteArtist => ({ name, ref, avatar_url: null, plays })
const track = (ref: string, artistName = 'A', title = ref): TasteTrack => ({ ref, title, artist: artistName })

describe('tasteMatch', () => {
  it('одинаковые вкусы — 100 %, «очень похожие»', () => {
    const likes = Array.from({ length: 20 }, (_, i) => track(`sc:${i}`))
    const side = { artists: [artist('A', 10), artist('B', 5)], likes }
    const m = tasteMatch(side, side)
    expect(m?.percent).toBe(100)
    expect(m?.level).toBe('very')
  })

  it('ничего общего — 0 %, «разные»', () => {
    const m = tasteMatch(
      { artists: [artist('A', 10)], likes: [track('sc:1')] },
      { artists: [artist('B', 10)], likes: [track('sc:2', 'B')] },
    )
    expect(m).toMatchObject({ percent: 0, level: 'different', artists: [], tracks: [] })
  })

  it('исполнители весят по доле прослушиваний: √(Σ min долей)', () => {
    // у меня A — 3/4, B — 1/4; у друга A — 1/4, B — 3/4 → 1/4 + 1/4 = 0.5 → √0.5 ≈ 71
    const m = tasteMatch(
      { artists: [artist('A', 30), artist('B', 10)], likes: [] },
      { artists: [artist('A', 10), artist('B', 30)], likes: [] },
    )
    expect(m?.percent).toBe(71)
    expect(m?.level).toBe('similar')
  })

  it('лайки — 30 %: общие / max(меньший список, 20)', () => {
    const mine = Array.from({ length: 40 }, (_, i) => track(`sc:${i}`))
    // исполнители совпали полностью (0.7), лайки 20 / 20 (0.3) → 100
    const full = tasteMatch({ artists: [artist('A', 1)], likes: mine }, { artists: [artist('A', 1)], likes: mine.slice(0, 20) })
    expect(full?.percent).toBe(100)
    // у друга 2 лайка, оба общие: 2 / 20 = 0.1 → √(0.7 + 0.03) ≈ 85
    const few = tasteMatch({ artists: [artist('A', 1)], likes: mine }, { artists: [artist('A', 1)], likes: mine.slice(0, 2) })
    expect(few?.percent).toBe(85)
  })

  it('нет лайков — только исполнители; нет топа — только лайки; ничего — null', () => {
    expect(tasteMatch({ artists: [artist('A', 1)], likes: [] }, { artists: [artist('A', 1)], likes: [track('x')] })?.percent).toBe(100)
    expect(tasteMatch({ artists: [], likes: [track('x')] }, { artists: [artist('A', 1)], likes: [track('x')] })?.percent).toBe(
      Math.round(Math.sqrt(1 / 20) * 100),
    )
    expect(tasteMatch({ artists: [], likes: [] }, { artists: [artist('A', 1)], likes: [] })).toBeNull()
  })

  it('исполнитель с другого сервиса совпадает по имени, ref берётся мой, аватар — у кого есть', () => {
    const m = tasteMatch(
      { artists: [artist('Шипы ', 5, 'sca:1')], likes: [] },
      { artists: [{ ...artist('шипы', 5, 'yma:9'), avatar_url: 'https://img/a.jpg' }], likes: [] },
    )
    expect(m?.artists).toEqual([{ name: 'Шипы ', ref: 'sca:1', avatar_url: 'https://img/a.jpg', plays: 5 }])
  })

  it('общие исполнители — сначала те, кого оба слушают больше', () => {
    const m = tasteMatch(
      { artists: [artist('A', 1), artist('B', 8), artist('C', 1)], likes: [] },
      { artists: [artist('A', 1), artist('B', 8), artist('D', 1)], likes: [] },
    )
    expect(m?.artists.map((a) => a.name)).toEqual(['B', 'A'])
  })

  it('общие треки — мои, по ref или «артист — название», без повторов, до 5', () => {
    const mine = [track('sc:1', 'A', 'Один'), track('ym:2', 'B', 'Два'), track('sc:3', 'C'), track('sc:1', 'A', 'Один')]
    const theirs = [track('sc:1', 'A', 'Один'), track('sc:77', 'b', 'два')]
    const m = tasteMatch({ artists: [], likes: mine }, { artists: [], likes: theirs })
    expect(m?.tracks.map((t) => t.ref)).toEqual(['sc:1', 'ym:2'])
    const many = Array.from({ length: 9 }, (_, i) => track(`sc:${i}`))
    expect(tasteMatch({ artists: [], likes: many }, { artists: [], likes: many })?.tracks).toHaveLength(TASTE_TRACKS_SHOWN)
  })
})

describe('tasteLevel и tasteKey', () => {
  it('пороги 60 и 85', () => {
    expect([59, 60, 84, 85, 100].map(tasteLevel)).toEqual(['different', 'similar', 'similar', 'very', 'very'])
  })
  it('ключ без регистра, ё = е, пробелы схлопнуты', () => {
    expect(tasteKey('  Ёлка   и  Ко ')).toBe('елка и ко')
  })
})

describe('demoFriendTaste', () => {
  it('похож, но не копия: часть исполнителей, каждый третий лайк, тот же результат каждый раз', () => {
    const me = {
      artists: [artist('A', 50), artist('B', 30), artist('C', 20), artist('D', 10)],
      likes: Array.from({ length: 9 }, (_, i) => track(`sc:${i}`)),
    }
    const friend = demoFriendTaste(me)
    expect(friend.likes.map((t) => t.ref)).toEqual(['sc:0', 'sc:3', 'sc:6'])
    const m = tasteMatch(me, friend)
    // A, B, D: Σ min долей ≈ 0.377; лайки 3 / 20 → √(0.7 · 0.377 + 0.3 · 0.15) ≈ 56 — то же на iPhone
    expect(m?.percent).toBe(56)
    expect(m?.artists.map((a) => a.name).sort()).toEqual(['A', 'B', 'D'])
    expect(tasteMatch(me, demoFriendTaste(me))).toEqual(m)
  })
})
