import Foundation

// Синхронизация слушателя с якорем комнаты (docs/ROOMS.md §2) — порт ПК `windows/src/lib/rooms/room-sync.ts`:
// смещение часов по пингам и решение «ничего / подстроить скорость / перемотать». Только числа, без плеера.

/// Один пинг: `sent` и `received` — наши часы, `server` — часы сервера в момент ответа (мс).
struct ClockSample: Equatable, Sendable {
    var sent: Int
    var server: Int
    var received: Int
}

struct ClockEstimate: Equatable, Sendable {
    /// Прибавить к нашим часам, чтобы получить часы сервера.
    var offset: Int
    /// RTT лучшего пинга: ошибка оценки не больше половины.
    var rtt: Int
}

enum SyncAction: Equatable, Sendable {
    case none(drift: Int)
    case nudge(rate: Double, drift: Int)
    case seek(position: Int, drift: Int)
    case wait(startIn: Int)
}

enum RoomSync {
    static let clockSamples = 5
    static let okMs = 250
    static let nudgeMaxMs = 2000
    /// ±3 %: на слух почти не заметно.
    static let rate = 0.03

    /// Пинг с минимальным RTT, сервер ответил посередине пути. Пусто или все кривые — nil.
    static func clockOffset(_ samples: [ClockSample]) -> ClockEstimate? {
        let valid = samples.filter { $0.received >= $0.sent }
        guard let best = valid.min(by: { $0.received - $0.sent < $1.received - $1.sent }) else { return nil }
        let rtt = best.received - best.sent
        let offset = (Double(best.server) - (Double(best.sent) + Double(rtt) / 2)).rounded()
        return ClockEstimate(offset: Int(offset), rtt: rtt)
    }

    static func serverTime(localNow: Int, clock: ClockEstimate?) -> Int { localNow + (clock?.offset ?? 0) }

    /// Что сделать слушателю; `drift` > 0 — мы отстаём, < 0 — убежали вперёд.
    static func action(playing: Bool, anchor: RoomAnchor, localPosition: Int, serverNow: Int) -> SyncAction {
        if playing && anchor.serverTs > serverNow { return .wait(startIn: anchor.serverTs - serverNow) }
        let target = RoomCore.anchorPosition(playing: playing, anchor: anchor, serverNow: serverNow)
        let drift = target - localPosition
        if abs(drift) < okMs { return .none(drift: drift) }
        if !playing || abs(drift) > nudgeMaxMs { return .seek(position: target, drift: drift) }
        return .nudge(rate: drift > 0 ? 1 + rate : 1 - rate, drift: drift)
    }

    static func action(_ room: Room, localPosition: Int, serverNow: Int) -> SyncAction {
        action(playing: room.playing, anchor: room.anchor, localPosition: localPosition, serverNow: serverNow)
    }

    /// За сколько мс подстройка скоростью закроет расхождение.
    static func nudgeDuration(_ drift: Int, rate: Double = rate) -> Int {
        Int((Double(abs(drift)) / rate).rounded())
    }
}
