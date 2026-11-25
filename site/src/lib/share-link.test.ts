import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import fixture from './share-link.fixture.json'
import {
  SHARE_MAX_LEN,
  decodeShare,
  encodeShare,
  pickPlay,
  scPath,
  shareUrl,
  validCover,
  type ShareData,
} from './share-link'

const base: ShareData = { t: 'Star Shopping', a: 'Lil Peep', d: 142, src: 'sc', ids: { sc: '247755542' } }

describe('ссылка «Поделиться»', () => {
  it('общий пример: та же строка, что у ПК и iPhone', () => {
    for (const c of fixture.cases) {
      const data = c.data as ShareData
      expect(encodeShare(data), c.name).toBe(c.encoded)
      expect(shareUrl(data, c.lang), c.name).toBe(c.url)
      expect(decodeShare(`#${c.encoded}`), c.name).toEqual(data)
    }
  })

  it('кириллица и эмодзи переживают кодирование', () => {
    const d = { ...base, t: 'Группа крови 🩸', a: 'Кино' }
    expect(decodeShare(encodeShare(d))).toEqual(d)
  })

  it('битая ссылка — null, а не исключение', () => {
    for (const h of ['', '#', '#%%%', '#abc', '#eyJ2IjoyfQ', `#${btoa('{"v":1,"t":"","src":"sc","ids":{}}')}`, '#!!!'])
      expect(decodeShare(h), h).toBeNull()
  })

  it('чужие поля и битые id выкидываются', () => {
    const raw = { v: 1, t: 'x', a: 'y', src: 'yt', ids: { yt: 'short', sc: '12', vk: '1_2' }, token: 'secret', play: 'yt' }
    const d = decodeShare(btoa(JSON.stringify(raw)).replace(/=+$/, ''))
    expect(d).toEqual({ t: 'x', a: 'y', src: 'yt', ids: { sc: '12' } })
  })

  it('обложка — только https с хостов сервисов', () => {
    expect(validCover('https://i1.sndcdn.com/a.jpg')).toBe(true)
    expect(validCover('https://avatars.yandex.net/get-music-content/1/400x400')).toBe(true)
    expect(validCover('http://i1.sndcdn.com/a.jpg')).toBe(false)
    expect(validCover('https://evil.example/a.jpg')).toBe(false)
    expect(validCover('https://i1.sndcdn.com.evil.example/a.jpg')).toBe(false)
    expect(validCover('javascript:alert(1)')).toBe(false)
  })

  it('длинная ссылка теряет обложку, а не данные', () => {
    const long = { ...base, t: 'а'.repeat(150), a: 'б'.repeat(150), c: `https://i1.sndcdn.com/${'x'.repeat(300)}.jpg` }
    const enc = encodeShare(long)
    expect(decodeShare(enc)?.c).toBeUndefined()
    expect(decodeShare(enc)?.t).toBe(long.t)
    expect(encodeShare(base).length).toBeLessThan(SHARE_MAX_LEN)
  })

  it('play — YouTube, иначе SoundCloud целиком, иначе ничего', () => {
    expect(pickPlay({ yt: 'm8QQR-wQA0I', sc: '1' }, true)).toBe('yt')
    expect(pickPlay({ sc: '1' }, true)).toBe('sc')
    expect(pickPlay({ sc: '1' }, false)).toBeUndefined()
    expect(pickPlay({ ym: '1', sp: '4uLU6hMCjMI75M1A2tKUQC' }, true)).toBeUndefined()
  })

  it('play без нужного id не проходит', () => {
    const raw = { v: 1, t: 'x', a: 'y', src: 'ym', ids: { ym: '1' }, play: 'sc' }
    expect(decodeShare(btoa(JSON.stringify(raw)).replace(/=+$/, ''))?.play).toBeUndefined()
  })

  it('путь SoundCloud без трекеров', () => {
    expect(scPath('https://soundcloud.com/lil_peep/star-shopping?si=abc&utm_source=x')).toBe('lil_peep/star-shopping')
    expect(scPath('https://m.soundcloud.com/a/b/')).toBe('a/b')
    expect(scPath('https://soundcloud.com/a/sets/b')).toBeUndefined()
    expect(scPath('https://soundcloud.com/discover/x')).toBeUndefined()
    expect(scPath('https://evil.example/a/b')).toBeUndefined()
    expect(scPath(null)).toBeUndefined()
  })

  it('язык — префиксом пути', () => {
    expect(shareUrl(base, 'ru')).toMatch(/^https:\/\/try-sonar\.ru\/t\/#/)
    expect(shareUrl(base, 'de')).toMatch(/^https:\/\/try-sonar\.ru\/de\/t\/#/)
  })

  it('копия в приложении ПК — байт в байт', () => {
    const site = readFileSync(new URL('./share-link.ts', import.meta.url), 'utf8')
    const pc = readFileSync(new URL('../../../windows/src/lib/share-link.ts', import.meta.url), 'utf8')
    expect(pc).toBe(site)
  })
})
