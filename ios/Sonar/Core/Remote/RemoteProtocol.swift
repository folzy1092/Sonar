import Foundation

// Пульт (docs/API.md «Пульт»): iPhone управляет Sonar на ПК по Wi-Fi. Здесь — чистая часть без сети:
// конверт `{v, type, id, re?, body}`, что телефон шлёт (hello / pair / ping / команды), что приходит от ПК
// (welcome / paired / state / error / pong / bye), найденный в сети ПК и ссылка из QR. Тот же протокол, что
// `windows/src-tauri/src/remote/protocol.rs`; проверяется XCTest `RemoteTests.swift`. Сеть — `RemoteConnection`,
// поиск — `RemoteBrowser`, состояние пульта — `Playback/RemoteControl.swift`.

enum RemoteProtocol {
    static let version = 1
    /// Bonjour: так ПК объявляет себя в сети (mdns.rs).
    static let serviceType = "_sonar._tcp"
    static let defaultPort: UInt16 = 53120
    /// Столько треков «Далее» присылает ПК.
    static let queueLimit = 50
    static let codeLength = 6
    /// Сервер ПК рвёт связь после 60 с тишины — пингуем чаще.
    static let pingInterval: TimeInterval = 20
    static let maxDeviceName = 64

    /// 6 цифр с экрана ПК.
    static func isCode(_ s: String) -> Bool {
        s.count == codeLength && s.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Что набрали в поле кода: только цифры, не длиннее шести (пробелы и дефисы из буфера — долой).
    static func cleanCode(_ s: String) -> String {
        String(s.filter { $0.isASCII && $0.isNumber }.prefix(codeLength))
    }

    /// Ключ от ПК: base64url, 16–128 символов (pairing.rs `new_key` — 43).
    static func isKey(_ s: String) -> Bool {
        (16...128).contains(s.count) && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// id телефона: 1–64 символа `[A-Za-z0-9-_.]` (UUID подходит).
    static func isDeviceID(_ s: String) -> Bool {
        (1...64).contains(s.count) && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }

    /// Имя телефона в списке устройств на ПК: без управляющих символов, до 64 знаков.
    static func cleanName(_ s: String) -> String {
        let name = String(String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxDeviceName))
        return name.isEmpty ? "iPhone" : name
    }
}

/// Этот телефон в `hello` / `pair`.
struct RemoteDevice: Equatable, Sendable {
    var id: String
    var name: String
}

/// ПК из `welcome` / `paired` и из `state.device`.
struct RemotePCInfo: Codable, Equatable, Hashable, Sendable {
    var id: String
    var name: String
}

// MARK: - Телефон → ПК

enum RemoteCommand: Equatable, Sendable {
    case toggle
    case next
    case prev
    /// Миллисекунды от начала трека.
    case seek(ms: Int)
    /// 0…1.
    case volume(Double)
    /// `ref` нет — текущий трек ПК; `value` нет — переключить.
    case like(ref: String?, value: Bool?)
    case playWave
    case play(ref: String, track: Track?)
    case queueAdd(ref: String, track: Track?, next: Bool)
    /// Номер в очереди из последнего `state` (0 — ближайший).
    case queuePlayIndex(Int)

    var type: String {
        switch self {
        case .toggle: "toggle"
        case .next: "next"
        case .prev: "prev"
        case .seek: "seek"
        case .volume: "volume"
        case .like: "like"
        case .playWave, .play: "play"
        case .queueAdd: "queue_add"
        case .queuePlayIndex: "queue_play_index"
        }
    }

    var body: [String: Any] {
        switch self {
        case .toggle, .next, .prev:
            return [:]
        case let .seek(ms):
            return ["ms": max(0, ms)]
        case let .volume(value):
            return ["value": min(1, max(0, value.isFinite ? value : 0))]
        case let .like(ref, value):
            var body: [String: Any] = [:]
            if let ref { body["ref"] = ref }
            if let value { body["value"] = value }
            return body
        case .playWave:
            return ["wave": true]
        case let .play(ref, track):
            return Self.withTrack(["wave": false, "ref": ref], ref: ref, track: track)
        case let .queueAdd(ref, track, next):
            return Self.withTrack(["ref": ref, "next": next], ref: ref, track: track)
        case let .queuePlayIndex(index):
            return ["index": index]
        }
    }

    /// Трек целиком — ПК сыграет его, даже если не видел в своём кэше. Чужой ref не прикладываем.
    private static func withTrack(_ base: [String: Any], ref: String, track: Track?) -> [String: Any] {
        guard let track, track.ref == ref,
              let data = try? JSONEncoder().encode(track),
              let object = try? JSONSerialization.jsonObject(with: data) else { return base }
        return base.merging(["track": object]) { _, new in new }
    }
}

enum RemoteOutgoing: Sendable {
    case hello(RemoteDevice, key: String)
    case pair(RemoteDevice, code: String)
    case ping
    case command(RemoteCommand)

    var type: String {
        switch self {
        case .hello: "hello"
        case .pair: "pair"
        case .ping: "ping"
        case let .command(command): command.type
        }
    }

    var body: [String: Any] {
        let device = { (d: RemoteDevice) -> [String: Any] in ["id": d.id, "name": RemoteProtocol.cleanName(d.name)] }
        switch self {
        case let .hello(d, key): return ["device": device(d), "key": key]
        case let .pair(d, code): return ["device": device(d), "code": code]
        case .ping: return [:]
        case let .command(command): return command.body
        }
    }

    /// Конверт `{v, type, id, body}` строкой JSON (ключи по алфавиту — стабильно для тестов).
    func encoded(id: String) -> String {
        var envelope: [String: Any] = ["v": RemoteProtocol.version, "type": type, "id": id]
        let body = body
        if !body.isEmpty { envelope["body"] = body }
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - ПК → телефон

/// Что играет на ПК (`state`). Позицию телефон двигает сам от момента получения — часы ПК не нужны.
struct RemoteState: Codable, Equatable, Sendable {
    var track: Track?
    var positionMs: Int
    var durationMs: Int
    var playing: Bool
    var volume: Double
    var repeatMode: RepeatMode
    var shuffle: Bool
    var liked: Bool
    var queue: [Track]
    var contextTitle: String?
    var device: Device?

    struct Device: Codable, Equatable, Sendable {
        var id: String
        var name: String
        var kind: String?
    }

    enum CodingKeys: String, CodingKey {
        case track, playing, volume, shuffle, liked, queue, device
        case positionMs = "position_ms"
        case durationMs = "duration_ms"
        case repeatMode = "repeat"
        case contextTitle = "context_title"
    }

    init(track: Track?, positionMs: Int = 0, durationMs: Int = 0, playing: Bool = false, volume: Double = 1,
         repeatMode: RepeatMode = .off, shuffle: Bool = false, liked: Bool = false, queue: [Track] = [],
         contextTitle: String? = nil, device: Device? = nil) {
        self.track = track
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.playing = playing
        self.volume = volume
        self.repeatMode = repeatMode
        self.shuffle = shuffle
        self.liked = liked
        self.queue = queue
        self.contextTitle = contextTitle
        self.device = device
    }

    // Терпимо к старым и будущим ПК: чего нет — по умолчанию, неизвестный повтор — «выкл».
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(type, forKey: key)) ?? nil
        }
        /// Миллисекунды: только конечные и неотрицательные, не больше суток.
        func ms(_ key: CodingKeys) -> Int {
            guard let raw = value(Double.self, key), raw.isFinite, raw > 0 else { return 0 }
            return Int(min(raw, Self.maxMs))
        }
        track = value(Track.self, .track)
        positionMs = ms(.positionMs)
        durationMs = ms(.durationMs)
        playing = value(Bool.self, .playing) ?? false
        let rawVolume = value(Double.self, .volume) ?? 1
        volume = rawVolume.isFinite ? min(1, max(0, rawVolume)) : 1
        repeatMode = value(String.self, .repeatMode).flatMap(RepeatMode.init(rawValue:)) ?? .off
        shuffle = value(Bool.self, .shuffle) ?? false
        liked = value(Bool.self, .liked) ?? false
        // битый трек в очереди пропускаем, а не теряем всё состояние
        queue = Array((value([FailableTrack].self, .queue) ?? []).compactMap(\.track).prefix(RemoteProtocol.queueLimit))
        contextTitle = value(String.self, .contextTitle)
        device = value(Device.self, .device)
    }

    private static let maxMs: Double = 24 * 60 * 60 * 1000

    /// Секунды: где сейчас трек, если с получения `state` прошло `elapsed` секунд.
    func position(after elapsed: TimeInterval) -> Double {
        let start = Double(positionMs) / 1000
        let end = durationMs > 0 ? Double(durationMs) / 1000 : .infinity
        guard playing else { return min(start, end) }
        return min(end, start + max(0, elapsed))
    }

    var duration: Double { Double(durationMs) / 1000 }
}

private struct FailableTrack: Decodable {
    let track: Track?
    init(from decoder: Decoder) throws {
        track = try? Track(from: decoder)
    }
}

enum RemoteIncoming: Equatable, Sendable {
    case welcome(RemotePCInfo)
    /// Ключ приходит один раз — сразу в Keychain.
    case paired(RemotePCInfo, key: String)
    case state(RemoteState)
    case error(code: String)
    case pong
    /// `unpaired` — телефон отвязали на ПК, `disabled` — пульт на ПК выключили.
    case bye(reason: String)
}

enum RemoteDecodeError: Error, Equatable {
    case badJSON
    case badVersion(Int)
    case unknown(String)
    case badBody(String)
}

extension RemoteProtocol {
    /// Сообщение от ПК → `(re, что пришло)`.
    static func decode(_ text: String) throws -> (re: String?, message: RemoteIncoming) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any],
              let type = envelope["type"] as? String else { throw RemoteDecodeError.badJSON }
        let v = (envelope["v"] as? NSNumber)?.intValue ?? -1
        guard v == version else { throw RemoteDecodeError.badVersion(v) }
        let re = (envelope["re"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let body = envelope["body"] as? [String: Any] ?? [:]
        return (re, try message(type: type, body: body))
    }

    private static func message(type: String, body: [String: Any]) throws -> RemoteIncoming {
        switch type {
        case "welcome":
            return .welcome(try pc(body))
        case "paired":
            guard let key = body["key"] as? String, isKey(key) else { throw RemoteDecodeError.badBody("key") }
            return .paired(try pc(body), key: key)
        case "state":
            guard let data = try? JSONSerialization.data(withJSONObject: body),
                  let state = try? JSONDecoder().decode(RemoteState.self, from: data) else { throw RemoteDecodeError.badBody("state") }
            return .state(state)
        case "error":
            return .error(code: (body["code"] as? String) ?? "unknown")
        case "pong":
            return .pong
        case "bye":
            return .bye(reason: (body["reason"] as? String) ?? "")
        default:
            throw RemoteDecodeError.unknown(String(type.prefix(32)))
        }
    }

    private static func pc(_ body: [String: Any]) throws -> RemotePCInfo {
        guard let pc = body["pc"] as? [String: Any], let id = pc["id"] as? String, !id.isEmpty else {
            throw RemoteDecodeError.badBody("pc")
        }
        return RemotePCInfo(id: id, name: (pc["name"] as? String).map(cleanName) ?? "PC")
    }
}

// MARK: - Где искать ПК

/// ПК в списке «Где играть»: найден в сети (Bonjour) или пришёл из QR (адрес и порт).
struct RemotePC: Identifiable, Hashable, Sendable {
    enum Endpoint: Hashable, Sendable {
        /// Служба Bonjour: имя, тип, домен.
        case service(name: String, type: String, domain: String)
        case host(String, port: UInt16)
    }

    var id: String
    var name: String
    var endpoint: Endpoint

    /// Из TXT службы (mdns.rs: `id`, `v`, `name`). Нет id — служба чужая или старая, не показываем;
    /// другая версия протокола — тоже.
    static func fromService(name: String, type: String = RemoteProtocol.serviceType, domain: String = "local.",
                            txt: [String: String]) -> RemotePC? {
        guard let id = txt["id"], !id.isEmpty else { return nil }
        if let v = txt["v"], Int(v) != RemoteProtocol.version { return nil }
        let title = txt["name"].map(RemoteProtocol.cleanName) ?? name
        return RemotePC(id: id, name: title, endpoint: .service(name: name, type: type, domain: domain))
    }
}

/// `sonar://remote/pair?pc=&name=&host=&port=&code=` — QR с экрана «Система → Пульт» (mod.rs `pair_link`).
struct RemotePairLink: Equatable, Sendable {
    var pc: RemotePC
    var code: String

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "sonar", url.host()?.lowercased() == "remote",
              url.pathComponents.dropFirst().first?.lowercased() == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let query = Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }) { first, _ in first }
        guard let id = query["pc"], !id.isEmpty,
              let host = query["host"], !host.isEmpty,
              let port = query["port"].flatMap(UInt16.init), port > 0,
              let code = query["code"], RemoteProtocol.isCode(code) else { return nil }
        let name = query["name"].map(RemoteProtocol.cleanName) ?? host
        pc = RemotePC(id: id, name: name, endpoint: .host(host, port: port))
        self.code = code
    }
}

/// Ошибка от ПК → текст для человека (по-русски; переводит `t()` на месте показа).
enum RemoteErrorText {
    static func russian(_ code: String) -> String {
        switch code {
        case "bad_code": "Код не подошёл — проверь цифры на экране ПК"
        case "code_expired", "no_code": "Код устарел — на ПК нажми «Привязать iPhone» ещё раз"
        case "code_burned": "Слишком много попыток — на ПК нажми «Привязать iPhone» ещё раз"
        case "not_paired": "ПК не узнал этот телефон — введи новый код"
        case "bad_version": "Обнови Sonar на ПК или на телефоне — версии пульта разные"
        default: "ПК не принял команду"
        }
    }
}
