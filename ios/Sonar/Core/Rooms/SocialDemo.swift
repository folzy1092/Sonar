import Foundation

// Демо «Вместе» до сервера — порт ПК `pages/social/social-demo.ts`: комната и чат из моих Любимых и двух выдуманных
// друзей. Всё живёт в памяти экрана, никуда не уходит; правила — настоящие (`RoomCore`, `DMCore`).

enum SocialDemo {
    static let friend = "demo_friend"
    static let friend2 = "demo_friend2"
    static let roomID = "demo_room"

    static func members(me: RoomMember, friendName: String, friend2Name: String) -> [RoomMember] {
        [me, RoomMember(username: friend, displayName: friendName), RoomMember(username: friend2, displayName: friend2Name)]
    }

    /// Я — хост, первый друг — диджей, второй — слушатель; очередь — до 8 Любимых, играет первый.
    static func room(members: [RoomMember], tracks: [Track], now: Int) -> Room {
        let me = members[0], friendM = members[1], friend2M = members[2]
        var room = RoomCore.newRoom(id: roomID, host: me, queue: [], serverNow: now)
        func step(_ by: String, _ op: RoomOp) {
            if case let .success(next) = RoomCore.apply(room, by: by, op, serverNow: now) { room = next }
        }
        step(friendM.username, .join(friendM))
        step(friend2M.username, .join(friend2M))
        step(me.username, .djSet(username: friendM.username, on: true))
        for (i, track) in tracks.prefix(8).enumerated() {
            step(i % 3 == 1 ? friendM.username : me.username, .queueAdd(ref: track.ref))
        }
        step(me.username, .play(position: min(42_000, (tracks.first?.durationMs ?? 0) / 3)))
        return room
    }

    struct Lines: Sendable {
        var hey: String
        var fire: String
        var join: String
        var room: String
    }

    static func track(_ t: Track) -> DMAttachment {
        .track(ref: t.ref, title: t.title, artist: t.artist, coverURL: t.coverURL)
    }

    /// Личный чат с другом (трек, ответ, приглашение) и чат комнаты.
    static func chat(me: String, tracks: [Track], roomTitle: String, lines: Lines, now: Int) -> (threads: [DMThread], messages: [DMMessage]) {
        let min = 60_000
        let threads = [
            DMThread(id: "dm_friend", peer: friend, roomID: nil, peerReadAt: now - 10 * min, myReadAt: now - 20 * min),
            DMThread(id: "dm_room", peer: nil, roomID: roomID, peerReadAt: now, myReadAt: now),
        ]
        func msg(_ id: String, _ thread: String, _ from: String, _ ago: Int, _ text: String,
                 _ attachments: [DMAttachment] = [], reply: String? = nil) -> DMMessage {
            DMMessage(id: id, threadID: thread, from: from, text: text, attachments: attachments, replyTo: reply, sentAt: now - ago * min)
        }
        var messages = [
            msg("m1", "dm_friend", friend, 42, lines.hey, tracks.first.map { [track($0)] } ?? []),
            msg("m2", "dm_friend", me, 30, lines.fire, reply: "m1"),
            msg("m3", "dm_friend", me, 12, lines.join, [.room(roomID: roomID, host: me, title: roomTitle)]),
        ]
        if tracks.count > 1 { messages.append(msg("m4", "dm_friend", friend, 8, "", [track(tracks[1])])) }
        messages.append(msg("r1", "dm_room", friend2, 5, lines.room))
        return (threads, messages)
    }
}
