import Foundation

/// Синк с ПК по Wi‑Fi, пока нет сервера Sonar (docs/API.md «Пульт» → «Синк по Wi‑Fi»). ПК отвечает как
/// сервер §6, но по связи пульта: `sync_push` / `sync_pull` и ответ тем же типом с `re`. Здесь — чистая
/// часть: сообщения, выбор стороны и какой ПК помним. Связь — `LANSyncTransport`.
enum RemoteSync {
    /// Ответ `sync_pull` ПК режет по ~512 КБ; берём с запасом, но не больше `MAX_SYNC_MESSAGE` ПК.
    static let maxMessage = 1024 * 1024
    /// Защита от бесконечного `more`: столько страниц `sync_pull` за один обмен.
    static let maxPages = 200

    // MARK: - Телефон → ПК

    private struct Envelope<Body: Encodable>: Encodable {
        let v: Int
        let type: String
        let id: String
        let body: Body
    }

    private struct PushBody: Encodable { let ops: [SyncOp] }
    private struct PullBody: Encodable { let since: Int }

    static func push(_ ops: [SyncOp], id: String) -> String {
        encode(type: "sync_push", id: id, body: PushBody(ops: ops))
    }

    static func pull(since: Int, id: String) -> String {
        encode(type: "sync_pull", id: id, body: PullBody(since: since))
    }

    private static func encode<B: Encodable>(type: String, id: String, body: B) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let envelope = Envelope(v: RemoteProtocol.version, type: type, id: id, body: body)
        guard let data = try? encoder.encode(envelope) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// `sync_pull` страницами: пока ПК отвечает `more`, просим дальше с нового `rev`; всё складываем в один
    /// ответ, как у сервера. ПК, который не двигает `rev`, не держит нас в цикле.
    /// `isolation` — страницы просит тот же актор, что вызвал (транспорт на главном): замыкание никуда не переходит.
    static func pullAll(
        since: Int,
        isolation: isolated (any Actor)? = #isolation,
        page: (Int) async throws -> (SyncPullReply, more: Bool)
    ) async throws -> SyncPullReply {
        var rev = since
        var changes: [SyncChange] = []
        for _ in 0..<maxPages {
            let (reply, more) = try await page(rev)
            changes += reply.changes
            let moved = reply.rev > rev
            rev = max(rev, reply.rev)
            if !more || !moved { break }
        }
        return SyncPullReply(rev: rev, changes: changes)
    }

    // MARK: - ПК → телефон

    enum Reply: Equatable, Sendable {
        case pushed(SyncPushReply)
        /// `more` — ПК отдал не всё (предел по размеру), просим ещё с нового `rev`.
        case pulled(SyncPullReply, more: Bool)
        case error(code: String)
        /// `welcome`, `state`, `pong`… — их разбирает `RemoteProtocol.decode`.
        case other(type: String)
    }

    private struct Head: Decodable {
        let v: Int?
        let type: String
        let re: String?
    }

    private struct Wrapped<Body: Decodable>: Decodable { let body: Body }
    private struct PullBodyIn: Decodable {
        let rev: Int
        let changes: [SyncChange]
        let more: Bool?
    }
    private struct ErrorBody: Decodable { let code: String? }

    /// Ответ ПК → `(re, что пришло)`; не JSON / другая версия / битое тело — ошибка.
    static func decode(_ text: String) throws -> (re: String?, reply: Reply) {
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        guard let head = try? decoder.decode(Head.self, from: data) else { throw RemoteDecodeError.badJSON }
        guard head.v == RemoteProtocol.version else { throw RemoteDecodeError.badVersion(head.v ?? -1) }
        let re = head.re.flatMap { $0.isEmpty ? nil : $0 }
        do {
            switch head.type {
            case "sync_push":
                return (re, .pushed(try decoder.decode(Wrapped<SyncPushReply>.self, from: data).body))
            case "sync_pull":
                let body = try decoder.decode(Wrapped<PullBodyIn>.self, from: data).body
                return (re, .pulled(SyncPullReply(rev: body.rev, changes: body.changes), more: body.more ?? false))
            case "error":
                let code = (try? decoder.decode(Wrapped<ErrorBody>.self, from: data))?.body.code
                return (re, .error(code: code ?? "unknown"))
            default:
                return (re, .other(type: String(head.type.prefix(32))))
            }
        } catch {
            throw RemoteDecodeError.badBody(head.type)
        }
    }
}

// MARK: - С кем синкаться

/// Куда идёт синк: сервер Sonar главнее; без него — ПК, к которому телефон привязан пультом; иначе никуда.
enum SyncTarget: Equatable, Sendable {
    case server
    case lan(pcID: String)
    case none

    /// Метка в журнале: сменилась — курсоры обнуляются (как `sync_target` на ПК).
    var tag: String? {
        switch self {
        case .server: "server"
        case let .lan(id): "lan:\(id)"
        case .none: nil
        }
    }

    /// `offline` — офлайн-режим: ни сервера, ни ПК (`NWConnection` идёт мимо `OfflineGuard`, проверяем сами).
    static func choose(serverReady: Bool, offline: Bool, pc: RemoteSyncPC?, hasKey: (String) -> Bool) -> SyncTarget {
        if offline { return .none }
        if serverReady { return .server }
        guard let pc, hasKey(pc.id) else { return .none }
        return .lan(pcID: pc.id)
    }
}

/// ПК, с которым телефон последний раз вошёл по пульту: с ним и синкаемся. Ключ — в Связке ключей
/// (`RemoteControl`), здесь только id и имя.
struct RemoteSyncPC: Codable, Equatable, Sendable {
    var id: String
    var name: String

    static let storageKey = "sonar.remote.sync_pc"

    static func load(from defaults: UserDefaults = .standard) -> RemoteSyncPC? {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(RemoteSyncPC.self, from: $0) }
    }

    static func save(_ pc: RemoteSyncPC?, to defaults: UserDefaults = .standard) {
        guard let pc, let data = try? JSONEncoder().encode(pc) else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    /// Отвязали ПК — забываем, только если это он.
    static func forget(_ id: String, in defaults: UserDefaults = .standard) {
        if load(from: defaults)?.id == id { save(nil, to: defaults) }
    }
}

/// Ошибка синка по Wi‑Fi; текст по-русски, переводит `t()`.
enum RemoteSyncError: LocalizedError, Equatable {
    case notFound
    case refused(String)
    case timeout
    case closed
    case badReply

    var russian: String {
        switch self {
        case .notFound: "ПК не найден в этой сети"
        case .timeout: "ПК не ответил"
        case .closed: "Связь с ПК оборвалась"
        case .badReply: "ПК ответил непонятно — обнови Sonar на ПК"
        case let .refused(code):
            switch code {
            case "not_paired": "ПК не узнал этот телефон — привяжи его заново в «Где играть»"
            case "offline": "На ПК включён офлайн-режим"
            case "server_sync": "ПК синхронизируется с сервером Sonar"
            case "too_big": "Слишком большая пачка изменений"
            default: "ПК не принял синхронизацию"
            }
        }
    }

    var errorDescription: String? { t(russian) }
}
