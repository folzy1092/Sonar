import Foundation

/// «Сейчас играет» на сервере (SERVER_PROMPT этап 5, API.md §5 и §7) — порт `now_push.rs` ПК: снимок плеера уходит
/// `PUT /player/state` вместе с названием трека, из этого сервер собирает `GET /oauth/now` для selfbot.
/// **Тело менять в обоих местах.**
enum NowPush {
    /// Очередь серверу — окном вокруг текущего трека: длинная волна иначе не влезет в 64 КБ `PlayerState`.
    static let queueBefore = 50
    static let queueMax = 200

    /// Что показать в `/oauth/now`: таблицу `tracks` на сервере заполняет только перенос из Dotify.
    struct Meta: Encodable, Equatable, Sendable {
        var title: String
        var artist: String
        var coverURL: String?
        var durationMs: Int

        enum CodingKeys: String, CodingKey {
            case title, artist
            case coverURL = "cover_url"
            case durationMs = "duration_ms"
        }
    }

    /// `PlayerState` из API.md §5 (+ необязательный `track`).
    struct State: Encodable, Equatable, Sendable {
        var deviceId: String
        var ref: String?
        var context: String?
        var isPlaying: Bool
        var positionMs: Int
        var queue: [String]
        var queueIndex: Int?
        var shuffle: Bool
        var repeatMode: String
        var clientTs: Int
        var track: Meta?

        enum CodingKeys: String, CodingKey {
            case ref, context, queue, shuffle, track
            case deviceId = "device_id"
            case isPlaying = "is_playing"
            case positionMs = "position_ms"
            case queueIndex = "queue_index"
            case repeatMode = "repeat"
            case clientTs = "client_ts"
        }
    }

    /// Снимок плеера → тело. Ничего не играет (`nil` или битый снимок) — `ref` пустой, сервер покажет «остановлено».
    static func state(_ snap: PlaybackSnapshot?, isPlaying: Bool, deviceId: String, now: Date) -> State {
        let ts = Int(now.timeIntervalSince1970 * 1000)
        guard let snap, let current = snap.current else {
            return State(deviceId: deviceId, ref: nil, context: nil, isPlaying: false, positionMs: 0, queue: [],
                         queueIndex: nil, shuffle: false, repeatMode: RepeatMode.off.rawValue, clientTs: ts, track: nil)
        }
        let refs = snap.order.compactMap { snap.tracks.indices.contains($0) ? snap.tracks[$0].ref : nil }
        let start = max(0, snap.pos - queueBefore)
        let window = Array(refs[start ..< min(refs.count, start + queueMax)])
        return State(deviceId: deviceId, ref: current.ref, context: snap.context.isEmpty ? nil : snap.context,
                     isPlaying: isPlaying, positionMs: max(0, Int(snap.position * 1000)), queue: window,
                     queueIndex: snap.pos - start, shuffle: snap.shuffle, repeatMode: snap.repeatMode.rawValue,
                     clientTs: ts,
                     track: Meta(title: current.title, artist: current.artist, coverURL: current.coverURL,
                                 durationMs: current.durationMs))
    }
}

/// Отправка по одной: пока идёт запрос, новые состояния копятся, и уходит только последнее — старое не перетрёт новое.
actor NowPusher {
    static let shared = NowPusher()

    private var pending: (NowPush.State, APIClient)?
    private var sending = false

    func submit(_ state: NowPush.State, client: APIClient) async {
        pending = (state, client)
        guard !sending else { return }
        sending = true
        defer { sending = false }
        while let (next, client) = pending {
            pending = nil
            do {
                try await client.call("PUT", "player/state", body: next)
            } catch let error as APIError where error.code == "network" {
                continue // нет сети — следующий снимок через 10 с, журнал не засоряем
            } catch {
                // 401 и прочее: выход из аккаунта ловит синк, значений в журнал не пишем
                CrashLog.warn("«сейчас играет» на сервер не ушло")
            }
        }
    }
}
