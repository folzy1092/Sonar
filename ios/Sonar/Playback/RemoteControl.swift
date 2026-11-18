import Foundation
import UIKit

/// Пульт: телефон управляет Sonar на ПК по Wi-Fi («Где играть» в полноэкранном плеере). Звук не
/// передаётся — только команды и то, что играет на ПК (протокол — `RemoteProtocol`, docs/API.md «Пульт»).
/// Ключ привязки к каждому ПК — в Связке ключей (`sonar.remote` / `key.<id ПК>`), код вводится один раз.
@MainActor
@Observable
final class RemoteControl {
    static let shared = RemoteControl()

    enum Phase: Equatable {
        case idle
        case connecting
        /// ПК ещё не знает телефон — нужен код с экрана ПК.
        case needsCode
        case connected
        case failed(String)
    }

    /// ПК с включённым пультом в этой сети (Bonjour).
    private(set) var pcs: [RemotePC] = []
    /// Выбранный ПК (`nil` — играет этот iPhone).
    private(set) var target: RemotePC?
    private(set) var phase: Phase = .idle
    /// Что играет на ПК; `receivedAt` — когда пришло (позицию досчитываем своими часами).
    private(set) var state: RemoteState?
    private(set) var receivedAt = Date()
    /// Код не подошёл / устарел — показываем под полем кода.
    private(set) var codeError: String?
    /// Поиск ПК не работает (обычно нет доступа к локальной сети).
    private(set) var browseFailed = false

    /// Режим пульта: плеер и мини-плеер показывают ПК, а не этот iPhone.
    var isActive: Bool { target != nil && state != nil }
    var isConnected: Bool { phase == .connected }
    var pcName: String { state?.device?.name ?? target?.name ?? "" }

    @ObservationIgnored private var browser: RemoteBrowser?
    @ObservationIgnored private var connection: RemoteConnection?
    /// Первое сообщение после открытия связи (`hello` или `pair`).
    @ObservationIgnored private var pending: RemoteOutgoing?
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var nextID = 0

    private static let keychainService = "sonar.remote"
    private static let maxRetries = 3

    private init() {}

    // MARK: - Поиск

    func startBrowsing() {
        browseFailed = false
        if browser == nil {
            browser = RemoteBrowser(
                onChange: { [weak self] found in self?.found(found) },
                onFail: { [weak self] _ in self?.browseFailed = true }
            )
        }
        browser?.start()
    }

    func stopBrowsing() {
        browser?.stop()
    }

    private func found(_ list: [RemotePC]) {
        pcs = list
        if !list.isEmpty { browseFailed = false }
    }

    // MARK: - Выбор устройства

    /// Играть на этом iPhone: связь с ПК закрывается, музыка на ПК не останавливается.
    func useThisPhone() {
        disconnect()
        target = nil
        state = nil
        phase = .idle
        codeError = nil
    }

    /// Выбрали ПК: есть ключ — входим им, нет — просим код.
    func choose(_ pc: RemotePC) {
        guard pc != target || !isConnected else { return }
        disconnect()
        target = pc
        state = nil
        codeError = nil
        retries = 0
        if let key = Self.key(for: pc.id) {
            connect(.hello(Self.device, key: key))
        } else {
            phase = .needsCode
        }
    }

    /// Код с экрана ПК (6 цифр).
    func submit(code: String) {
        let code = RemoteProtocol.cleanCode(code)
        guard target != nil, RemoteProtocol.isCode(code) else { return }
        codeError = nil
        connect(.pair(Self.device, code: code))
    }

    /// QR с экрана ПК (`sonar://remote/pair?…`) — системная камера открывает ссылку.
    func pair(_ link: RemotePairLink) {
        disconnect()
        target = pcs.first { $0.id == link.pc.id } ?? link.pc
        state = nil
        codeError = nil
        retries = 0
        connect(.pair(Self.device, code: link.code))
    }

    /// Вернулись в приложение / открыли «Где играть» — связь с выбранным ПК потерялась, пробуем снова.
    func reconnectIfNeeded() {
        guard let pc = target, connection == nil, phase != .needsCode, let key = Self.key(for: pc.id) else { return }
        retries = 0
        connect(.hello(Self.device, key: key))
    }

    // MARK: - Команды

    func send(_ command: RemoteCommand) {
        guard isConnected, let connection else {
            if target != nil { PlaybackEngine.shared.message = t("Нет связи с {name}", ["name": pcName]) }
            return
        }
        connection.send(RemoteOutgoing.command(command).encoded(id: messageID()))
        guess(command)
    }

    /// Список с трека index — на ПК: первый играет, следующие (до 49) уходят в очередь.
    /// `false` — пульт не включён, играет этот iPhone.
    func forward(_ list: [Track], from index: Int) -> Bool {
        guard isActive, list.indices.contains(index) else { return false }
        let first = list[index]
        send(.play(ref: first.ref, track: first))
        for track in list.dropFirst(index + 1).prefix(RemoteProtocol.queueLimit - 1) {
            send(.queueAdd(ref: track.ref, track: track, next: false))
        }
        return true
    }

    func forwardEnqueue(_ track: Track, next: Bool) -> Bool {
        guard isActive else { return false }
        send(.queueAdd(ref: track.ref, track: track, next: next))
        return true
    }

    func forwardWave() -> Bool {
        guard isActive else { return false }
        send(.playWave)
        return true
    }

    /// Позиция на ПК сейчас, секунды.
    func position(at now: Date) -> Double {
        state?.position(after: now.timeIntervalSince(receivedAt)) ?? 0
    }

    /// Сразу показываем ожидаемое (ПК пришлёт настоящее состояние следом).
    private func guess(_ command: RemoteCommand) {
        guard var next = state else { return }
        switch command {
        case .toggle:
            next.positionMs = Int(position(at: Date()) * 1000)
            next.playing.toggle()
        case let .seek(ms):
            next.positionMs = ms
        case let .volume(value):
            next.volume = value
        case let .like(ref, value) where ref == nil || ref == next.track?.ref:
            next.liked = value ?? !next.liked
        default:
            return
        }
        state = next
        receivedAt = Date()
    }

    // MARK: - Связь

    private func connect(_ first: RemoteOutgoing) {
        guard let pc = target else { return }
        disconnect()
        phase = .connecting
        pending = first
        let connection = RemoteConnection(to: pc) { [weak self] event in self?.handle(event) }
        self.connection = connection
        connection.start()
    }

    private func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        connection?.cancel()
        connection = nil
        pending = nil
    }

    private func handle(_ event: RemoteConnection.Event) {
        switch event {
        case .ready:
            if let pending { connection?.send(pending.encoded(id: messageID())) }
            pending = nil
            startPing()
        case let .message(text):
            guard let decoded = try? RemoteProtocol.decode(text) else { return }
            handle(decoded.message)
        case .closed:
            lost()
        }
    }

    private func handle(_ message: RemoteIncoming) {
        switch message {
        case let .welcome(pc):
            loggedIn(pc)
        case let .paired(pc, key):
            guard RemoteProtocol.isKey(key) else { return failed(t("ПК прислал неверный ключ")) }
            Keychain.set(key, service: Self.keychainService, account: Self.keyAccount(pc.id))
            PlaybackEngine.shared.message = t("Привязан к {name}", ["name": pc.name])
            loggedIn(pc)
        case let .state(next):
            state = next
            receivedAt = Date()
        case let .error(code):
            refused(code)
        case .pong:
            break
        case let .bye(reason):
            closedByPC(reason)
        }
    }

    private func loggedIn(_ pc: RemotePCInfo) {
        phase = .connected
        retries = 0
        codeError = nil
        // на ПК ещё ничего не играло — состояние не придёт, показываем пустой плеер ПК
        if state == nil { state = RemoteState(track: nil, device: .init(id: pc.id, name: pc.name, kind: "pc")) }
        if PlaybackEngine.shared.isPlaying { PlaybackEngine.shared.pause() }
    }

    /// Ответ `error`: до входа — код или ключ не подошли, после — команда не выполнилась.
    private func refused(_ code: String) {
        let text = t(RemoteErrorText.russian(code))
        guard phase == .connecting else {
            PlaybackEngine.shared.message = text
            return
        }
        disconnect()
        switch code {
        case "not_paired":
            if let pc = target { Keychain.set(nil, service: Self.keychainService, account: Self.keyAccount(pc.id)) }
            state = nil
            phase = .needsCode
        case "bad_code", "no_code", "code_expired", "code_burned":
            // код из QR — листа «Где играть» может не быть на экране, поэтому и всплывашкой
            codeError = text
            phase = .needsCode
            PlaybackEngine.shared.message = text
        default:
            failed(text)
        }
    }

    private func closedByPC(_ reason: String) {
        disconnect()
        state = nil
        if reason == "unpaired", let pc = target {
            Keychain.set(nil, service: Self.keychainService, account: Self.keyAccount(pc.id))
            phase = .needsCode
            PlaybackEngine.shared.message = t("{name} отвязал этот телефон", ["name": pc.name])
        } else {
            failed(t("На ПК выключили пульт"))
        }
    }

    /// Связь оборвалась сама: после входа пробуем вернуться (Wi-Fi моргнул), иначе — ошибка.
    private func lost() {
        let wasIn = phase == .connected || state != nil
        disconnect()
        guard let pc = target, wasIn, retries < Self.maxRetries, let key = Self.key(for: pc.id) else {
            if phase == .connecting || phase == .connected {
                failed(t("Не удалось подключиться к {name}", ["name": target?.name ?? ""]))
            }
            return
        }
        retries += 1
        phase = .connecting
        let delay = Double(retries)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.target == pc, self.connection == nil, self.phase == .connecting else { return }
            self.connect(.hello(Self.device, key: key))
        }
    }

    private func failed(_ text: String) {
        disconnect()
        let hadState = state != nil
        state = nil
        phase = .failed(text)
        if hadState { PlaybackEngine.shared.message = text }
    }

    private func startPing() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(RemoteProtocol.pingInterval))
                guard let self, !Task.isCancelled, let connection = self.connection else { return }
                connection.send(RemoteOutgoing.ping.encoded(id: self.messageID()))
            }
        }
    }

    private func messageID() -> String {
        nextID += 1
        return "i\(nextID)"
    }

    // MARK: - Связка ключей

    private static func keyAccount(_ pcID: String) -> String { "key.\(pcID)" }

    private static func key(for pcID: String) -> String? {
        Keychain.string(service: keychainService, account: keyAccount(pcID)).flatMap { RemoteProtocol.isKey($0) ? $0 : nil }
    }

    /// Этот телефон для ПК: постоянный id (из Связки ключей) и имя устройства.
    private static var device: RemoteDevice {
        RemoteDevice(id: deviceID(), name: RemoteProtocol.cleanName(UIDevice.current.name))
    }

    private static func deviceID() -> String {
        if let id = Keychain.string(service: keychainService, account: "device"), RemoteProtocol.isDeviceID(id) { return id }
        let id = UUID().uuidString.lowercased()
        Keychain.set(id, service: keychainService, account: "device")
        return id
    }
}
