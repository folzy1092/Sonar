import Foundation

// Комната совместного прослушивания (docs/ROOMS.md) — порт ПК `windows/src/lib/rooms/room-core.ts`: состояние,
// роли и права, операции с `rev`. Без сети: до сервера им живёт демо-экран, потом тем же правилам следует сервер.
// Правила менять в обоих местах, в docs/ROOMS.md и в тестах (`RoomCoreTests`).

struct RoomMember: Codable, Hashable, Sendable {
    var username: String
    var displayName: String?
    var avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }
}

struct RoomItem: Codable, Hashable, Sendable {
    var ref: String
    var addedBy: String

    enum CodingKeys: String, CodingKey {
        case ref
        case addedBy = "added_by"
    }
}

/// Якорь времени: в момент `serverTs` (часы сервера, мс) лидер был на `position` (мс).
struct RoomAnchor: Codable, Hashable, Sendable {
    var serverTs: Int
    var position: Int

    enum CodingKeys: String, CodingKey {
        case serverTs = "server_ts_ms"
        case position = "position_ms"
    }
}

struct Room: Codable, Hashable, Sendable {
    var id: String
    /// Создал комнату, единственный может её закрыть.
    var host: String
    /// Чьи Play / пауза / перемотка главные.
    var leader: String
    /// Могут менять очередь (хост и лидер — всегда, без записи здесь).
    var djs: [String]
    var members: [RoomMember]
    var queue: [RoomItem]
    /// Индекс играющего трека в `queue`.
    var pos: Int
    var playing: Bool
    var anchor: RoomAnchor
    var rev: Int
    var closed: Bool

    func isMember(_ username: String) -> Bool { members.contains { $0.username == username } }
}

enum RoomRole: String, Sendable {
    case host, leader, dj, listener

    /// Ключ перевода.
    var title: String {
        switch self {
        case .host: "Хост"
        case .leader: "Лидер"
        case .dj: "Диджей"
        case .listener: "Слушатель"
        }
    }
}

enum RoomOp: Equatable, Sendable {
    case join(RoomMember)
    case leave
    case play(position: Int?)
    case pause(position: Int)
    case seek(position: Int)
    case next
    case prev
    case jump(index: Int)
    case queueAdd(ref: String)
    case queueRemove(index: Int)
    case queueMove(from: Int, to: Int)
    case leaderSet(username: String)
    case djSet(username: String, on: Bool)
    case suggest(ref: String)
    case close

    /// Имя операции в протоколе (docs/API.md «Комнаты»).
    var name: String {
        switch self {
        case .join: "join"
        case .leave: "leave"
        case .play: "play"
        case .pause: "pause"
        case .seek: "seek"
        case .next: "next"
        case .prev: "prev"
        case .jump: "jump"
        case .queueAdd: "queue.add"
        case .queueRemove: "queue.remove"
        case .queueMove: "queue.move"
        case .leaderSet: "leader.set"
        case .djSet: "dj.set"
        case .suggest: "suggest"
        case .close: "close"
        }
    }
}

enum RoomError: String, Error, Sendable {
    case closed, forbidden, full, notMember = "not_member", badIndex = "bad_index", noUser = "no_user", noop

    /// Ключ перевода для всплывашки; `noop` молчит.
    var message: String? {
        switch self {
        case .closed: "Комната закрыта"
        case .forbidden: "У этой роли нет на это прав"
        case .full: "В комнате нет мест"
        case .notMember: "Ты не в комнате"
        case .badIndex: "Так нельзя: этот трек играет или очередь кончилась"
        case .noUser: "Этого участника уже нет в комнате"
        case .noop: nil
        }
    }
}

enum RoomCore {
    /// Участников по умолчанию (потом — `GET /config` `rooms.max_members`).
    static let maxMembers = 8
    /// Через сколько после команды стартует новый трек: у каждого успевает прогреться поток.
    static let startDelayMs = 1500

    /// Роли участника, сильнейшая первой; не участник — пусто.
    static func roles(_ room: Room, _ username: String) -> [RoomRole] {
        guard room.isMember(username) else { return [] }
        var out: [RoomRole] = []
        if room.host == username { out.append(.host) }
        if room.leader == username { out.append(.leader) }
        if room.djs.contains(username) { out.append(.dj) }
        return out.isEmpty ? [.listener] : out
    }

    static func mainRole(_ room: Room, _ username: String) -> RoomRole? { roles(room, username).first }

    static func canControl(_ room: Room, _ username: String) -> Bool {
        room.isMember(username) && room.leader == username
    }

    static func canEditQueue(_ room: Room, _ username: String) -> Bool {
        room.isMember(username) && (room.host == username || room.leader == username || room.djs.contains(username))
    }

    static func canManageRoles(_ room: Room, _ username: String) -> Bool {
        room.isMember(username) && (room.host == username || room.leader == username)
    }

    static func can(_ room: Room, _ username: String, _ op: RoomOp) -> Bool {
        if case .join = op { return !room.closed }
        guard room.isMember(username) else { return false }
        switch op {
        case .join: return !room.closed
        case .leave, .suggest: return true
        case .play, .pause, .seek, .next, .prev, .jump: return canControl(room, username)
        case .queueAdd, .queueRemove, .queueMove: return canEditQueue(room, username)
        case .leaderSet, .djSet: return canManageRoles(room, username)
        case .close: return room.host == username
        }
    }

    /// Позиция лидера сейчас по якорю (часы сервера).
    static func anchorPosition(playing: Bool, anchor: RoomAnchor, serverNow: Int) -> Int {
        playing ? anchor.position + max(0, serverNow - anchor.serverTs) : anchor.position
    }

    static func anchorPosition(_ room: Room, serverNow: Int) -> Int {
        anchorPosition(playing: room.playing, anchor: room.anchor, serverNow: serverNow)
    }

    /// Применить операцию участника `by` в момент `serverNow`. Принятая — `rev + 1`, отказ — ошибка.
    static func apply(_ room: Room, by: String, _ op: RoomOp, serverNow: Int, maxMembers: Int = maxMembers) -> Result<Room, RoomError> {
        if room.closed { return .failure(.closed) }
        if case let .join(member) = op {
            if member.username != by { return .failure(.forbidden) }
            if room.isMember(by) { return .failure(.noop) }
            if room.members.count >= maxMembers { return .failure(.full) }
            return done(room) { $0.members.append(member) }
        }
        guard room.isMember(by) else { return .failure(.notMember) }
        guard can(room, by, op) else { return .failure(.forbidden) }

        func at(_ position: Int, playing: Bool? = nil) -> (inout Room) -> Void {
            { r in
                r.anchor = RoomAnchor(serverTs: serverNow, position: max(0, position))
                if let playing { r.playing = playing }
            }
        }
        func startTrack(_ pos: Int) -> (inout Room) -> Void {
            { r in
                r.pos = pos
                r.anchor = RoomAnchor(serverTs: serverNow + startDelayMs, position: 0)
            }
        }
        let now = anchorPosition(room, serverNow: serverNow)

        switch op {
        case .join:
            return .failure(.noop)
        case .leave:
            return leave(room, by: by, serverNow: serverNow)
        case let .play(position):
            if room.playing && position == nil { return .failure(.noop) }
            return done(room, at(position ?? now, playing: true))
        case let .pause(position):
            if !room.playing { return .failure(.noop) }
            return done(room, at(position, playing: false))
        case let .seek(position):
            return done(room, at(position))
        case .next:
            if room.pos + 1 >= room.queue.count { return .failure(.badIndex) }
            return done(room, startTrack(room.pos + 1))
        case .prev:
            // как у плеера: дальше 3 с — в начало трека, иначе — предыдущий
            if now > 3000 || room.pos == 0 { return done(room, at(0)) }
            return done(room, startTrack(room.pos - 1))
        case let .jump(index):
            guard room.queue.indices.contains(index) else { return .failure(.badIndex) }
            return done(room, startTrack(index))
        case let .queueAdd(ref):
            return done(room) { $0.queue.append(RoomItem(ref: ref, addedBy: by)) }
        case let .queueRemove(index):
            guard room.queue.indices.contains(index), index != room.pos else { return .failure(.badIndex) }
            return done(room) { r in
                r.queue.remove(at: index)
                if index < r.pos { r.pos -= 1 }
            }
        case let .queueMove(from, to):
            guard room.queue.indices.contains(from), room.queue.indices.contains(to) else { return .failure(.badIndex) }
            if from == to { return .failure(.noop) }
            return done(room) { r in
                let item = r.queue.remove(at: from)
                r.queue.insert(item, at: to)
                r.pos = movedPos(r.pos, from: from, to: to)
            }
        case let .leaderSet(username):
            guard room.isMember(username) else { return .failure(.noUser) }
            if room.leader == username { return .failure(.noop) }
            // новый лидер подхватывает с той же точки — у слушателей ничего не дёргается
            return done(room) { r in
                r.leader = username
                r.anchor = RoomAnchor(serverTs: serverNow, position: now)
            }
        case let .djSet(username, on):
            guard room.isMember(username) else { return .failure(.noUser) }
            if room.djs.contains(username) == on { return .failure(.noop) }
            return done(room) { r in
                if on { r.djs.append(username) } else { r.djs.removeAll { $0 == username } }
            }
        case .suggest:
            return .failure(.noop)
        case .close:
            return done(room) { r in
                r.closed = true
                r.playing = false
            }
        }
    }

    private static func leave(_ room: Room, by: String, serverNow: Int) -> Result<Room, RoomError> {
        let now = anchorPosition(room, serverNow: serverNow)
        return done(room) { r in
            r.members.removeAll { $0.username == by }
            // ушёл хост — комната закрывается: чужую комнату без хозяина никто не закроет
            if room.host == by {
                r.closed = true
                r.playing = false
                return
            }
            r.djs.removeAll { $0 == by }
            // ушёл лидер — пульт возвращается хосту с той же точки
            if room.leader == by {
                r.leader = room.host
                r.anchor = RoomAnchor(serverTs: serverNow, position: now)
            }
        }
    }

    /// Куда уезжает играющий трек после перестановки `from → to`.
    static func movedPos(_ pos: Int, from: Int, to: Int) -> Int {
        if from == pos { return to }
        if from < pos && to >= pos { return pos - 1 }
        if from > pos && to <= pos { return pos + 1 }
        return pos
    }

    private static func done(_ room: Room, _ patch: (inout Room) -> Void) -> Result<Room, RoomError> {
        var next = room
        patch(&next)
        next.rev = room.rev + 1
        return .success(next)
    }

    /// Принять снимок с сервера: только новее нашего.
    static func accept(local: Room?, incoming: Room) -> Room {
        guard let local, local.id == incoming.id, incoming.rev <= local.rev else { return incoming }
        return local
    }

    /// Новая комната хоста: он же лидер; открывается на паузе.
    static func newRoom(id: String, host: RoomMember, queue: [String], serverNow: Int) -> Room {
        Room(id: id, host: host.username, leader: host.username, djs: [], members: [host],
             queue: queue.map { RoomItem(ref: $0, addedBy: host.username) }, pos: 0, playing: false,
             anchor: RoomAnchor(serverTs: serverNow, position: 0), rev: 1, closed: false)
    }
}
