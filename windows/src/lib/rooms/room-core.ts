// Комната совместного прослушивания (docs/ROOMS.md): состояние, роли и права, операции с `rev`.
// Чистое ядро без сети: до сервера им пользуется демо-экран, потом тем же правилам следует сервер
// (он — источник истины, клиент только принимает снимки с бо́льшим `rev`). iPhone — `Core/Rooms/RoomCore.swift`,
// правила менять в обоих местах и в docs/ROOMS.md.

export interface RoomMember {
  username: string
  display_name: string | null
  avatar_url: string | null
}

export interface RoomItem {
  ref: string
  added_by: string
}

/** Якорь времени: в момент `server_ts_ms` (часы сервера) лидер был на `position_ms`. */
export interface RoomAnchor {
  server_ts_ms: number
  position_ms: number
}

export interface Room {
  id: string
  /** Создал комнату, единственный может её закрыть. */
  host: string
  /** Чьи Play / пауза / перемотка главные. По умолчанию хост. */
  leader: string
  /** Могут менять очередь. Хост и лидер — всегда, без записи здесь. */
  djs: string[]
  members: RoomMember[]
  queue: RoomItem[]
  /** Индекс играющего трека в `queue`. */
  pos: number
  playing: boolean
  anchor: RoomAnchor
  /** Номер версии: растёт на каждую принятую операцию. */
  rev: number
  closed: boolean
}

export type RoomRole = 'host' | 'leader' | 'dj' | 'listener'

export type RoomOp =
  | { type: 'join'; member: RoomMember }
  | { type: 'leave' }
  | { type: 'play'; position_ms?: number }
  | { type: 'pause'; position_ms: number }
  | { type: 'seek'; position_ms: number }
  | { type: 'next' }
  | { type: 'prev' }
  | { type: 'jump'; index: number }
  | { type: 'queue.add'; ref: string }
  | { type: 'queue.remove'; index: number }
  | { type: 'queue.move'; from: number; to: number }
  | { type: 'leader.set'; username: string }
  | { type: 'dj.set'; username: string; on: boolean }
  | { type: 'suggest'; ref: string }
  | { type: 'close' }

export type RoomError = 'closed' | 'forbidden' | 'full' | 'not_member' | 'bad_index' | 'no_user' | 'noop'

export type RoomResult = { ok: true; room: Room } | { ok: false; error: RoomError }

/** Участников бесплатно и с Sonar Deep у хоста (решение владельца 2026-11-25; потом — `GET /config`). */
export const ROOM_MAX_MEMBERS = 4
export const ROOM_MAX_MEMBERS_DEEP = 8

/** Предел комнаты: решает подписка хоста, а не того, кто заходит. */
export const roomLimit = (hostHasDeep: boolean) => (hostHasDeep ? ROOM_MAX_MEMBERS_DEEP : ROOM_MAX_MEMBERS)

const isMember = (room: Room, username: string) => room.members.some((m) => m.username === username)

/** Роли участника, сильнейшая первой. Не участник — пустой список. */
export function rolesOf(room: Room, username: string): RoomRole[] {
  if (!isMember(room, username)) return []
  const roles: RoomRole[] = []
  if (room.host === username) roles.push('host')
  if (room.leader === username) roles.push('leader')
  if (room.djs.includes(username)) roles.push('dj')
  return roles.length ? roles : ['listener']
}

/** Главная роль — для подписи в списке участников. */
export function mainRole(room: Room, username: string): RoomRole | null {
  return rolesOf(room, username)[0] ?? null
}

/** Управляет воспроизведением: только лидер. */
export function canControl(room: Room, username: string): boolean {
  return isMember(room, username) && room.leader === username
}

/** Меняет очередь: хост, лидер и диджеи. */
export function canEditQueue(room: Room, username: string): boolean {
  return isMember(room, username) && (room.host === username || room.leader === username || room.djs.includes(username))
}

/** Раздаёт лидерство и диджеев: хост и действующий лидер. */
export function canManageRoles(room: Room, username: string): boolean {
  return isMember(room, username) && (room.host === username || room.leader === username)
}

/** Разрешена ли операция (без проверки аргументов — их проверяет `applyOp`). */
export function can(room: Room, username: string, op: RoomOp['type']): boolean {
  if (op === 'join') return !room.closed
  if (!isMember(room, username)) return false
  switch (op) {
    case 'leave':
    case 'suggest':
      return true
    case 'play':
    case 'pause':
    case 'seek':
    case 'next':
    case 'prev':
    case 'jump':
      return canControl(room, username)
    case 'queue.add':
    case 'queue.remove':
    case 'queue.move':
      return canEditQueue(room, username)
    case 'leader.set':
    case 'dj.set':
      return canManageRoles(room, username)
    case 'close':
      return room.host === username
  }
}

/** Позиция лидера сейчас по якорю (часы сервера). */
export function anchorPosition(room: Pick<Room, 'anchor' | 'playing'>, serverNow: number): number {
  const { server_ts_ms, position_ms } = room.anchor
  return room.playing ? position_ms + Math.max(0, serverNow - server_ts_ms) : position_ms
}

/** Через сколько после команды стартует новый трек: у каждого успевает прогреться поток. */
export const START_DELAY_MS = 1500

const fail = (error: RoomError): RoomResult => ({ ok: false, error })

/**
 * Применить операцию участника `by` в момент `serverNow`. Не меняет исходную комнату.
 * Всё, что прошло, увеличивает `rev` на 1; отказ — `rev` прежний.
 * `suggest` состояние не меняет (предложение уходит лидеру и диджеям отдельным сообщением) — `noop`.
 */
export function applyOp(room: Room, by: string, op: RoomOp, serverNow: number, maxMembers = ROOM_MAX_MEMBERS): RoomResult {
  if (room.closed) return fail('closed')
  if (op.type === 'join') {
    if (op.member.username !== by) return fail('forbidden')
    if (isMember(room, by)) return fail('noop')
    if (room.members.length >= maxMembers) return fail('full')
    return done(room, { members: [...room.members, op.member] })
  }
  if (!isMember(room, by)) return fail('not_member')
  if (!can(room, by, op.type)) return fail('forbidden')

  const at = (position_ms: number, playing = room.playing) => ({ anchor: { server_ts_ms: serverNow, position_ms: Math.max(0, position_ms) }, playing })
  /** Новый трек: начинается у всех через START_DELAY_MS, якорь — в будущем на нуле. */
  const startTrack = (pos: number) => ({ pos, anchor: { server_ts_ms: serverNow + START_DELAY_MS, position_ms: 0 } })

  switch (op.type) {
    case 'leave':
      return leave(room, by, serverNow)
    case 'play':
      if (room.playing && op.position_ms === undefined) return fail('noop')
      return done(room, at(op.position_ms ?? anchorPosition(room, serverNow), true))
    case 'pause':
      if (!room.playing) return fail('noop')
      return done(room, at(op.position_ms, false))
    case 'seek':
      return done(room, at(op.position_ms))
    case 'next':
      if (room.pos + 1 >= room.queue.length) return fail('bad_index')
      return done(room, startTrack(room.pos + 1))
    case 'prev':
      // как у плеера: дальше 3 с — в начало трека, иначе — предыдущий
      if (anchorPosition(room, serverNow) > 3000 || room.pos === 0) return done(room, at(0))
      return done(room, startTrack(room.pos - 1))
    case 'jump':
      if (!inRange(room.queue, op.index)) return fail('bad_index')
      return done(room, startTrack(op.index))
    case 'queue.add':
      return done(room, { queue: [...room.queue, { ref: op.ref, added_by: by }] })
    case 'queue.remove': {
      if (!inRange(room.queue, op.index) || op.index === room.pos) return fail('bad_index')
      const queue = room.queue.filter((_, i) => i !== op.index)
      return done(room, { queue, pos: op.index < room.pos ? room.pos - 1 : room.pos })
    }
    case 'queue.move': {
      if (!inRange(room.queue, op.from) || !inRange(room.queue, op.to)) return fail('bad_index')
      if (op.from === op.to) return fail('noop')
      const queue = [...room.queue]
      const [item] = queue.splice(op.from, 1)
      queue.splice(op.to, 0, item)
      return done(room, { queue, pos: movedPos(room.pos, op.from, op.to) })
    }
    case 'leader.set':
      if (!isMember(room, op.username)) return fail('no_user')
      if (room.leader === op.username) return fail('noop')
      // новый лидер подхватывает с той же точки — у слушателей ничего не дёргается
      return done(room, { leader: op.username, ...at(anchorPosition(room, serverNow)) })
    case 'dj.set': {
      if (!isMember(room, op.username)) return fail('no_user')
      const has = room.djs.includes(op.username)
      if (has === op.on) return fail('noop')
      return done(room, { djs: op.on ? [...room.djs, op.username] : room.djs.filter((u) => u !== op.username) })
    }
    case 'suggest':
      return fail('noop')
    case 'close':
      return done(room, { closed: true, playing: false })
  }
}

function leave(room: Room, by: string, serverNow: number): RoomResult {
  // ушёл хост — комната закрывается (как «Закрыть»): чужую комнату без хозяина никто не закроет
  if (room.host === by) return done(room, { closed: true, playing: false, members: room.members.filter((m) => m.username !== by) })
  const members = room.members.filter((m) => m.username !== by)
  const djs = room.djs.filter((u) => u !== by)
  if (room.leader !== by) return done(room, { members, djs })
  // ушёл лидер — пульт возвращается хосту с той же точки
  return done(room, {
    members,
    djs,
    leader: room.host,
    anchor: { server_ts_ms: serverNow, position_ms: anchorPosition(room, serverNow) },
  })
}

const inRange = (list: unknown[], i: number) => Number.isInteger(i) && i >= 0 && i < list.length

/** Куда уезжает играющий трек после перестановки `from → to`. */
export function movedPos(pos: number, from: number, to: number): number {
  if (from === pos) return to
  if (from < pos && to >= pos) return pos - 1
  if (from > pos && to <= pos) return pos + 1
  return pos
}

function done(room: Room, patch: Partial<Room>): RoomResult {
  return { ok: true, room: { ...room, ...patch, rev: room.rev + 1 } }
}

/** Принять снимок с сервера: только новее нашего. Старый или повтор — оставляем свой. */
export function acceptSnapshot(local: Room | null, incoming: Room): Room {
  if (!local || local.id !== incoming.id || incoming.rev > local.rev) return incoming
  return local
}

/** Пустая комната хоста: он же лидер и единственный участник. */
export function newRoom(id: string, host: RoomMember, queue: string[], serverNow: number): Room {
  return {
    id,
    host: host.username,
    leader: host.username,
    djs: [],
    members: [host],
    queue: queue.map((ref) => ({ ref, added_by: host.username })),
    pos: 0,
    // комната открывается на паузе: хост сам решает, когда начать
    playing: false,
    anchor: { server_ts_ms: serverNow, position_ms: 0 },
    rev: 1,
    closed: false,
  }
}
