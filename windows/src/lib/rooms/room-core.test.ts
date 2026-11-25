import { describe, expect, it } from 'vitest'
import { acceptSnapshot, anchorPosition, applyOp, can, mainRole, movedPos, newRoom, rolesOf, START_DELAY_MS, type Room, type RoomOp } from './room-core'

const m = (username: string) => ({ username, display_name: null, avatar_url: null })

function room(): Room {
  let r = newRoom('r1', m('host'), ['sc:1', 'ym:2', 'sc:3'], 1000)
  for (const u of ['dj', 'ann']) r = ok(applyOp(r, u, { type: 'join', member: m(u) }, 1000))
  return ok(applyOp(r, 'host', { type: 'dj.set', username: 'dj', on: true }, 1000))
}

function ok(res: ReturnType<typeof applyOp>): Room {
  if (!res.ok) throw new Error(res.error)
  return res.room
}

const err = (r: Room, by: string, op: RoomOp, now = 2000) => {
  const res = applyOp(r, by, op, now)
  return res.ok ? 'ok' : res.error
}

describe('комната: роли', () => {
  it('хост — он же лидер, диджей, остальные — слушатели, чужой — никто', () => {
    const r = room()
    expect(rolesOf(r, 'host')).toEqual(['host', 'leader'])
    expect(mainRole(r, 'dj')).toBe('dj')
    expect(mainRole(r, 'ann')).toBe('listener')
    expect(rolesOf(r, 'stranger')).toEqual([])
  })

  it('права: пульт — у лидера, очередь — у хоста/лидера/диджеев, закрыть — только хост', () => {
    const r = room()
    expect(can(r, 'host', 'play')).toBe(true)
    expect(can(r, 'dj', 'play')).toBe(false)
    expect(can(r, 'dj', 'queue.add')).toBe(true)
    expect(can(r, 'ann', 'queue.add')).toBe(false)
    expect(can(r, 'ann', 'suggest')).toBe(true)
    expect(can(r, 'dj', 'close')).toBe(false)
    expect(can(r, 'stranger', 'suggest')).toBe(false)
  })

  it('открывается на паузе, rev растёт только на принятых операциях', () => {
    const r = room()
    expect(r.playing).toBe(false)
    const rev = r.rev
    expect(err(r, 'ann', { type: 'play' })).toBe('forbidden')
    const played = ok(applyOp(r, 'host', { type: 'play' }, 2000))
    expect(played.rev).toBe(rev + 1)
    expect(err(played, 'host', { type: 'play' })).toBe('noop')
  })

  it('передача лидера: новый лидер управляет, старый — нет, позиция не прыгает', () => {
    const r = ok(applyOp(room(), 'host', { type: 'play', position_ms: 10_000 }, 2000))
    const passed = ok(applyOp(r, 'host', { type: 'leader.set', username: 'ann' }, 5000))
    expect(passed.leader).toBe('ann')
    expect(anchorPosition(passed, 5000)).toBe(13_000)
    expect(can(passed, 'ann', 'pause')).toBe(true)
    expect(can(passed, 'host', 'pause')).toBe(false)
    // хост всё равно раздаёт роли
    expect(can(passed, 'host', 'leader.set')).toBe(true)
    expect(err(passed, 'host', { type: 'leader.set', username: 'nope' })).toBe('no_user')
  })

  it('ушёл лидер — пульт у хоста; ушёл хост — комната закрыта', () => {
    const r = ok(applyOp(room(), 'host', { type: 'leader.set', username: 'dj' }, 2000))
    const left = ok(applyOp(r, 'dj', { type: 'leave' }, 3000))
    expect(left.leader).toBe('host')
    expect(left.djs).toEqual([])
    const closed = ok(applyOp(left, 'host', { type: 'leave' }, 3000))
    expect(closed.closed).toBe(true)
    expect(err(closed, 'ann', { type: 'suggest', ref: 'sc:9' })).toBe('closed')
  })

  it('лимит участников и повторный вход', () => {
    let r = room()
    expect(err(r, 'ann', { type: 'join', member: m('ann') })).toBe('noop')
    expect(err(r, 'x', { type: 'join', member: m('y') })).toBe('forbidden')
    r = ok(applyOp(r, 'n4', { type: 'join', member: m('n4') }, 1, 4))
    expect(applyOp(r, 'n5', { type: 'join', member: m('n5') }, 1, 4)).toEqual({ ok: false, error: 'full' })
  })
})

describe('комната: воспроизведение и очередь', () => {
  it('пауза фиксирует позицию, play продолжает с неё', () => {
    let r = ok(applyOp(room(), 'host', { type: 'play', position_ms: 0 }, 1000))
    expect(anchorPosition(r, 4000)).toBe(3000)
    r = ok(applyOp(r, 'host', { type: 'pause', position_ms: 3000 }, 4000))
    expect(anchorPosition(r, 9000)).toBe(3000)
    r = ok(applyOp(r, 'host', { type: 'play' }, 9000))
    expect(anchorPosition(r, 10_000)).toBe(4000)
  })

  it('следующий трек стартует у всех через задержку прогрева', () => {
    const r = ok(applyOp(ok(applyOp(room(), 'host', { type: 'play' }, 1000)), 'host', { type: 'next' }, 5000))
    expect(r.pos).toBe(1)
    expect(r.anchor).toEqual({ server_ts_ms: 5000 + START_DELAY_MS, position_ms: 0 })
    expect(anchorPosition(r, 5000)).toBe(0)
    expect(anchorPosition(r, 5000 + START_DELAY_MS + 200)).toBe(200)
  })

  it('«назад» дальше 3 с — в начало трека, иначе — предыдущий; за краем — bad_index', () => {
    let r = ok(applyOp(room(), 'host', { type: 'jump', index: 2 }, 0))
    r = ok(applyOp(r, 'host', { type: 'seek', position_ms: 60_000 }, 1000))
    const restart = ok(applyOp(r, 'host', { type: 'prev' }, 1000))
    expect([restart.pos, restart.anchor.position_ms]).toEqual([2, 0])
    expect(ok(applyOp(restart, 'host', { type: 'prev' }, 1000)).pos).toBe(1)
    expect(err(r, 'host', { type: 'next' })).toBe('bad_index')
  })

  it('диджей добавляет с подписью, играющий трек убрать нельзя, перестановка держит играющий', () => {
    let r = ok(applyOp(room(), 'host', { type: 'jump', index: 1 }, 0))
    r = ok(applyOp(r, 'dj', { type: 'queue.add', ref: 'sc:9' }, 0))
    expect(r.queue.at(-1)).toEqual({ ref: 'sc:9', added_by: 'dj' })
    expect(err(r, 'dj', { type: 'queue.remove', index: 1 })).toBe('bad_index')
    r = ok(applyOp(r, 'dj', { type: 'queue.remove', index: 0 }, 0))
    expect([r.queue[r.pos].ref, r.pos]).toEqual(['ym:2', 0])
    r = ok(applyOp(r, 'dj', { type: 'queue.move', from: 2, to: 0 }, 0))
    expect(r.queue.map((i) => i.ref)).toEqual(['sc:9', 'ym:2', 'sc:3'])
    expect(r.queue[r.pos].ref).toBe('ym:2')
  })

  it('movedPos: все случаи', () => {
    expect(movedPos(2, 2, 0)).toBe(0)
    expect(movedPos(2, 0, 3)).toBe(1)
    expect(movedPos(2, 4, 1)).toBe(3)
    expect(movedPos(2, 3, 4)).toBe(2)
  })

  it('suggest ничего не меняет, close — только хост', () => {
    const r = room()
    expect(err(r, 'ann', { type: 'suggest', ref: 'sc:7' })).toBe('noop')
    expect(err(r, 'dj', { type: 'close' })).toBe('forbidden')
    expect(ok(applyOp(r, 'host', { type: 'close' }, 0)).closed).toBe(true)
  })

  it('снимок с сервера принимается только новее', () => {
    const r = room()
    const newer = { ...r, rev: r.rev + 1, pos: 2 }
    expect(acceptSnapshot(r, newer)).toBe(newer)
    expect(acceptSnapshot(newer, r)).toBe(newer)
    expect(acceptSnapshot(null, r)).toBe(r)
    expect(acceptSnapshot(r, { ...r, id: 'other', rev: 0 }).id).toBe('other')
  })
})
