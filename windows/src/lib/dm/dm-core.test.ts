import { describe, expect, it } from 'vitest'
import {
  attachmentLink, canEdit, dropExpired, DM_RETENTION_MS, checkDraft, deleteMessage, DM_EDIT_WINDOW_MS, DM_MAX_TEXT, editMessage, groupRuns, parseSonarLinks,
  replyPreview, seenByPeer, sonarLink, timeline, unreadCount, type DMMessage, type DMThread,
} from './dm-core'

const msg = (id: string, from: string, sent_at: number, text = 'привет', patch: Partial<DMMessage> = {}): DMMessage => ({
  id, thread_id: 't1', from, text, attachments: [], reply_to: null, sent_at, edited_at: null, deleted: false, ...patch,
})
const thread: DMThread = { id: 't1', peer: 'ann', room_id: null, peer_read_at: 200, my_read_at: 150 }

describe('ссылки sonar://', () => {
  it('туда и обратно, ref с двоеточием', () => {
    const link = sonarLink('track', 'sc:123')
    expect(link).toBe('sonar://track/sc:123')
    expect(parseSonarLinks(`лови ${link}, огонь`)).toEqual([{ kind: 'track', value: 'sc:123' }])
  })

  it('несколько видов, без повторов, хвостовая пунктуация отрезается', () => {
    const text = 'sonar://room/r42! и sonar://TRACK/ym:9. ещё раз sonar://track/ym:9 и sonar://album/ymalb:1)'
    expect(parseSonarLinks(text)).toEqual([
      { kind: 'room', value: 'r42' },
      { kind: 'track', value: 'ym:9' },
      { kind: 'album', value: 'ymalb:1' },
    ])
  })

  it('кириллица в значении кодируется и раскодируется; чужие схемы — мимо', () => {
    expect(parseSonarLinks(sonarLink('user', 'фолзи'))).toEqual([{ kind: 'user', value: 'фолзи' }])
    expect(parseSonarLinks('https://x.ru/track/1 sonar://play/liked sonar://track/')).toEqual([])
    expect(parseSonarLinks('sonar://track/%E0%A4%A')).toEqual([])
  })

  it('вложения ведут на свою ссылку', () => {
    expect(attachmentLink({ kind: 'track', ref: 'sc:1', title: 'a', artist: 'b', cover_url: null })).toBe('sonar://track/sc:1')
    expect(attachmentLink({ kind: 'room', room_id: 'r1', host: 'folzy', title: 'x' })).toBe('sonar://room/r1')
  })
})

describe('сообщения', () => {
  it('черновик: пустое без вложений не уходит, длина в символах, а не байтах', () => {
    expect(checkDraft('   ', [])).toEqual({ ok: false, error: 'empty' })
    expect(checkDraft(' ', [{ kind: 'room', room_id: 'r', host: 'h', title: 't' }])).toEqual({ ok: true, text: '' })
    expect(checkDraft('🎵'.repeat(DM_MAX_TEXT), [])).toMatchObject({ ok: true })
    expect(checkDraft('a'.repeat(DM_MAX_TEXT + 1), [])).toEqual({ ok: false, error: 'too_long' })
  })

  it('правка: своё и в окне; чужое, удалённое, старое, без изменений — нельзя', () => {
    const mine = msg('1', 'me', 0)
    expect(editMessage(mine, 'me', ' ку ', 10)).toEqual({ ...mine, text: 'ку', edited_at: 10 })
    expect(editMessage(mine, 'ann', 'ку', 10)).toBeNull()
    expect(editMessage(mine, 'me', 'привет', 10)).toBeNull()
    expect(canEdit(mine, 'me', DM_EDIT_WINDOW_MS + 1)).toBe(false)
    expect(editMessage({ ...mine, deleted: true }, 'me', 'ку', 10)).toBeNull()
  })

  it('старше 30 дней — стёрто', () => {
    const now = DM_RETENTION_MS + 1000
    expect(dropExpired([msg('old', 'a', 999), msg('new', 'a', 1000)], now).map((m) => m.id)).toEqual(['new'])
  })

  it('удаление стирает содержимое, оставляет место', () => {
    const d = deleteMessage(msg('1', 'me', 0, 'x', { attachments: [{ kind: 'room', room_id: 'r', host: 'h', title: 't' }] }), 'me')
    expect(d).toMatchObject({ text: '', attachments: [], deleted: true })
    expect(deleteMessage(msg('1', 'ann', 0), 'me')).toBeNull()
  })

  it('непрочитанные и «прочитано»', () => {
    const list = [msg('1', 'ann', 100), msg('2', 'ann', 160), msg('3', 'me', 170), msg('4', 'ann', 180, '', { deleted: true })]
    expect(unreadCount(thread, list, 'me')).toBe(1)
    expect(seenByPeer(thread, list[2], 'me')).toBe(true)
    expect(seenByPeer({ ...thread, peer_read_at: 100 }, list[2], 'me')).toBe(false)
  })

  it('цитата ответа: первая строка, обрезка, вложение вместо пустого текста', () => {
    expect(replyPreview(msg('1', 'a', 0, 'раз\nдва'))).toBe('раз')
    expect(replyPreview(msg('1', 'a', 0, 'абвгд'), 4)).toBe('абв…')
    expect(replyPreview(msg('1', 'a', 0, '', { attachments: [{ kind: 'track', ref: 'sc:1', title: 'Т', artist: 'А', cover_url: null }] }))).toBe('А — Т')
    expect(replyPreview(msg('1', 'a', 0, 'x', { deleted: true }))).toBeNull()
    expect(replyPreview(undefined)).toBeNull()
  })

  it('лента по времени без дублей; группы одного автора с разрывом по времени', () => {
    const list = [msg('b', 'me', 20), msg('a', 'ann', 10), msg('b', 'me', 20, 'правка'), { ...msg('z', 'x', 1), thread_id: 't2' }]
    const line = timeline(list, 't1')
    expect(line.map((m) => m.id)).toEqual(['a', 'b'])
    expect(line[1].text).toBe('правка')
    const runs = groupRuns([msg('1', 'a', 0), msg('2', 'a', 1000), msg('3', 'b', 2000), msg('4', 'b', 2000 + 6 * 60_000)])
    expect(runs.map((r) => r.map((m) => m.id))).toEqual([['1', '2'], ['3'], ['4']])
  })
})
