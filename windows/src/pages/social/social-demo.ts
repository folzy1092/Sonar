// Демо-данные «Вместе» (комната и сообщения) до сервера: друзей нет, поэтому комната и чат собираются из
// моих же Любимых и двух выдуманных друзей — как демо-друг «Схожести» (lib/taste-match.ts). Всё живёт в памяти
// страницы, никуда не уходит. Правила — настоящие: комнату двигает `applyOp`, чат — `dm-core`.
import type { ListTrack } from '../../lib/api'
import { applyOp, newRoom, type Room, type RoomMember } from '../../lib/rooms/room-core'
import type { DMAttachment, DMMessage, DMThread } from '../../lib/dm/dm-core'

export const FRIEND = 'demo_friend'
export const FRIEND2 = 'demo_friend2'
export const ROOM_ID = 'demo_room'

export function demoMembers(me: RoomMember, friendName: string, friend2Name: string): RoomMember[] {
  return [
    me,
    { username: FRIEND, display_name: friendName, avatar_url: null },
    { username: FRIEND2, display_name: friend2Name, avatar_url: null },
  ]
}

/** Комната: я — хост, первый друг — диджей, второй — слушатель; очередь — до 8 моих Любимых. */
export function demoRoom(members: RoomMember[], tracks: ListTrack[], now: number): Room {
  const [me, friend, friend2] = members
  let room = newRoom(ROOM_ID, me, [], now)
  const step = (by: string, op: Parameters<typeof applyOp>[2]) => {
    const res = applyOp(room, by, op, now)
    if (res.ok) room = res.room
  }
  step(friend.username, { type: 'join', member: friend })
  step(friend2.username, { type: 'join', member: friend2 })
  step(me.username, { type: 'dj.set', username: friend.username, on: true })
  // кто что добавил: по очереди я и диджей — видно подпись «добавил»
  tracks.slice(0, 8).forEach((t, i) => step(i % 3 === 1 ? friend.username : me.username, { type: 'queue.add', ref: t.ref }))
  step(me.username, { type: 'play', position_ms: Math.min(42_000, Math.floor((tracks[0]?.duration_ms ?? 0) / 3)) })
  return room
}

const track = (t: ListTrack): DMAttachment => ({ kind: 'track', ref: t.ref, title: t.title, artist: t.artist, cover_url: t.cover_url })

export interface DemoChat {
  threads: DMThread[]
  messages: DMMessage[]
}

/** Два чата: личный с другом (трек, ответ, приглашение в комнату) и чат комнаты. */
export function demoChat(me: string, tracks: ListTrack[], roomTitle: string, lines: Record<'hey' | 'fire' | 'join' | 'room', string>, now: number): DemoChat {
  const min = 60_000
  const threads: DMThread[] = [
    { id: 'dm_friend', peer: FRIEND, room_id: null, peer_read_at: now - 10 * min, my_read_at: now - 20 * min },
    { id: 'dm_room', peer: null, room_id: ROOM_ID, peer_read_at: now, my_read_at: now },
  ]
  const msg = (id: string, thread_id: string, from: string, ago: number, text: string, attachments: DMAttachment[] = [], reply_to: string | null = null): DMMessage => ({
    id, thread_id, from, text, attachments, reply_to, sent_at: now - ago * min, edited_at: null, deleted: false,
  })
  const [a, b] = tracks
  const messages: DMMessage[] = [
    msg('m1', 'dm_friend', FRIEND, 42, lines.hey, a ? [track(a)] : []),
    msg('m2', 'dm_friend', me, 30, lines.fire, [], 'm1'),
    msg('m3', 'dm_friend', me, 12, lines.join, [{ kind: 'room', room_id: ROOM_ID, host: me, title: roomTitle }]),
    ...(b ? [msg('m4', 'dm_friend', FRIEND, 8, '', [track(b)])] : []),
    msg('r1', 'dm_room', FRIEND2, 5, lines.room),
  ]
  return { threads, messages }
}
