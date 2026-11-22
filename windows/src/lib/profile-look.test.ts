import { describe, expect, it } from 'vitest'
import {
  addLink,
  addShowcase,
  canShowcase,
  colorHex,
  LINKS_MAX,
  linkLabel,
  NICK_FONTS,
  nickFontStack,
  parseLink,
  PROFILE_COLORS,
  readLinks,
  readShowcase,
  removeLink,
  removeShowcase,
  SHOWCASE_MAX,
  showcaseAlbum,
  showcaseArtist,
  showcasePlaylist,
  showcaseTrack,
  visibleShowcase,
  type ShowcaseItem,
} from './profile-look'

const item = (ref: string, kind: ShowcaseItem['kind'] = 'track'): ShowcaseItem => ({ kind, ref, title: ref, subtitle: '', cover_url: null })

describe('цвет и шрифт ника', () => {
  it('десять цветов и пустой — цвет темы', () => {
    expect(PROFILE_COLORS).toHaveLength(10)
    expect(colorHex('blue')).toBe('#4c8dff')
    expect(colorHex('')).toBeNull()
    expect(colorHex('nope')).toBeNull()
  })

  it('шрифт ника — сетка из 12, по умолчанию без своего шрифта', () => {
    expect(NICK_FONTS).toHaveLength(12)
    expect(nickFontStack('default')).toBeNull()
    expect(nickFontStack('unknown')).toBeNull()
    expect(nickFontStack('pixel')).toContain("'Pixelify Sans Variable'")
  })
})

describe('ссылки профиля', () => {
  it('узнаёт Telegram по @нику и по домену', () => {
    expect(parseLink('@folzy_music')).toEqual({ kind: 'telegram', url: 'https://t.me/folzy_music' })
    expect(parseLink('t.me/SonarUpdates')?.kind).toBe('telegram')
  })

  it('узнаёт Discord и сайт, дописывает https', () => {
    expect(parseLink('https://discord.gg/abc')?.kind).toBe('discord')
    expect(parseLink('try-sonar.ru')).toEqual({ kind: 'site', url: 'https://try-sonar.ru/' })
  })

  it('не ссылка и чужой протокол — null', () => {
    expect(parseLink('')).toBeNull()
    expect(parseLink('просто текст')).toBeNull()
    expect(parseLink('javascript:alert(1)')).toBeNull()
    expect(parseLink('ftp://files.example.com')).toBeNull()
  })

  it('подпись без протокола и косой черты', () => {
    expect(linkLabel({ kind: 'site', url: 'https://www.example.com/' })).toBe('example.com')
  })

  it('добавляет без повторов и не больше предела, не меняя исходный список', () => {
    const one = [parseLink('@folzy_music')!]
    expect(addLink(one, parseLink('@folzy_music')!)).toHaveLength(1)
    const full = Array.from({ length: LINKS_MAX }, (_, i) => parseLink(`site${i}.com`)!)
    expect(addLink(full, parseLink('extra.com')!)).toHaveLength(LINKS_MAX)
    const two = addLink(one, parseLink('try-sonar.ru')!)
    expect(two).toHaveLength(2)
    expect(one).toHaveLength(1)
    expect(removeLink(two, 'https://t.me/folzy_music')).toEqual([parseLink('try-sonar.ru')])
  })

  it('из настроек берёт только настоящие ссылки', () => {
    expect(readLinks([{ url: '@folzy_music' }, { url: 'нет' }, null, 5])).toEqual([{ kind: 'telegram', url: 'https://t.me/folzy_music' }])
    expect(readLinks('мусор')).toEqual([])
  })
})

describe('витрина', () => {
  it('до шести мест без повторов', () => {
    let list: ShowcaseItem[] = []
    for (let i = 0; i < SHOWCASE_MAX + 2; i++) list = addShowcase(list, item(`t${i}`))
    expect(list).toHaveLength(SHOWCASE_MAX)
    expect(addShowcase([item('a')], item('a'))).toHaveLength(1)
    expect(addShowcase([item('a')], item('a', 'album'))).toHaveLength(2)
  })

  it('скрытый «от других» плейлист не ставится и пропадает из показа', () => {
    expect(canShowcase(item('p1', 'playlist'), ['p1'])).toBe(false)
    expect(canShowcase(item('p1', 'track'), ['p1'])).toBe(true)
    expect(addShowcase([], item('p1', 'playlist'), ['p1'])).toEqual([])
    const list = [item('p1', 'playlist'), item('t1')]
    expect(visibleShowcase(list, ['p1'])).toEqual([item('t1')])
  })

  it('убирает по виду и ref, исходный список цел', () => {
    const list = [item('a'), item('a', 'album')]
    expect(removeShowcase(list, 'track', 'a')).toEqual([item('a', 'album')])
    expect(list).toHaveLength(2)
  })

  it('из настроек отбрасывает битые записи', () => {
    const raw = [item('a'), { kind: 'video', ref: 'x', title: 'x' }, { kind: 'album', ref: 'b', title: 'B', cover_url: 3 }, 'x']
    expect(readShowcase(raw)).toEqual([item('a'), { kind: 'album', ref: 'b', title: 'B', subtitle: '', cover_url: null }])
    expect(readShowcase(null)).toEqual([])
  })
})

describe('места витрины из медиатеки и поиска', () => {
  it('плейлист Sonar — по id и первой обложке', () => {
    expect(showcasePlaylist({ id: 'pl_1', name: 'Ночь', covers: ['a.jpg', 'b.jpg'] })).toEqual({ kind: 'playlist', ref: 'pl_1', title: 'Ночь', subtitle: '', cover_url: 'a.jpg' })
    expect(showcasePlaylist({ id: 'pl_2', name: 'Пусто', covers: [] }).cover_url).toBeNull()
  })

  it('трек, альбом и исполнитель сервиса — по ref', () => {
    expect(showcaseTrack({ ref: 'sc:1', title: 'Song', artist: 'Band', cover_url: null })).toMatchObject({ kind: 'track', ref: 'sc:1', subtitle: 'Band' })
    expect(showcaseAlbum({ ref: 'ym:al:2', title: 'LP', artist: 'Band', cover_url: 'c.jpg' })).toMatchObject({ kind: 'album', cover_url: 'c.jpg' })
    expect(showcaseArtist({ ref: 'ym:ar:3', name: 'Band', avatar_url: 'b.jpg' })).toEqual({ kind: 'artist', ref: 'ym:ar:3', title: 'Band', subtitle: '', cover_url: 'b.jpg' })
  })
})
