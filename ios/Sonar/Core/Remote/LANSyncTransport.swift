import Foundation

/// Синк с ПК по Wi‑Fi, пока нет сервера: отдельная короткая связь пульта (`RemoteConnection`) на один обмен.
/// Находит ПК по id через Bonjour (или берёт адрес, по которому уже подключён пульт), входит ключом пульта
/// (`hello` → `welcome`) и шлёт `sync_push` / `sync_pull` (docs/API.md «Синк по Wi‑Fi»). Прослушивания не
/// шлёт: телефон держит их для будущего сервера, иначе они уехали бы туда дважды. После обмена — `close()`.
@MainActor
final class LANSyncTransport: SyncTransport {
    static let findTimeout: Duration = .seconds(6)
    static let replyTimeout: Duration = .seconds(20)

    nonisolated var sendsPlays: Bool { false }

    private let pcID: String
    private let key: String
    private let device: RemoteDevice
    /// ПК, к которому пульт уже подключён: искать его в сети не нужно.
    private let known: RemotePC?

    private var connection: RemoteConnection?
    private var browser: RemoteBrowser?
    private var finding: CheckedContinuation<RemotePC, Error>?
    private var pending: [String: CheckedContinuation<RemoteSync.Reply, Error>] = [:]
    private var helloID = ""
    private var loggedIn = false
    private var nextID = 0

    init(pcID: String, key: String, device: RemoteDevice, known: RemotePC? = nil) {
        self.pcID = pcID
        self.key = key
        self.device = device
        self.known = known?.id == pcID ? known : nil
    }

    func push(_ ops: [SyncOp]) async throws -> SyncPushReply {
        try await open()
        guard case let .pushed(reply) = try await request({ RemoteSync.push(ops, id: $0) }) else {
            throw RemoteSyncError.badReply
        }
        return reply
    }

    func pull(since: Int) async throws -> SyncPullReply {
        try await open()
        return try await RemoteSync.pullAll(since: since) { [self] from in
            guard case let .pulled(page, more) = try await request({ RemoteSync.pull(since: from, id: $0) }) else {
                throw RemoteSyncError.badReply
            }
            return (page, more)
        }
    }

    func plays(_ plays: [PlayUpload]) async throws -> Int { 0 }

    /// Закрыть связь; всё, что ещё ждёт ответа, — ошибкой.
    func close() {
        found(.failure(RemoteSyncError.closed))
        connection?.cancel()
        connection = nil
        loggedIn = false
        failAll(RemoteSyncError.closed)
    }

    // MARK: - Вход

    private func open() async throws {
        if loggedIn, connection != nil { return }
        let pc = try await locate()
        let connection = RemoteConnection(to: pc, maxMessage: RemoteSync.maxMessage) { [weak self] event in
            self?.handle(event)
        }
        self.connection = connection
        helloID = makeID()
        let id = helloID
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RemoteSync.Reply, Error>) in
            pending[id] = continuation
            connection.start()
            armTimeout(id)
        }
        loggedIn = true
    }

    private func locate() async throws -> RemotePC {
        if let known { return known }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RemotePC, Error>) in
            finding = continuation
            let id = pcID
            let browser = RemoteBrowser(onChange: { [weak self] pcs in
                guard let pc = pcs.first(where: { $0.id == id }) else { return }
                self?.found(.success(pc))
            }, onFail: { [weak self] _ in
                self?.found(.failure(RemoteSyncError.notFound))
            })
            self.browser = browser
            browser.start()
            Task { [weak self] in
                try? await Task.sleep(for: Self.findTimeout)
                self?.found(.failure(RemoteSyncError.notFound))
            }
        }
    }

    private func found(_ result: Result<RemotePC, Error>) {
        browser?.stop()
        browser = nil
        guard let continuation = finding else { return }
        finding = nil
        continuation.resume(with: result)
    }

    // MARK: - Запросы

    private func request(_ make: (String) -> String) async throws -> RemoteSync.Reply {
        guard let connection, loggedIn else { throw RemoteSyncError.closed }
        let id = makeID()
        let text = make(id)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RemoteSync.Reply, Error>) in
            pending[id] = continuation
            connection.send(text)
            armTimeout(id)
        }
    }

    private func armTimeout(_ id: String) {
        Task { [weak self] in
            try? await Task.sleep(for: Self.replyTimeout)
            self?.resolve(id, .failure(RemoteSyncError.timeout))
        }
    }

    private func resolve(_ id: String, _ result: Result<RemoteSync.Reply, Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func failAll(_ error: Error) {
        let waiting = pending
        pending = [:]
        for continuation in waiting.values { continuation.resume(throwing: error) }
    }

    private func makeID() -> String {
        nextID += 1
        return "s\(nextID)"
    }

    // MARK: - Связь

    private func handle(_ event: RemoteConnection.Event) {
        switch event {
        case .ready:
            connection?.send(RemoteOutgoing.hello(device, key: key).encoded(id: helloID))
        case let .message(text):
            received(text)
        case .closed:
            connection = nil
            loggedIn = false
            failAll(RemoteSyncError.closed)
        }
    }

    private func received(_ text: String) {
        guard let (re, reply) = try? RemoteSync.decode(text) else { return }
        switch reply {
        case .other("welcome"):
            guard case let .welcome(pc)? = try? RemoteProtocol.decode(text).message, pc.id == pcID else {
                return resolve(helloID, .failure(RemoteSyncError.refused("wrong_pc")))
            }
            resolve(helloID, .success(reply))
        case .other("bye"):
            let unpaired = (try? RemoteProtocol.decode(text).message) == .bye(reason: "unpaired")
            failAll(unpaired ? RemoteSyncError.refused("not_paired") : RemoteSyncError.closed)
        case .other:
            // `state` приходит сразу после входа, `pong` — на чужой ping: синку не нужны
            break
        case let .error(code):
            if let re, pending[re] != nil {
                resolve(re, .failure(RemoteSyncError.refused(code)))
            } else {
                failAll(RemoteSyncError.refused(code))
            }
        case .pushed, .pulled:
            if let re { resolve(re, .success(reply)) }
        }
    }
}
