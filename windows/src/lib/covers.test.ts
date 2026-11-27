import { describe, expect, it } from 'vitest'
import { collage, coverKey, distinctCovers, thumbUrl, type CoverSource } from './covers'

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

describe('thumbUrl', () => {
  it('SoundCloud: 500 → large / t300x300, большое — как есть', () => {
    const u = 'https://i1.sndcdn.com/artworks-abc-t500x500.jpg'
    expect(thumbUrl(u, 44)).toBe('https://i1.sndcdn.com/artworks-abc-large.jpg')
    expect(thumbUrl(u, 44, 2)).toBe('https://i1.sndcdn.com/artworks-abc-large.jpg')
    expect(thumbUrl(u, 120, 2)).toBe('https://i1.sndcdn.com/artworks-abc-t300x300.jpg')
    expect(thumbUrl(u, 320, 1.5)).toBe(u)
    expect(thumbUrl('https://i1.sndcdn.com/avatars-x-large.jpg', 44)).toBe('https://i1.sndcdn.com/avatars-x-large.jpg')
  })
  it('Яндекс: 400x400 → 100x100 / 200x200', () => {
    const u = 'https://avatars.yandex.net/get-music-content/1/ab/400x400'
    expect(thumbUrl(u, 44, 1.25)).toBe('https://avatars.yandex.net/get-music-content/1/ab/100x100')
    expect(thumbUrl(u, 160, 1)).toBe('https://avatars.yandex.net/get-music-content/1/ab/200x200')
    expect(thumbUrl(u, 320, 1)).toBe(u)
  })
  it('Google: =w544-h544 → 120 / 240, =s544 тоже', () => {
    expect(thumbUrl('https://lh3.googleusercontent.com/x=w544-h544-l90-rj', 44, 2)).toBe('https://lh3.googleusercontent.com/x=w120-h120-l90-rj')
    expect(thumbUrl('https://yt3.ggpht.com/x=s544', 180)).toBe('https://yt3.ggpht.com/x=s240')
    expect(thumbUrl('https://lh3.googleusercontent.com/x=w60-h60', 200)).toBe('https://lh3.googleusercontent.com/x=w60-h60')
  })
  it('Spotify: 640 → 64 / 300', () => {
    const u = 'https://i.scdn.co/image/ab67616d0000b273deadbeef'
    expect(thumbUrl(u, 40)).toBe('https://i.scdn.co/image/ab67616d00004851deadbeef')
    expect(thumbUrl(u, 180)).toBe('https://i.scdn.co/image/ab67616d00001e02deadbeef')
    expect(thumbUrl(u, 400)).toBe(u)
  })
  it('чужие адреса не трогает, ключ коллажа тот же', () => {
    expect(thumbUrl('http://127.0.0.1:5000/cover?u=x', 40)).toBe('http://127.0.0.1:5000/cover?u=x')
    const u = 'https://avatars.yandex.net/get-music-content/1/ab/400x400'
    expect(coverKey(thumbUrl(u, 40))).toBe(coverKey(u))
  })
})
