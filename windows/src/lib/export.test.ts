import { describe, expect, it } from 'vitest'
import {
  FALLBACK_NAME,
  MAX_NAME_CHARS,
  csvCell,
  exportText,
  safeFileName,
  serviceName,
  toCsv,
  toJson,
  toM3u8,
  trackWebUrl,
  type ExportTrack,
} from './export'

function track(over: Partial<ExportTrack> = {}): ExportTrack {
  return {
    ref: 'sc:1',
    title: 'Song',
    artist: 'Artist',
    artists: [{ ref: 'sca:5', name: 'Artist', avatar_url: null }],
    album: null,
    duration_ms: 123_400,
    cover_url: null,
    url: 'https://soundcloud.com/artist/song',
    explicit: false,
    available: true,
    ...over,
  }
}

describe('safeFileName', () => {
  it('keeps ordinary and unicode names as is', () => {
    expect(safeFileName('Мой плейлист')).toBe('Мой плейлист')
    expect(safeFileName('Café ☕ 2024')).toBe('Café ☕ 2024')
    expect(safeFileName('日本の歌')).toBe('日本の歌')
  })

  it('replaces forbidden and control characters with a single space', () => {
    expect(safeFileName('AC/DC: Best?')).toBe('AC DC Best')
    expect(safeFileName('a<b>c"d\\e|f*g')).toBe('a b c d e f g')
    expect(safeFileName('line\nbreak\ttab\u0000nul')).toBe('line break tab nul')
  })

  it('trims dots and spaces at the edges', () => {
    expect(safeFileName('  ..hidden.. ')).toBe('hidden')
    expect(safeFileName('end.')).toBe('end')
  })

  it('falls back to Sonar when nothing is left', () => {
    expect(safeFileName('')).toBe(FALLBACK_NAME)
    expect(safeFileName('???')).toBe(FALLBACK_NAME)
    expect(safeFileName(' . . ')).toBe(FALLBACK_NAME)
  })

  it('guards Windows device names', () => {
    expect(safeFileName('CON')).toBe('_CON')
    expect(safeFileName('nul')).toBe('_nul')
    expect(safeFileName('com1.backup')).toBe('_com1.backup')
    expect(safeFileName('Console')).toBe('Console')
  })

  it('limits length by characters, not UTF-16 units', () => {
    expect(Array.from(safeFileName('я'.repeat(300)))).toHaveLength(MAX_NAME_CHARS)
    expect(Array.from(safeFileName('🎵'.repeat(300)))).toHaveLength(MAX_NAME_CHARS)
  })
})

describe('trackWebUrl', () => {
  it('prefers the track own http link', () => {
    expect(trackWebUrl({ ref: 'ym:7', url: 'https://music.yandex.ru/album/3/track/7' })).toBe(
      'https://music.yandex.ru/album/3/track/7',
    )
  })

  it('builds the link from the registry ref when there is none', () => {
    expect(trackWebUrl({ ref: 'ym:7', url: null })).toBe('https://music.yandex.ru/track/7')
    expect(trackWebUrl({ ref: 'yt:dQw4w9WgXcQ', url: null })).toBe('https://music.youtube.com/watch?v=dQw4w9WgXcQ')
    expect(trackWebUrl({ ref: 'sp:4uLU6hMCjMI75M1A2tKUQC', url: null })).toBe(
      'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC',
    )
    expect(trackWebUrl({ ref: 'vk:-2001_42', url: null })).toBe('https://vk.com/audio-2001_42')
  })

  it('ignores non-http links and unknown refs', () => {
    expect(trackWebUrl({ ref: 'sc:1', url: 'javascript:alert(1)' })).toBeNull()
    expect(trackWebUrl({ ref: 'sc:1', url: null })).toBeNull()
    expect(trackWebUrl({ ref: 'local:abc', url: null })).toBeNull()
    expect(trackWebUrl({ ref: 'ymalb:9', url: null })).toBeNull()
    expect(trackWebUrl({ ref: 'zz:1', url: null })).toBeNull()
  })

  it('escapes the id', () => {
    expect(trackWebUrl({ ref: 'yt:a b&c', url: null })).toBe('https://music.youtube.com/watch?v=a%20b%26c')
  })
})

describe('toM3u8', () => {
  it('writes the header, EXTINF in seconds and the service link', () => {
    const out = toM3u8('Микс', [track(), track({ ref: 'ym:7', url: null, artist: 'Земфира', title: 'Хочешь?' })])
    expect(out).toBe(
      [
        '#EXTM3U',
        '#PLAYLIST:Микс',
        '#EXTINF:123,Artist - Song',
        'https://soundcloud.com/artist/song',
        '#EXTINF:123,Земфира - Хочешь?',
        'https://music.yandex.ru/track/7',
        '',
      ].join('\n'),
    )
  })

  it('keeps every entry on one line and marks unknown duration as -1', () => {
    const out = toM3u8('a\nb', [track({ title: 'two\r\nlines', duration_ms: 0, url: null, ref: 'local:x' })])
    expect(out.split('\n')).toEqual(['#EXTM3U', '#PLAYLIST:a b', '#EXTINF:-1,Artist - two lines', 'local:x', ''])
  })

  it('keeps commas inside the title (only the first comma separates)', () => {
    expect(toM3u8('x', [track({ title: 'One, Two' })])).toContain('#EXTINF:123,Artist - One, Two\n')
  })

  it('omits the dash when the artist is empty', () => {
    expect(toM3u8('x', [track({ artist: '' })])).toContain('#EXTINF:123,Song\n')
  })
})

describe('csvCell', () => {
  it('leaves plain values unquoted', () => {
    expect(csvCell('plain')).toBe('plain')
    expect(csvCell('Ёлка 🎄')).toBe('Ёлка 🎄')
  })

  it('quotes commas, quotes and line breaks and doubles inner quotes', () => {
    expect(csvCell('a,b')).toBe('"a,b"')
    expect(csvCell('say "hi"')).toBe('"say ""hi"""')
    expect(csvCell('two\nlines')).toBe('"two\nlines"')
    expect(csvCell('cr\rhere')).toBe('"cr\rhere"')
  })

  it('neutralizes spreadsheet formulas in text cells only', () => {
    expect(csvCell('=HYPERLINK("x")', true)).toBe(`"'=HYPERLINK(""x"")"`)
    expect(csvCell('+1', true)).toBe("'+1")
    expect(csvCell('@me', true)).toBe("'@me")
    expect(csvCell('-x', false)).toBe('-x')
  })
})

describe('toCsv', () => {
  it('writes BOM, header, CRLF rows with all columns', () => {
    const rows = [
      track({ added_at: Date.UTC(2026, 10, 17, 12, 30, 5, 999) }),
      track({
        ref: 'ym:7',
        url: null,
        title: 'Привет, мир',
        artist: 'Он "сам"',
        album: { ref: 'ymalb:3', title: 'Альбом' },
        added_at: null,
      }),
    ]
    const out = toCsv(rows)
    expect(out.startsWith('﻿')).toBe(true)
    expect(out.slice(1).split('\r\n')).toEqual([
      'title,artist,album,duration,service,link,added',
      'Song,Artist,,123,SoundCloud,https://soundcloud.com/artist/song,2026-11-17T12:30:05Z',
      '"Привет, мир","Он ""сам""",Альбом,123,Яндекс Музыка,https://music.yandex.ru/track/7,',
      '',
    ])
  })

  it('uses the given service label (translated names)', () => {
    expect(toCsv([track()], () => 'SC!')).toContain(',SC!,')
  })

  it('writes only the header for an empty list', () => {
    expect(toCsv([])).toBe('﻿title,artist,album,duration,service,link,added\r\n')
  })
})

describe('toJson', () => {
  it('writes API.md Track fields in order plus added_at and drops client-only fields', () => {
    const out = toJson([track({ added_at: 1_794_340_594_779, plays: 5 }), track({ ref: 'ym:2' })])
    const parsed = JSON.parse(out)
    expect(parsed).toHaveLength(2)
    expect(Object.keys(parsed[0])).toEqual([
      'ref',
      'title',
      'artist',
      'artists',
      'album',
      'duration_ms',
      'cover_url',
      'url',
      'explicit',
      'available',
      'added_at',
    ])
    expect(parsed[0].added_at).toBe(1_794_340_594_779)
    expect(parsed[0].plays).toBeUndefined()
    expect(parsed[1].added_at).toBeNull()
    expect(parsed[0].artists).toEqual([{ ref: 'sca:5', name: 'Artist', avatar_url: null }])
  })

  it('round-trips unicode and escapes control characters', () => {
    const title = 'Кавычка " и\nперенос 🎶'
    const out = toJson([track({ title })])
    expect(JSON.parse(out)[0].title).toBe(title)
    expect(out).toContain('\\n')
    expect(out).toContain('🎶')
    expect(out.endsWith(']\n')).toBe(true)
  })

  it('writes an empty array for an empty list', () => {
    expect(toJson([])).toBe('[]\n')
  })
})

describe('exportText and serviceName', () => {
  it('dispatches by format', () => {
    const list = [track()]
    expect(exportText('m3u8', 'x', list)).toBe(toM3u8('x', list))
    expect(exportText('csv', 'x', list)).toBe(toCsv(list))
    expect(exportText('json', 'x', list)).toBe(toJson(list))
  })

  it('names the service from the registry', () => {
    expect(serviceName('sc:1')).toBe('SoundCloud')
    expect(serviceName('ym:1')).toBe('Яндекс Музыка')
    expect(serviceName('nope')).toBe('')
  })
})
