import { describe, expect, it } from 'vitest'
import { collage, coverKey, distinctCovers, type CoverSource } from './covers'

const t = (cover_url: string | null, album: string | null = null, artist = 'A'): CoverSource => ({
  cover_url,
  artist,
  album: album ? { ref: album } : null,
})

describe('coverKey', () => {
  it('SoundCloud: размер, схема и запрос не важны', () => {
    const base = 'i1.sndcdn.com/artworks-abc-0'
    expect(coverKey(`https://${base}-t500x500.jpg`)).toBe(`${base}.jpg`)
    expect(coverKey(`http://${base}-large.jpg?x=1`)).toBe(`${base}.jpg`)
    expect(coverKey(`https://${base}-t300x300.jpg`)).toBe(`${base}.jpg`)
  })

  it('Яндекс: %% и /400x400', () => {
    const base = 'avatars.yandex.net/get-music-content/123/abc.a.1-1'
    expect(coverKey(`https://${base}/%%`)).toBe(base)
    expect(coverKey(`https://${base}/400x400`)).toBe(base)
    expect(coverKey(`https://${base}/m1000x1000`)).toBe(base)
  })

  it('YouTube: =w544-h544 и подобное', () => {
    const base = 'lh3.googleusercontent.com/abcdef'
    expect(coverKey(`https://${base}=w544-h544-l90-rj`)).toBe(base)
    expect(coverKey(`https://${base}=w120-h120`)).toBe(base)
    expect(coverKey(`https://${base}=s0`)).toBe(base)
  })

  it('адрес через локальный прокси обложек сравнивается по исходному', () => {
    const raw = 'https://i1.sndcdn.com/artworks-x-t500x500.jpg'
    expect(coverKey(`http://127.0.0.1:5000/cover?u=${encodeURIComponent(raw)}`)).toBe(coverKey(raw))
  })
})

describe('distinctCovers', () => {
  it('10 треков одного альбома + 3 других — 4 разные обложки, первым альбом', () => {
    const list = [
      ...Array.from({ length: 10 }, (_, i) => t(`https://c/alb-${i}-t500x500.jpg`, 'ym:alb1')),
      t('https://c/x.jpg', 'ym:x'),
      t('https://c/y.jpg', 'ym:y'),
      t('https://c/z.jpg', null, 'Z'),
    ]
    expect(distinctCovers(list)).toEqual(['https://c/alb-0-t500x500.jpg', 'https://c/x.jpg', 'https://c/y.jpg', 'https://c/z.jpg'])
  })

  it('тот же адрес в другом размере — повтор, даже у разных альбомов', () => {
    const list = [t('https://c/a-t500x500.jpg', 'sc:1'), t('https://c/a-large.jpg', 'sc:2'), t('https://c/b.jpg')]
    expect(distinctCovers(list)).toEqual(['https://c/a-t500x500.jpg', 'https://c/b.jpg'])
  })

  it('без альбома: исполнитель + адрес', () => {
    const list = [t('https://c/a.jpg', null, 'A'), t('https://c/a.jpg?v=2', null, 'A'), t('https://c/b.jpg', null, 'A')]
    expect(distinctCovers(list)).toEqual(['https://c/a.jpg', 'https://c/b.jpg'])
  })

  it('идёт дальше первых 30 треков, если разных меньше четырёх', () => {
    const list = [...Array.from({ length: 40 }, () => t('https://c/same.jpg', 'alb')), t('https://c/1.jpg'), t('https://c/2.jpg'), t('https://c/3.jpg')]
    expect(distinctCovers(list)).toHaveLength(4)
  })

  it('без обложек — пусто; порядок стабильный', () => {
    expect(distinctCovers([t(null), t(null)])).toEqual([])
    const list = [t('https://c/1.jpg'), t('https://c/2.jpg'), t('https://c/3.jpg'), t('https://c/4.jpg'), t('https://c/5.jpg')]
    expect(distinctCovers(list)).toEqual(distinctCovers([...list]))
  })
})

describe('collage', () => {
  it('4 разные — сетка, 2–3 — одна первая, 0 — пусто', () => {
    const four = ['1', '2', '3', '4'].map((x) => t(`https://c/${x}.jpg`))
    expect(collage(four)).toHaveLength(4)
    expect(collage(four.slice(0, 3))).toEqual(['https://c/1.jpg'])
    expect(collage(four.slice(0, 1))).toEqual(['https://c/1.jpg'])
    expect(collage([])).toEqual([])
  })
})
