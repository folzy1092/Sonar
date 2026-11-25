import { describe, expect, it } from 'vitest'
import type { ShareData } from './share-link'
import { appLink, bestHit, cleanTitle, coverUrl, embedUrl, lineAt, lyricsPairs, parseLrc, serviceLinks } from './track-page'

const yt: ShareData = { t: 'Star Shopping', a: 'Lil Peep', d: 142, src: 'sc', ids: { sc: '247755542', yt: 'm8QQR-wQA0I' }, sl: 'lil_peep/star-shopping', play: 'yt' }
const ymOnly: ShareData = { t: 'Группа крови', a: 'Кино', src: 'ym', ids: { ym: '1695' } }

describe('кнопки сервисов', () => {
  it('найденные — прямыми ссылками и первыми', () => {
    const links = serviceLinks(yt)
    expect(links.slice(0, 2).map((l) => [l.service, l.href])).toEqual([
      ['yt', 'https://music.youtube.com/watch?v=m8QQR-wQA0I'],
      ['sc', 'https://soundcloud.com/lil_peep/star-shopping'],
    ])
    expect(links.find((l) => l.service === 'ym')).toEqual({ service: 'ym', href: 'https://music.yandex.ru/search?text=Lil%20Peep%20Star%20Shopping', direct: false })
    expect(links).toHaveLength(5)
  })

  it('SoundCloud без пути — поиск, Apple Music — всегда поиск', () => {
    const links = serviceLinks(ymOnly)
    expect(links[0]).toEqual({ service: 'ym', href: 'https://music.yandex.ru/track/1695', direct: true })
    expect(links.find((l) => l.service === 'sc')?.direct).toBe(false)
    expect(links.find((l) => l.service === 'am')?.href).toBe('https://music.apple.com/search?term=%D0%9A%D0%B8%D0%BD%D0%BE%20%D0%93%D1%80%D1%83%D0%BF%D0%BF%D0%B0%20%D0%BA%D1%80%D0%BE%D0%B2%D0%B8')
  })
})

describe('встройка и обложка', () => {
  it('YouTube — nocookie с JS API', () => {
    const u = new URL(embedUrl(yt, 'https://try-sonar.ru')!)
    expect(u.origin + u.pathname).toBe('https://www.youtube-nocookie.com/embed/m8QQR-wQA0I')
    expect(u.searchParams.get('enablejsapi')).toBe('1')
    expect(u.searchParams.get('origin')).toBe('https://try-sonar.ru')
  })
  it('SoundCloud — виджет по id', () => {
    const u = new URL(embedUrl({ ...yt, play: 'sc' }, 'https://try-sonar.ru')!)
    expect(u.origin).toBe('https://w.soundcloud.com')
    expect(u.searchParams.get('url')).toBe('https://api.soundcloud.com/tracks/247755542')
  })
  it('без play — встройки нет', () => {
    expect(embedUrl(ymOnly, 'https://try-sonar.ru')).toBeNull()
  })
  it('обложки нет — превью YouTube', () => {
    expect(coverUrl(yt)).toBe('https://i.ytimg.com/vi/m8QQR-wQA0I/hqdefault.jpg')
    expect(coverUrl(ymOnly)).toBeNull()
  })
  it('ссылка в приложение — ref исходного сервиса', () => {
    expect(appLink(yt)).toBe('sonar://track/sc:247755542')
    expect(appLink(ymOnly)).toBe('sonar://track/ym:1695')
  })
})

describe('текст', () => {
  it('LRC: метки, несколько меток у строки, паузы', () => {
    const lines = parseLrc('[ar: x]\n[00:01.50]Раз\n[00:03.00][00:10.00]Припев\n[00:05.20]\n')
    expect(lines).toEqual([
      { at: 1.5, text: 'Раз' },
      { at: 3, text: 'Припев' },
      { at: 5.2, text: '' },
      { at: 10, text: 'Припев' },
    ])
  })
  it('текущая строка', () => {
    const lines = parseLrc('[00:01.00]a\n[00:02.00]b\n[00:03.00]c')
    expect(lineAt(lines, 0)).toBe(-1)
    expect(lineAt(lines, 1.9)).toBe(1)
    expect(lineAt(lines, 99)).toBe(2)
    expect(lineAt([], 5)).toBe(-1)
  })
  it('перезалив «АРТИСТ - ТРЕК» — вторая пара', () => {
    expect(lyricsPairs({ a: 'some uploader', t: 'Lil Peep - Star Shopping (slowed + reverb)' })).toEqual([
      ['some uploader', 'Lil Peep - Star Shopping'],
      ['Lil Peep', 'Star Shopping'],
    ])
    expect(lyricsPairs({ a: 'Кино', t: 'Группа крови' })).toEqual([['Кино', 'Группа крови']])
  })
  it('чистка названия', () => {
    expect(cleanTitle('Track [Official Video]')).toBe('Track')
    expect(cleanTitle('Track prod. someone')).toBe('Track')
    expect(cleanTitle('Track feat. X')).toBe('Track')
    expect(cleanTitle('Remix')).toBe('Remix')
  })
  it('выдача поиска: длительность ±3 с, синхронный — выше', () => {
    const hits = [
      { duration: 200, plainLyrics: 'p' },
      { duration: 143, plainLyrics: 'p2' },
      { duration: 141, syncedLyrics: '[00:01.00]s', plainLyrics: 's' },
    ]
    expect(bestHit(hits, 142)).toBe(hits[2])
    expect(bestHit(hits.slice(0, 2), 142)).toBe(hits[1])
    expect(bestHit([{ duration: 10, plainLyrics: 'x' }], 142)).toBeNull()
  })
})
