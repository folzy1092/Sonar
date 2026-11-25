import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Входы в сервисы на всех устройствах (SERVER_PROMPT этап 4, API.md «Сервисы») — порт `cred_sync.rs` ПК:
/// ключи из Keychain ↔ `GET/PUT /services/credentials`. **Правила слияния менять в обоих местах.**
///
/// Слияние трёхстороннее: рядом с сессией (`SessionVault.credBase`) лежит хэш того, что было на сервере после
/// прошлого обмена. Своё поменялось — едет на сервер, поменялся сервер — входим здесь, на одной стороне пропало,
/// а другая не менялась — отключаем и там. Первый обмен (базы нет) — своё побеждает, остальное берём с сервера.
/// Значения ключей не пишутся ни в журнал, ни в ошибки — только имена сервисов.
enum CredentialSync {
    /// Поля одного сервиса — как на сервере (`server/sonar/api/services.py` `FIELDS`), без пустых.
    typealias Fields = [String: String]
    /// Сервис → хэш полей на сервере после прошлого обмена.
    typealias Base = [String: String]

    /// Сервисы, которые знает сервер; остальные не синкаются.
    static let services: Set<String> = ["soundcloud", "yandex", "youtube", "spotify"]

    /// Своё подключение: поля и имя аккаунта (сервер показывает его в «Сервисах» других устройств).
    struct Local: Equatable, Sendable {
        var fields: Fields
        var name: String?
    }

    enum Step: Equatable, Sendable {
        /// Своё — на сервер.
        case push(String)
        /// Отключили здесь — убрать и с сервера.
        case delete(String)
        /// С сервера — войти здесь.
        case apply(String)
        /// Отключили на другом устройстве — отключить здесь.
        case forget(String)

        var service: String {
            switch self {
            case let .push(s), let .delete(s), let .apply(s), let .forget(s): s
            }
        }
    }

    static func hash(_ fields: Fields) -> String {
        let canon = fields.keys.sorted().map { "\($0)=\(fields[$0] ?? "")" }.joined(separator: "\n")
        return SHA256.hash(data: Data(canon.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Что сделать по каждому сервису. Вся логика слияния — здесь (как `plan` в `cred_sync.rs`).
    static func plan(local: [String: Fields], remote: [String: Fields], base: Base) -> [Step] {
        Set(local.keys).union(remote.keys).sorted().compactMap { svc in
            let was = base[svc]
            switch (local[svc].map(hash), remote[svc].map(hash)) {
            case let (l?, r?) where l == r: return nil
            case let (l?, _?) where was == l: return .apply(svc)
            case (_?, _?): return .push(svc)
            case let (l?, nil) where was == l: return .forget(svc)
            case (_?, nil): return .push(svc)
            case let (nil, r?) where was == r: return .delete(svc)
            case (nil, _?): return .apply(svc)
            case (nil, nil): return nil
            }
        }
    }

    /// База после обмена: хэш того, что теперь на сервере. `failed` — где войти по ключу с сервера не вышло
    /// (правило — в цикле ниже).
    static func nextBase(local: [String: Fields], remote: [String: Fields], old: Base, steps: [Step],
                         failed: Set<String>) -> Base {
        var out: Base = [:]
        for svc in Set(local.keys).union(remote.keys) {
            // не вошли по ключу с сервера (сейчас или пропущен как уже не прошедший):
            // свой есть — базы нет, следующий обмен зальёт свой рабочий вместо протухшего;
            // своего нет — база прежняя, иначе следующий обмен решит «у меня отключили» и удалит вход для всех
            if failed.contains(svc) {
                if local[svc] == nil, let h = old[svc] { out[svc] = h }
                continue
            }
            let h: String?
            switch steps.first(where: { $0.service == svc }) {
            case nil: h = remote[svc].map(hash)
            case .push?: h = local[svc].map(hash)
            case .apply?: h = remote[svc].map(hash)
            case .delete?, .forget?: h = nil
            }
            if let h { out[svc] = h }
        }
        return out
    }

    /// Ответ `GET /services/credentials` → только известные сервисы.
    static func known(_ remote: [String: Fields]) -> [String: Fields] {
        remote.filter { services.contains($0.key) }
    }

    /// Тело `PUT /services/credentials`: своё с именем аккаунта, отключённое — `null`. Пусто — PUT не нужен.
    static func pushBody(steps: [Step], local: [String: Local]) -> [String: Fields?] {
        var body: [String: Fields?] = [:]
        for step in steps {
            switch step {
            case let .push(svc):
                guard let mine = local[svc] else { continue }
                var value = mine.fields
                if let name = mine.name { value["name"] = name }
                body[svc] = .some(value)
            case let .delete(svc):
                body[svc] = .some(nil)
            case .apply, .forget:
                continue
            }
        }
        return body
    }

    /// Поля без пробелов по краям и без пустых — как `cred_snapshot` ПК.
    static func clean(_ raw: [String: String?]) -> Fields {
        raw.compactMapValues { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.value.isEmpty }
    }
}

/// Где живут ключи сервисов: в приложении — `MusicCore` + `SpotifyCore`, в тестах — подставной.
protocol CredentialHost: Sendable {
    func snapshot() async -> [String: CredentialSync.Local]
    func apply(_ service: String, _ fields: CredentialSync.Fields) async throws
    func forget(_ service: String) async
}

/// Обмен входами с сервером. Один на приложение: обмен после входа и по таймеру не идут одновременно.
actor CredentialSyncer {
    static let shared = CredentialSyncer(host: LiveCredentialHost())

    private let host: CredentialHost
    private var running = false
    /// Не вошли по пришедшему ключу (протух, сервис лежит) — тот же ключ до перезапуска больше не пробуем.
    private var tried: Set<String> = []

    init(host: CredentialHost) {
        self.host = host
    }

    /// Вышли из аккаунта или вошли в другой — прошлые неудачи ни о чём не говорят (базу стирает `SessionVault`).
    func reset() {
        tried.removeAll()
    }

    /// Один обмен. → true, если здесь что-то подключилось или отключилось.
    func run(client: APIClient, vault: SessionVault) async throws -> Bool {
        guard !running else { return false }
        running = true
        defer { running = false }

        let localFull = await host.snapshot()
        let local = localFull.mapValues(\.fields)
        let remote = CredentialSync.known(try await client.send("GET", "services/credentials", as: [String: CredentialSync.Fields].self))
        let old = vault.credBase
        var steps = CredentialSync.plan(local: local, remote: remote, base: old)
        var failed = Set<String>()
        steps.removeAll { step in
            guard case let .apply(svc) = step, let fields = remote[svc],
                  tried.contains(Self.key(svc, fields)) else { return false }
            failed.insert(svc)
            return true
        }

        let body = CredentialSync.pushBody(steps: steps, local: localFull)
        if !body.isEmpty { try await client.call("PUT", "services/credentials", body: body) }

        var changed = false
        for step in steps {
            switch step {
            case let .apply(svc):
                guard let fields = remote[svc] else { continue }
                do {
                    try await host.apply(svc, fields)
                    changed = true
                } catch {
                    CrashLog.warn("вход в \(svc) с другого устройства не прошёл")
                    tried.insert(Self.key(svc, fields))
                    failed.insert(svc)
                }
            case let .forget(svc):
                await host.forget(svc)
                changed = true
            case .push, .delete:
                continue
            }
        }
        // за время обмена могли выйти из аккаунта — тогда базу не пишем (её уже стёр выход)
        if let token = vault.token, token == client.token {
            vault.credBase = CredentialSync.nextBase(local: local, remote: remote, old: old, steps: steps, failed: failed)
        }
        return changed
    }

    private static func key(_ svc: String, _ fields: CredentialSync.Fields) -> String {
        "\(svc):\(CredentialSync.hash(fields))"
    }
}

/// Ключи сервисов в приложении: SoundCloud, Яндекс, YouTube — `MusicCore`, Spotify — `SpotifyCore`.
struct LiveCredentialHost: CredentialHost {
    func snapshot() async -> [String: CredentialSync.Local] {
        var out = await MusicCore.shared.credentialSnapshot()
        if let spotify = await SpotifyCore.shared.credentialSnapshot() { out["spotify"] = spotify }
        return out
    }

    func apply(_ service: String, _ f: CredentialSync.Fields) async throws {
        switch service {
        case "soundcloud":
            _ = try await MusicCore.shared.connectSoundCloud(SoundCloudCreds(clientId: f["client_id"] ?? "", oauthToken: f["oauth_token"]))
        case "yandex": _ = try await MusicCore.shared.connectYandex(token: f["token"] ?? "")
        case "youtube": _ = try await MusicCore.shared.connectYouTube(cookie: f["cookie"] ?? "")
        case "spotify": _ = try await SpotifyCore.shared.connect(spDc: f["sp_dc"] ?? "")
        default: throw ServiceError(message: "Неизвестный сервис")
        }
    }

    func forget(_ service: String) async {
        if service == "spotify" {
            await SpotifyCore.shared.disconnect()
        } else if let svc = Service(rawValue: service) {
            await MusicCore.shared.disconnect(svc)
        }
    }
}

extension Notification.Name {
    /// Вход в сервис пришёл или ушёл с другого устройства — экраны перечитывают состояние сервисов.
    static let servicesChanged = Notification.Name("sonar.services.changed")
}
