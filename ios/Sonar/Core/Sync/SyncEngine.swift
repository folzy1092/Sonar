import Foundation

/// Хранилище телефона глазами синка: снимок своих строк и применение пришедших.
@MainActor
protocol SyncAdapter: AnyObject {
    /// Типы операций (`like`, `setting`…), за которые отвечает адаптер.
    var types: Set<String> { get }
    /// Текущее состояние: (тип, ключ) → значение в формате API.md §6. `journal` — прошлые значения
    /// (например, `added_at` лайка, которого хранилище не помнит).
    func snapshot(journal: SyncJournal) -> [SyncKey: JSONValue]
    /// Применить пришедшее (`.null` — удалить). false — телефон такое хранить не умеет (строка останется
    /// в журнале «чужой»). `journal` уже содержит это изменение.
    func apply(_ change: SyncChange, journal: SyncJournal) -> Bool
}

/// Куда отправлять: сервер по HTTP (`HTTPSyncTransport`) или в памяти (`MemorySyncServer`, тесты).
protocol SyncTransport: Sendable {
    func push(_ ops: [SyncOp]) async throws -> SyncPushReply
    func pull(since: Int) async throws -> SyncPullReply
    func plays(_ plays: [PlayUpload]) async throws -> Int
}

/// Обмен с сервером — порт `sync_once` (Windows `sync.rs`): отправить своё пачками, отправить
/// прослушивания, забрать чужое. Журнал пишется в файл после каждого шага.
@MainActor
final class SyncEngine {
    static let pushBatch = 500
    static let playsBatch = 500

    let deviceId: String
    private(set) var journal: SyncJournal
    /// Идёт применение пришедшего — уведомления хранилищ в это время не свои изменения.
    private(set) var isApplying = false
    private let adapters: [SyncAdapter]
    private let file: URL?
    private let now: () -> Int64
    /// Прослушивания после метки (мс), по возрастанию `played_at`.
    private let playsSource: ((Int64) -> [PlayUpload])?

    init(deviceId: String, adapters: [SyncAdapter], file: URL? = nil, plays: ((Int64) -> [PlayUpload])? = nil,
         now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.deviceId = deviceId
        self.adapters = adapters
        self.file = file
        self.now = now
        playsSource = plays
        if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(SyncJournal.self, from: data) {
            journal = saved
        } else {
            journal = SyncJournal()
        }
    }

    /// Сверить хранилища с журналом (своё изменение → новый rev). Вернёт, сколько строк изменилось.
    @discardableResult
    func scan() -> Int {
        var changed = 0
        for adapter in adapters {
            changed += journal.record(adapter.snapshot(journal: journal), types: adapter.types, now: now())
        }
        if changed > 0 { save() }
        return changed
    }

    func pendingOps(limit: Int = SyncEngine.pushBatch) -> PushPlan {
        journal.pendingOps(deviceId: deviceId, limit: limit)
    }

    func markPushed(_ upto: Int) {
        journal.markPushed(upto)
        save()
    }

    /// Применить пришедшее; вернёт, сколько применено. Своё неотправленное важнее — пришедшее
    /// пропускается, своё уйдёт следующей отправкой, и сервер решит, кто позже.
    @discardableResult
    func apply(_ changes: [SyncChange]) -> Int {
        scan() // свежие свои правки — сначала в журнал, чтобы их не затёрло
        isApplying = true
        defer { isApplying = false }
        var applied = 0
        var touched: [SyncKey: SyncAdapter] = [:]
        for change in changes.sorted(by: { $0.rev < $1.rev }) {
            let key = SyncKey(change.type, change.key)
            if journal.isPending(key) { continue }
            let adapter = adapters.first { $0.types.contains(change.type) }
            journal.store(key, value: change.value, foreign: true, now: now())
            guard let adapter, adapter.apply(change, journal: journal) else { continue }
            journal.store(key, value: change.value, foreign: false, now: now())
            touched[key] = adapter
            applied += 1
        }
        // как теперь видит хранилище — чтобы следующий scan не принял пришедшее за своё
        var snapshots: [ObjectIdentifier: [SyncKey: JSONValue]] = [:]
        for (key, adapter) in touched {
            let id = ObjectIdentifier(adapter)
            if snapshots[id] == nil { snapshots[id] = adapter.snapshot(journal: journal) }
            journal.settle(key, value: snapshots[id]?[key])
        }
        if let max = changes.map(\.rev).max(), max > journal.pulledRev { journal.pulledRev = max }
        save()
        return applied
    }

    /// Один полный обмен.
    func syncOnce(_ transport: SyncTransport) async throws -> SyncReport {
        var report = SyncReport()
        scan()
        while true {
            let plan = pendingOps()
            if plan.ops.isEmpty {
                markPushed(plan.upto)
                break
            }
            let reply = try await transport.push(plan.ops)
            let applied = Set(reply.applied)
            // сервер подтверждает каждую операцию; не все — курсор не сдвигаем, повторим позже
            if plan.ops.contains(where: { !applied.contains($0.opId) }) {
                throw SyncError.partial(applied: reply.applied.count, sent: plan.ops.count)
            }
            report.pushed += plan.ops.count
            markPushed(plan.upto)
            if plan.ops.count < Self.pushBatch { break }
        }
        if let playsSource {
            while true {
                let batch = Array(playsSource(journal.playsUploadedAt).prefix(Self.playsBatch))
                guard let last = batch.last?.playedAt else { break }
                _ = try await transport.plays(batch)
                report.plays += batch.count
                journal.playsUploadedAt = max(journal.playsUploadedAt, last)
                save()
                if batch.count < Self.playsBatch { break }
            }
        }
        let reply = try await transport.pull(since: journal.pulledRev)
        report.pulled = apply(reply.changes)
        if reply.rev > journal.pulledRev {
            journal.pulledRev = reply.rev
            save()
        }
        return report
    }

    /// Выход из аккаунта.
    func reset() {
        journal.reset()
        save()
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(journal) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// Сервер Sonar по HTTP (API.md §6).
struct HTTPSyncTransport: SyncTransport {
    let client: APIClient

    private struct PushBody: Encodable { var ops: [SyncOp] }
    private struct PlaysBody: Encodable { var plays: [PlayUpload] }
    private struct Accepted: Decodable { var accepted: Int }

    func push(_ ops: [SyncOp]) async throws -> SyncPushReply {
        try await client.send("POST", "sync/push", body: PushBody(ops: ops))
    }

    func pull(since: Int) async throws -> SyncPullReply {
        try await client.send("GET", "sync/pull", query: [("since", String(since))])
    }

    func plays(_ plays: [PlayUpload]) async throws -> Int {
        let reply: Accepted = try await client.send("POST", "plays", body: PlaysBody(plays: plays))
        return reply.accepted
    }
}

/// Сервер в памяти с той же логикой, что `MemoryServer` в Windows `sync.rs` и API.md §6: глобальный rev,
/// повтор `op_id` не применяется дважды (но подтверждается), настройки — «побеждает позднее» по
/// `client_ts` (проигравшему победитель приходит в следующем pull), остальное — последняя запись. Для тестов и как образец для серверной части.
actor MemorySyncServer: SyncTransport {
    private struct Row {
        var value: JSONValue
        var rev: Int
        var ts: Int64
    }

    private var rev = 0
    private var rows: [SyncKey: Row] = [:]
    private var seen: Set<String> = []
    private(set) var playsCount = 0
    /// Сколько раз звали push (для тестов «повтор»).
    private(set) var pushCalls = 0

    func push(_ ops: [SyncOp]) async throws -> SyncPushReply {
        pushCalls += 1
        var applied: [String] = []
        for op in ops {
            if seen.insert(op.opId).inserted {
                let key = SyncKey(op.type, op.key)
                let older = op.type == "setting" && (rows[key].map { $0.ts > op.clientTs } ?? false)
                rev += 1
                if older {
                    // проигравшее изменение: победитель уходит в pull заново, чтобы отправивший его получил
                    rows[key]?.rev = rev
                } else {
                    rows[key] = Row(value: op.value, rev: rev, ts: op.clientTs)
                }
            }
            applied.append(op.opId)
        }
        return SyncPushReply(applied: applied)
    }

    func pull(since: Int) async throws -> SyncPullReply {
        let changes = rows.filter { $0.value.rev > since }
            .map { SyncChange(type: $0.key.type, key: $0.key.key, value: $0.value.value, rev: $0.value.rev) }
            .sorted { $0.rev < $1.rev }
        return SyncPullReply(rev: rev, changes: changes)
    }

    func plays(_ plays: [PlayUpload]) async throws -> Int {
        playsCount += plays.count
        return plays.count
    }

    func value(_ type: String, _ key: String) -> JSONValue? {
        rows[SyncKey(type, key)]?.value
    }
}
