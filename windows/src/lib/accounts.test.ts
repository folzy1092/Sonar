import { describe, expect, it } from 'vitest'
import { accountRows, maskKey, safeProfileUrl } from './accounts'
import type { ServiceStatus, ServicesStatus } from './api'

const off: ServiceStatus = { connected: false, name: null, avatar_url: null }
const status = (p: Partial<ServicesStatus>): ServicesStatus => ({ soundcloud: off, yandex: off, youtube: off, spotify: off, ...p })

describe('safeProfileUrl', () => {
  it('пропускает только https', () => {
    expect(safeProfileUrl('https://soundcloud.com/folzy')).toBe('https://soundcloud.com/folzy')
    expect(safeProfileUrl('http://soundcloud.com/folzy')).toBeNull()
    expect(safeProfileUrl('javascript:alert(1)')).toBeNull()
    expect(safeProfileUrl('file:///C:/Windows')).toBeNull()
    expect(safeProfileUrl('не адрес')).toBeNull()
    expect(safeProfileUrl(null)).toBeNull()
    expect(safeProfileUrl('')).toBeNull()
  })
})

describe('accountRows', () => {
  it('пусто, пока статус не пришёл или никто не вошёл', () => {
    expect(accountRows(null)).toEqual([])
    expect(accountRows(status({}))).toEqual([])
  })

  it('берёт только подключённые, ссылка — когда сервис её отдал', () => {
    const rows = accountRows(
      status({
        soundcloud: { connected: true, name: 'Folzy', avatar_url: 'https://i1.sndcdn.com/a.jpg', profile_url: 'https://soundcloud.com/folzy' },
        yandex: { connected: true, name: 'Денис', avatar_url: null, profile_url: null },
        spotify: { connected: false, name: 'старое', avatar_url: null, profile_url: 'https://open.spotify.com/user/x' },
      }),
    )
    expect(rows.map((r) => [r.service, r.name, r.url])).toEqual([
      ['sc', 'Folzy', 'https://soundcloud.com/folzy'],
      ['ym', 'Денис', null],
    ])
    expect(rows[0].avatar).toBe('https://i1.sndcdn.com/a.jpg')
  })

  it('чужая схема в адресе ссылкой не становится', () => {
    const rows = accountRows(status({ youtube: { connected: true, name: 'F', avatar_url: null, profile_url: 'javascript:1' } }))
    expect(rows).toHaveLength(1)
    expect(rows[0].url).toBeNull()
  })
})

describe('maskKey', () => {
  it('прячет ключ, оставляя префикс и хвост', () => {
    expect(maskKey('snr_AbCdEfGhIjKlMnOp')).toBe('snr_••••••••MnOp')
    expect(maskKey('snr_abc')).toBe('•••')
    expect(maskKey('')).toBe('')
  })
})
