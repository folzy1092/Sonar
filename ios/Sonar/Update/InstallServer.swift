import Foundation
import Network

/// Крошечный HTTP-сервер на `127.0.0.1` для `itms-services` (порт ShadowInstallServer, маршрут только
/// «Semi Local»): отдаёт подписанную IPA с поддержкой Range, страницу `/install` для Safari и считает,
/// сколько байт забрал установщик iOS. Состояние живёт на своей очереди; колбэки — тоже на ней.
final class InstallServer: @unchecked Sendable {
    struct Item: Sendable {
        let ipaURL: URL
        let bundleId: String
        let bundleVersion: String
        let title: String
    }

    enum ServerError: LocalizedError {
        case port

        var errorDescription: String? { "Не удалось открыть локальный порт для установки." }
    }

    private let item: Item
    private let queue = DispatchQueue(label: "sonar.install-server")
    private let ipaSize: Int64
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var pageTarget: URL?
    private var activity = InstallActivity()
    /// Отданные байты IPA по всем запросам: запрос хвоста (каталог zip) не значит, что передача закончена.
    private var payloadSent = IndexSet()
    private var didReportPayload = false
    private var didReportFinished = false
    private var startCompletion: (@Sendable (Result<UInt16, Error>) -> Void)?

    // Ставятся до `start()`, вызываются на очереди сервера.
    var onActivity: (@Sendable (InstallActivity) -> Void)?
    var onPayloadRequested: (@Sendable () -> Void)?
    var onPayloadProgress: (@Sendable (Int64, Int64) -> Void)?
    var onPayloadFinished: (@Sendable () -> Void)?

    init(item: Item) {
        self.item = item
        let size = (try? FileManager.default.attributesOfItem(atPath: item.ipaURL.path)[.size]) as? NSNumber
        self.ipaSize = size?.int64Value ?? 0
    }

    deinit {
        listener?.cancel()
    }

    /// Порт, на котором сервер готов.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.startCompletion = { continuation.resume(with: $0) }
                self.startListener()
            }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            self.connections.values.forEach { $0.cancel() }
            self.connections.removeAll()
        }
    }

    func snapshot() async -> InstallActivity {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.activity) }
        }
    }

    func setPageTarget(_ itms: URL) {
        queue.async { self.pageTarget = itms }
    }

    // MARK: - Слушатель

    /// Порты по очереди: сначала постоянные (под них в репо лежат запасные манифесты,
    /// `InstallLinks.fixedPorts`), последним — любой свободный.
    private var portsToTry: [NWEndpoint.Port] = InstallLinks.fixedPorts.compactMap { NWEndpoint.Port(rawValue: $0) } + [.any]

    private func startListener() {
        let port = portsToTry.isEmpty ? NWEndpoint.Port.any : portsToTry.removeFirst()
        let parameters = NWParameters.tcp
        // только петля: IPA не видна в локальной сети
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            if !portsToTry.isEmpty { return startListener() }
            finishStart(.failure(error))
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            // события прежнего слушателя (порт был занят) не трогают состояние нового
            guard let self, let listener, self.listener == nil || self.listener === listener else { return }
            self.listenerChanged(state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            activity.listener = "работает"
            activity.isReady = true
            if let port = listener?.port?.rawValue {
                finishStart(.success(port))
            } else {
                finishStart(.failure(ServerError.port))
            }
        case let .waiting(error):
            activity.listener = "ждёт: \(Self.describe(error))"
            activity.isReady = false
        case let .failed(error):
            activity.listener = "ошибка: \(Self.describe(error))"
            activity.isReady = false
            listener?.cancel()
            listener = nil
            // порт занят — следующий; пока не ответили на start()
            if startCompletion != nil, !portsToTry.isEmpty {
                startListener()
                return
            }
            finishStart(.failure(error))
        case .cancelled:
            if activity.isReady { activity.listener = "остановлен" }
            activity.isReady = false
        default:
            break
        }
        onActivity?(activity)
    }

    private func finishStart(_ result: Result<UInt16, Error>) {
        let completion = startCompletion
        startCompletion = nil
        completion?(result)
    }

    static func describe(_ error: NWError) -> String {
        switch error {
        case let .posix(code): "POSIX \(code.rawValue)"
        case let .tls(status): "TLS \(status)"
        case let .dns(code): "DNS \(code)"
        default: "\(error)"
        }
    }

    // MARK: - Соединения

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        activity.connections += 1
        onActivity?(activity)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case let .waiting(error), let .failed(error):
                self.activity.connectionErrors += 1
                self.activity.lastConnectionError = Self.describe(error)
                self.onActivity?(self.activity)
                self.connections.removeValue(forKey: id)?.cancel()
            case .cancelled:
                self.connections.removeValue(forKey: id)
            default:
                break
            }
        }
        connection.start(queue: queue)
        readRequest(connection, buffer: Data())
    }

    private func readRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(connection, head: String(decoding: buffer[buffer.startIndex ..< end.lowerBound], as: UTF8.self))
            } else if error != nil || isComplete || buffer.count > 64 * 1024 {
                connection.cancel()
            } else {
                self.readRequest(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.components(separatedBy: " ") ?? []
        guard requestLine.count >= 2 else {
            return send(connection, status: "400 Bad Request", headers: [:], body: Data(), isHead: false)
        }
        let method = requestLine[0].uppercased()
        let isHead = method == "HEAD"
        guard method == "GET" || isHead else {
            return send(connection, status: "405 Method Not Allowed", headers: [:], body: Data(), isHead: false)
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let path = requestLine[1].components(separatedBy: "?").first ?? ""
        switch path {
        case InstallLinks.pagePath:
            guard let target = pageTarget else {
                return send(connection, status: "404 Not Found", headers: [:], body: Data(), isHead: isHead)
            }
            activity.pageRequested = true
            onActivity?(activity)
            send(connection, status: "200 OK",
                 headers: ["Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store"],
                 body: Data(InstallLinks.installPage(itms: target).utf8), isHead: isHead)
        case InstallLinks.payloadPath:
            activity.payloadRequested = true
            onActivity?(activity)
            if !didReportPayload {
                didReportPayload = true
                onPayloadRequested?()
            }
            sendPayload(connection, range: headers["range"], isHead: isHead)
        default:
            send(connection, status: "404 Not Found", headers: [:], body: Data(), isHead: isHead)
        }
    }

    private func send(_ connection: NWConnection, status: String, headers: [String: String], body: Data, isHead: Bool) {
        var response = "HTTP/1.1 \(status)\r\n"
        var all = headers
        all["Content-Length"] = "\(body.count)"
        all["Connection"] = "close"
        for (key, value) in all.sorted(by: { $0.key < $1.key }) {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"
        var data = Data(response.utf8)
        if !isHead { data.append(body) }
        connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func sendPayload(_ connection: NWConnection, range header: String?, isHead: Bool) {
        let size = ipaSize
        guard size > 0, let handle = try? FileHandle(forReadingFrom: item.ipaURL) else {
            return send(connection, status: "404 Not Found", headers: [:], body: Data(), isHead: isHead)
        }
        let file = PayloadFile(handle: handle)
        let range = HTTPRange.parse(header, size: size)
        let span = range ?? (0 ... size - 1)
        var response = range == nil ? "HTTP/1.1 200 OK\r\n" : "HTTP/1.1 206 Partial Content\r\n"
        response += "Content-Type: application/octet-stream\r\n"
        response += "Accept-Ranges: bytes\r\n"
        response += "Content-Length: \(span.upperBound - span.lowerBound + 1)\r\n"
        if range != nil {
            response += "Content-Range: bytes \(span.lowerBound)-\(span.upperBound)/\(size)\r\n"
        }
        response += "Connection: close\r\n\r\n"
        if isHead {
            file.close()
            connection.send(content: Data(response.utf8), isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
        file.seek(to: span.lowerBound)
        sendChunk(connection, file: file, offset: span.lowerBound, end: span.upperBound)
    }

    private func sendChunk(_ connection: NWConnection, file: PayloadFile, offset: Int64, end: Int64) {
        let length = min(512 * 1024, end - offset + 1)
        let data = file.read(Int(length))
        if data.isEmpty {
            file.close()
            connection.cancel()
            return
        }
        let next = offset + Int64(data.count)
        let isLast = next > end
        connection.send(content: data, isComplete: isLast, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                file.close()
                connection.cancel()
                return
            }
            self.payloadSent.insert(integersIn: Int(offset) ..< Int(next))
            let sent = min(Int64(self.payloadSent.count), self.ipaSize)
            self.onPayloadProgress?(sent, self.ipaSize)
            if isLast {
                file.close()
                connection.cancel()
                if sent >= self.ipaSize, !self.didReportFinished {
                    self.didReportFinished = true
                    self.onPayloadFinished?()
                }
            } else {
                self.sendChunk(connection, file: file, offset: next, end: end)
            }
        })
    }
}

/// Файл IPA, который читается кусками на очереди сервера.
private final class PayloadFile: @unchecked Sendable {
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    func seek(to offset: Int64) {
        try? handle.seek(toOffset: UInt64(offset))
    }

    func read(_ count: Int) -> Data {
        (try? handle.read(upToCount: count)) ?? Data()
    }

    func close() {
        try? handle.close()
    }
}
