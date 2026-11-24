import Foundation
import Network

/// Связь с ПК: WebSocket поверх TCP (`NWProtocolWebSocket`) к службе Bonjour или к адресу из QR.
/// Только текстовые сообщения протокола (`RemoteProtocol`); звук не передаётся. Всё — на главной очереди.
@MainActor
final class RemoteConnection {
    enum Event: Equatable {
        case ready
        case message(String)
        /// Связь закрылась; `nil` — закрыли мы сами.
        case closed(String?)
    }

    private var connection: NWConnection?
    private let onEvent: @MainActor (Event) -> Void
    private var closed = false

    /// `maxMessage` — пульту хватает 64 КБ (как MAX_MESSAGE на ПК), синку нужно больше (`RemoteSync.maxMessage`).
    init(to pc: RemotePC, maxMessage: Int = 64 * 1024, onEvent: @escaping @MainActor (Event) -> Void) {
        self.onEvent = onEvent
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        websocket.maximumMessageSize = maxMessage
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        connection = NWConnection(to: Self.endpoint(pc.endpoint), using: parameters)
    }

    static func endpoint(_ endpoint: RemotePC.Endpoint) -> NWEndpoint {
        switch endpoint {
        case let .service(name, type, domain):
            return .service(name: name, type: type, domain: domain, interface: nil)
        case let .host(host, port):
            return .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 53120)
        }
    }

    func start() {
        guard let connection else { return }
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.changed(state) }
        }
        connection.start(queue: .main)
        receive()
    }

    func send(_ text: String) {
        guard let connection, !closed else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: Data(text.utf8), contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            MainActor.assumeIsolated { self?.finish("\(error)") }
        })
    }

    /// Закрыть самим (выбрали «Этот iPhone», ушли со связи) — без события.
    func cancel() {
        closed = true
        connection?.cancel()
        connection = nil
    }

    private func changed(_ state: NWConnection.State) {
        switch state {
        case .ready:
            onEvent(.ready)
        case let .failed(error):
            finish("\(error)")
        case let .waiting(error):
            // ПК не отвечает (выключен, другой Wi-Fi) — не ждём бесконечно
            finish("\(error)")
        case .cancelled:
            finish(nil)
        default:
            break
        }
    }

    private func receive() {
        connection?.receiveMessage { [weak self] data, context, _, error in
            let opcode = (context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata)?.opcode
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            let failure = error.map { "\($0)" }
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                if let failure { return self.finish(failure) }
                if opcode == .close { return self.finish("closed") }
                if opcode == .text, let text { self.onEvent(.message(text)) }
                self.receive()
            }
        }
    }

    private func finish(_ reason: String?) {
        guard !closed else { return }
        closed = true
        connection?.cancel()
        connection = nil
        onEvent(.closed(reason ?? "closed"))
    }
}
