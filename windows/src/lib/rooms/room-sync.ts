// Синхронизация слушателя с якорем комнаты (docs/ROOMS.md §2): смещение часов с сервером по пингам и
// решение «ничего / подстроить скорость / перемотать». Без сети и без плеера — только числа, чтобы
// одну и ту же логику прогонять на ПК (vitest) и iPhone (`Core/Rooms/RoomSync.swift`, XCTest).

import { anchorPosition, type Room } from './room-core'

/** Один пинг: `sent` и `received` — наши часы, `server` — часы сервера в момент ответа. */
export interface ClockSample {
  sent: number
  server: number
  received: number
}

export interface ClockEstimate {
  /** Прибавить к нашим часам, чтобы получить часы сервера. */
  offset_ms: number
  /** RTT лучшего пинга: чем меньше, тем точнее оценка (ошибка не больше половины). */
  rtt_ms: number
}

/**
 * Смещение часов как в NTP-упрощении: берём пинг с минимальным RTT (его меньше всего задержала сеть)
 * и считаем, что сервер ответил ровно посередине пути. Пусто или все пинги кривые — null.
 */
export function clockOffset(samples: readonly ClockSample[]): ClockEstimate | null {
  let best: ClockSample | null = null
  for (const s of samples) {
    if (!(s.received >= s.sent)) continue
    if (!best || s.received - s.sent < best.received - best.sent) best = s
  }
  if (!best) return null
  const rtt = best.received - best.sent
  return { offset_ms: Math.round(best.server - (best.sent + rtt / 2)), rtt_ms: rtt }
}

/** Пингов на оценку (спека — 4–5). */
export const CLOCK_SAMPLES = 5

/** Пороги подстройки. */
export const SYNC_OK_MS = 250
export const SYNC_NUDGE_MAX_MS = 2000
/** Насколько можно ускорить / замедлить звук, чтобы догнать: ±3 % на слух почти не заметно. */
export const SYNC_RATE = 0.03

export type SyncAction =
  | { kind: 'none'; drift_ms: number }
  | { kind: 'nudge'; rate: number; drift_ms: number }
  | { kind: 'seek'; position_ms: number; drift_ms: number }
  | { kind: 'wait'; start_in_ms: number }

/**
 * Что сделать слушателю. `drift_ms` > 0 — мы отстаём, < 0 — убежали вперёд.
 * - якорь в будущем (трек ещё не стартовал) — ждать;
 * - на паузе — встать ровно на позицию лидера, если ушли дальше допуска;
 * - отстаём или спешим меньше 250 мс — не трогать; до 2 с — скорость 1 ± 3 %; больше — перемотка.
 */
export function syncAction(room: Pick<Room, 'anchor' | 'playing'>, localPositionMs: number, serverNow: number): SyncAction {
  if (room.playing && room.anchor.server_ts_ms > serverNow) {
    return { kind: 'wait', start_in_ms: room.anchor.server_ts_ms - serverNow }
  }
  const target = anchorPosition(room, serverNow)
  const drift = Math.round(target - localPositionMs)
  const abs = Math.abs(drift)
  if (abs < SYNC_OK_MS) return { kind: 'none', drift_ms: drift }
  if (!room.playing || abs > SYNC_NUDGE_MAX_MS) return { kind: 'seek', position_ms: target, drift_ms: drift }
  return { kind: 'nudge', rate: drift > 0 ? 1 + SYNC_RATE : 1 - SYNC_RATE, drift_ms: drift }
}

/** Через сколько миллисекунд подстройка скоростью закроет расхождение (для подсказки и теста). */
export function nudgeDuration(driftMs: number, rate = SYNC_RATE): number {
  return Math.round(Math.abs(driftMs) / rate)
}

/** Часы сервера по нашим. */
export const serverTime = (localNow: number, clock: ClockEstimate | null) => localNow + (clock?.offset_ms ?? 0)
