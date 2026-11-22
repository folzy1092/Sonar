import Foundation

// Синхронизация (API.md §6, SPEC §3.10) — порт Windows `store/sync.rs` + `sync.rs`. Тот же формат
// операций и те же правила: `op_id` детерминирован, `value: null` — удалено, своё неотправленное
// важнее пришедшего, настройки — «побеждает позднее» по `client_ts` (решает сервер).

/// Строка синка — (тип, ключ): `like` / `sc:1`, `setting` / `appearance.cover_theme`.
struct SyncKey: Hashable, Codable, Sendable, Comparable {
    var type: String
    var key: String

    init(_ type: String, _ key: String) {
        self.type = type
        self.key = key
    }

    static func < (a: SyncKey, b: SyncKey) -> Bool {
        (a.type, a.key) < (b.type, b.key)
    }
}

/// Операция `POST /sync/push`. `value == .null` — удалено (tombstone).
struct SyncOp: Codable, Equatable, Sendable {
    /// `<device_id>:<type>:<key>:<локальный rev>` — повтор после сбоя сети сервер не применит дважды.
    var opId: String
    var type: String
    var key: String
    var value: JSONValue
    var clientTs: Int64
    /// Локальный rev строки — для сдвига `pushedRev`; на сервер не едет.
    var rev: Int

    enum CodingKeys: String, CodingKey {
        case type, key, value
        case opId = "op_id"
        case clientTs = "client_ts"
    }

    init(opId: String, type: String, key: String, value: JSONValue, clientTs: Int64, rev: Int) {
        self.opId = opId
        self.type = type
        self.key = key
        self.value = value
        self.clientTs = clientTs
        self.rev = rev
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        opId = try c.decode(String.self, forKey: .opId)
        type = try c.decode(String.self, forKey: .type)
        key = try c.decode(String.self, forKey: .key)
        value = try c.decodeIfPresent(JSONValue.self, forKey: .value) ?? .null
        clientTs = try c.decode(Int64.self, forKey: .clientTs)
        rev = 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(opId, forKey: .opId)
        try c.encode(type, forKey: .type)
        try c.encode(key, forKey: .key)
        try c.encode(value, forKey: .value) // null пишется явно
        try c.encode(clientTs, forKey: .clientTs)
    }
}

/// Изменение из `GET /sync/pull`.
struct SyncChange: Codable, Equatable, Sendable {
    var type: String
    var key: String
    var value: JSONValue
    var rev: Int

    init(type: String, key: String, value: JSONValue, rev: Int) {
        self.type = type
        self.key = key
        self.value = value
        self.rev = rev
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        key = try c.decode(String.self, forKey: .key)
        value = try c.decodeIfPresent(JSONValue.self, forKey: .value) ?? .null
        rev = try c.decode(Int.self, forKey: .rev)
    }
}

struct SyncPushReply: Codable, Equatable, Sendable {
    var applied: [String]
}

struct SyncPullReply: Codable, Equatable, Sendable {
    var rev: Int
    var changes: [SyncChange]
}

/// Прослушивание для `POST /plays`.
struct PlayUpload: Codable, Equatable, Sendable {
    var ref: String
    var playedAt: Int64
    var listenedMs: Int
    var context: String?

    enum CodingKeys: String, CodingKey {
        case ref, context
        case playedAt = "played_at"
        case listenedMs = "listened_ms"
    }
}

/// Что отправить: операции по возрастанию rev и до какого rev они покрывают всё.
struct PushPlan: Equatable, Sendable {
    var ops: [SyncOp]
    var upto: Int
}

/// Итог одного обмена.
struct SyncReport: Equatable, Sendable {
    var pushed = 0
    var pulled = 0
    var plays = 0
}

enum SyncError: LocalizedError, Equatable {
    /// Сервер подтвердил не все операции — курсор не сдвигаем, повторим.
    case partial(applied: Int, sent: Int)

    var errorDescription: String? {
        switch self {
        case let .partial(applied, sent): "Сервер принял не все изменения (\(applied) из \(sent))"
        }
    }
}

/// Какие настройки едут (SETTINGS.md, колонка sync): всё, кроме устройства — как `setting_syncs` на ПК.
enum SyncPolicy {
    static let localSettings: Set<String> = [
        "general.language",
        "audio.quality",
        "audio.sc_via_yandex",
        "audio.output_device",
        "appearance.scale_window",
        "appearance.scale_fullscreen",
        "player.volume",
        "audio.eq",
        "player.speed_mode",
        "player.tempo",
        "player.pitch_linked",
        "player.pitch",
        "player.reverb",
        "obs.token",
        "lyrics.view",
    ]
    /// `server.` и `account.` — адрес и флаг сервера на этом телефоне.
    static let localPrefixes = ["system.", "update.", "storage.", "sync.", "server.", "account."]

    static func settingSyncs(_ key: String) -> Bool {
        !localSettings.contains(key) && !localPrefixes.contains { key.hasPrefix($0) }
    }
}

extension JSONValue {
    /// Из любого Encodable (карточка трека в лайке).
    static func encode<T: Encodable>(_ value: T) -> JSONValue {
        guard let data = try? JSONEncoder().encode(value), let json = try? JSONValue(data: data) else { return .null }
        return json
    }

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard !isNull, let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    var int64: Int64? { int.map(Int64.init) ?? number.map { Int64($0) } }
}
