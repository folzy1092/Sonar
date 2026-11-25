import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import type { Track } from './api'
import { canShare, shareData, shareLink } from './share'
import { decodeShare } from './share-link'

const fixture = JSON.parse(readFileSync(new URL('../../../site/src/lib/share-link.fixture.json', import.meta.url), 'utf8'))

const track = (over: Partial<Track> = {}): Track => ({
  ref: 'sc:247755542',
  title: 'Star Shopping',
  artist: 'Lil Peep',
  artists: [],
  album: null,
  duration_ms: 142_300,
  cover_url: 'https://i1.sndcdn.com/artworks-000-t500x500.jpg',
  url: 'https://soundcloud.com/lil_peep/star-shopping?si=tracker',
  explicit: false,
  available: true,
  ...over,
})

describe('ссылка «Поделиться» на ПК', () => {
  it('общий пример сайта и iPhone: та же ссылка', () => {
    const c = fixture.cases[0]
    const twins = { refs: { yt: 'yt:m8QQR-wQA0I', ym: 'ym:41245581' }, urls: {}, sc_full: true }
    expect(shareLink(track(), twins, c.lang)).toBe(c.url)
  })

  it('SoundCloud-отрывок без YouTube — сайт не играет, но кнопки есть', () => {
    const d = shareData(track(), { refs: {}, urls: {}, sc_full: false })
    expect(d?.play).toBeUndefined()
    expect(d?.sl).toBe('lil_peep/star-shopping')
  })

  it('с Яндекса: путь SoundCloud — из ссылки двойника', () => {
    const d = shareData(track({ ref: 'ym:1695', url: 'https://music.yandex.ru/album/1/track/1695' }), {
      refs: { sc: 'sc:5' },
      urls: { sc: 'https://soundcloud.com/kino/gruppa-krovi' },
      sc_full: true,
    })
    expect(d).toMatchObject({ src: 'ym', ids: { ym: '1695', sc: '5' }, sl: 'kino/gruppa-krovi', play: 'sc' })
  })

  it('без личного: в ссылке нет трекеров и чужих обложек', () => {
    const link = shareLink(track({ cover_url: 'https://evil.example/a.jpg' }), null, 'ru')!
    const d = decodeShare(link.split('#')[1])!
    expect(d.c).toBeUndefined()
    expect(link).not.toContain('si=')
    expect(JSON.stringify(d)).not.toContain('tracker')
  })

  it('локальным файлом не делимся', () => {
    expect(canShare(track({ ref: 'local:abc' }))).toBe(false)
    expect(canShare(track())).toBe(true)
  })
})
