import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // тесты логики на Linux
#endif

// Last.fm (как Windows `windows/src-tauri/src/lastfm.rs`): вход в один клик и скробблинг прямо с
// телефона. Ключ и секрет приложения Last.fm подставляет CI в Info.plist (`SonarLastfmKey`,
// `SonarLastfmSecret` из секретов `SONAR_LASTFM_KEY` / `LASTFM_API_SECRET`); в репо их нет. Без них
// экран честно говорит, что Last.fm появится в сборке с ключом.

/// Ключ и секрет приложения Last.fm из сборки.
struct LastfmKeys: Equatable, Sendable {
    var key: String
    var secret: String

    static let keyName = "SonarLastfmKey"
    static let secretName = "SonarLastfmSecret"

    /// Из Info.plist; пусто или не подставлено (`$(SONAR_LASTFM_KEY)`) — нет ключа.
    static func from(info: [String: Any]?) -> LastfmKeys? {
        func clean(_ name: String) -> String? {
            guard let raw = (info?[name] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
            return raw
        }
        guard let key = clean(keyName), let secret = clean(secretName) else { return nil }
        return LastfmKeys(key: key, secret: secret)
    }

    static var bundled: LastfmKeys? { from(info: Bundle.main.infoDictionary) }
}

/// Сохранённый вход (Keychain).
struct LastfmSession: Codable, Equatable, Sendable {
    var name: String
    var key: String
    var avatarURL: String?
}

/// Трек для Last.fm.
struct LastfmTrack: Codable, Equatable, Sendable {
    var artist: String
    var title: String
    var album: String?
    var durationS: Int?
    /// Начало прослушивания, секунды Unix (для скроббла).
    var startedAt: Int

    init(artist: String, title: String, album: String? = nil, durationS: Int? = nil, startedAt: Int) {
        self.artist = artist
        self.title = title
        self.album = album
        self.durationS = durationS
        self.startedAt = startedAt
    }

    init(_ track: Track, startedAt: Date) {
        let main = track.artists.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(artist: main.isEmpty ? track.artist : main, title: track.title, album: track.album?.title,
                  durationS: track.durationMs > 0 ? track.durationMs / 1000 : nil,
                  startedAt: Int(startedAt.timeIntervalSince1970))
    }
}

/// Правила Last.fm (last.fm/api/scrobbling): трек длиннее 30 с; скроббл, когда прослушана половина
/// или 4 минуты — что раньше. Длительность неизвестна — после 4 минут.
enum LastfmRules {
    static let minDurationMs = 30_000
    static let maxThresholdMs = 240_000
    /// Старше 14 дней Last.fm не принимает.
    static let maxAge: TimeInterval = 14 * 86_400

    /// Сколько нужно прослушать; nil — трек слишком короткий, не скробблится.
    static func threshold(durationMs: Int) -> Int? {
        if durationMs <= 0 { return maxThresholdMs }
        if durationMs <= minDurationMs { return nil }
        return min(durationMs / 2, maxThresholdMs)
    }

    static func shouldScrobble(listenedMs: Int, durationMs: Int) -> Bool {
        guard let need = threshold(durationMs: durationMs) else { return false }
        return listenedMs >= need
    }
}

/// Подпись запроса: параметры по алфавиту «имязначение» подряд (без `format` и `callback`) + секрет → md5.
enum LastfmSign {
    static func signature(_ params: [String: String], secret: String) -> String {
        var text = ""
        for key in params.keys.sorted() where key != "format" && key != "callback" {
            text += key + (params[key] ?? "")
        }
        return MD5.hex(text + secret)
    }
}

struct LastfmError: Error, Equatable, LocalizedError {
    var code: Int
    var message: String

    /// Нет ключа приложения в сборке.
    static let noKeys = LastfmError(code: -1, message: "Last.fm появится в сборке с ключом")
    /// 9 — сессия недействительна (отозвали доступ на last.fm): нужно войти заново.
    var isInvalidSession: Bool { code == 9 }
    /// 11 / 16 / 29 — сервис недоступен или лимит: повторить позже.
    var isTemporary: Bool { [11, 16, 29, 0].contains(code) }

    var errorDescription: String? { message }
}

/// Отправка запроса (в тестах — подмена).
protocol LastfmTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

struct URLSessionLastfmTransport: LastfmTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Вызовы API Last.fm 2.0.
struct LastfmAPI: Sendable {
    static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    static let authPage = "https://www.last.fm/api/auth/"

    var keys: LastfmKeys
    var transport: LastfmTransport = URLSessionLastfmTransport()

    /// Готовый запрос: api_key, подпись, format=json; POST — формой.
    func request(_ params: [String: String], signed: Bool, post: Bool) -> URLRequest {
        var all = params
        all["api_key"] = keys.key
        if signed { all["api_sig"] = LastfmSign.signature(all, secret: keys.secret) }
        all["format"] = "json"
        let fields = all.keys.sorted().map { ($0, all[$0] ?? "") }
        var request: URLRequest
        if post {
            request = URLRequest(url: Self.endpoint, timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = HTTP.form(fields)
        } else {
            let url = (try? HTTP.url(Self.endpoint.absoluteString, query: fields)) ?? Self.endpoint
            request = URLRequest(url: url, timeoutInterval: 20)
        }
        request.setValue("Sonar/iOS", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Ответ JSON; `{"error": N, "message": …}` → `LastfmError`.
    func call(_ params: [String: String], signed: Bool = true, post: Bool = false) async throws -> [String: Any] {
        let (data, status) = try await transport.send(request(params, signed: signed, post: post))
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let code = json?["error"] as? Int {
            throw LastfmError(code: code, message: "Last.fm: \(json?["message"] as? String ?? "ошибка") (\(code))")
        }
        guard let json, (200 ..< 300).contains(status) else {
            throw LastfmError(code: 0, message: "Last.fm не ответил (\(status))")
        }
        return json
    }

    func getToken() async throws -> String {
        let json = try await call(["method": "auth.getToken"])
        guard let token = json["token"] as? String, !token.isEmpty else {
            throw LastfmError(code: 0, message: "Last.fm не выдал токен")
        }
        return token
    }

    /// Страница «Разрешить доступ»; после «Yes, allow access» Last.fm ведёт на callback с `?token=`.
    func authURL(token: String, callback: String) -> URL {
        (try? HTTP.url(Self.authPage, query: [("api_key", keys.key), ("token", token), ("cb", callback)]))
            ?? URL(string: Self.authPage)!
    }

    func getSession(token: String) async throws -> LastfmSession {
        let json = try await call(["method": "auth.getSession", "token": token])
        guard let session = json["session"] as? [String: Any], let name = session["name"] as? String,
              let key = session["key"] as? String else {
            throw LastfmError(code: 14, message: "Вход ещё не подтверждён")
        }
        return LastfmSession(name: name, key: key, avatarURL: nil)
    }

    /// Аватар — для карточки в настройках (самая большая картинка).
    func avatar(user: String) async -> String? {
        guard let json = try? await call(["method": "user.getInfo", "user": user], signed: false),
              let images = (json["user"] as? [String: Any])?["image"] as? [[String: Any]] else { return nil }
        return images.reversed().compactMap { ($0["#text"] as? String).flatMap { $0.isEmpty ? nil : $0 } }.first
    }

    static func trackParams(_ track: LastfmTrack, index: Int? = nil, timestamp: Bool) -> [String: String] {
        func name(_ base: String) -> String { index.map { "\(base)[\($0)]" } ?? base }
        var p = [name("artist"): track.artist, name("track"): track.title]
        if let album = track.album, !album.isEmpty { p[name("album")] = album }
        if let d = track.durationS, d > 0 { p[name("duration")] = String(d) }
        if timestamp { p[name("timestamp")] = String(track.startedAt) }
        return p
    }

    func nowPlaying(_ track: LastfmTrack, session: String) async throws {
        var p = Self.trackParams(track, timestamp: false)
        p["method"] = "track.updateNowPlaying"
        p["sk"] = session
        _ = try await call(p, post: true)
    }

    /// Скробблы пачкой (до 50 за запрос — правило Last.fm).
    func scrobble(_ tracks: [LastfmTrack], session: String) async throws {
        guard !tracks.isEmpty else { return }
        var p: [String: String] = ["method": "track.scrobble", "sk": session]
        for (i, track) in tracks.prefix(50).enumerated() {
            p.merge(Self.trackParams(track, index: tracks.count == 1 ? nil : i, timestamp: true)) { _, new in new }
        }
        _ = try await call(p, post: true)
    }
}
