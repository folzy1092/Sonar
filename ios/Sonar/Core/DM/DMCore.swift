import Foundation

// Личные сообщения (docs/DM.md) — порт ПК `windows/src/lib/dm/dm-core.ts`: вложения, ссылки `sonar://` в тексте,
// правка, удаление, прочитанность, ленты. Без сети; правила менять в обоих местах и в тестах (`DMCoreTests`).

enum DMAttachment: Hashable, Sendable {
    case track(ref: String, title: String, artist: String, coverURL: String?)
    case playlist(id: String, title: String, count: Int, coverURL: String?)
    case room(roomID: String, host: String, title: String)

    /// Куда ведёт: та же ссылка `sonar://`, что понимает `DeepLink`.
    var link: String {
        switch self {
        case let .track(ref, _, _, _): DMCore.link(.track, ref)
        case let .playlist(id, _, _, _): DMCore.link(.playlist, id)
        case let .room(roomID, _, _): DMCore.link(.room, roomID)
        }
    }
}

struct DMMessage: Hashable, Sendable, Identifiable {
    var id: String
    var threadID: String
    var from: String
    var text: String
    var attachments: [DMAttachment] = []
    var replyTo: String?
    var sentAt: Int
    var editedAt: Int?
    var deleted = false
}

struct DMThread: Hashable, Sendable, Identifiable {
    var id: String
    /// Собеседник; nil — чат комнаты.
    var peer: String?
    var roomID: String?
    /// До какого сообщения (sentAt) собеседник прочитал наши.
    var peerReadAt: Int
    /// До какого мы прочитали его.
    var myReadAt: Int
}

struct SonarLink: Hashable, Sendable {
    enum Kind: String, Sendable { case track, album, playlist, room, user }
    var kind: Kind
    var value: String
}

enum DraftError: Error, Equatable { case empty, tooLong, tooMany }

enum DMCore {
    static let maxText = 2000
    static let maxAttachments = 4
    /// Сколько сервер хранит сообщения (решение владельца 2026-11-25).
    static let retentionMs = 30 * 24 * 3_600_000

    /// Убрать сообщения старше срока хранения — так же их стирает сервер.
    static func dropExpired(_ messages: [DMMessage], now: Int) -> [DMMessage] {
        messages.filter { now - $0.sentAt <= retentionMs }
    }

    /// Своё можно править 48 часов.
    static let editWindowMs = 48 * 3_600_000

    static func link(_ kind: SonarLink.Kind, _ value: String) -> String {
        "sonar://\(kind.rawValue)/\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
    }

    /// Как `encodeURI` на ПК: буквы, цифры и `;,/?:@&=+$-_.!~*'()#` остаются как есть.
    private static let allowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789;,/?:@&=+$-_.!~*'()#")

    private static let pattern = try! NSRegularExpression(
        pattern: #"sonar://(track|album|playlist|room|user)/([^\s<>"'`]+)"#, options: [.caseInsensitive])

    /// Все ссылки `sonar://…` по порядку, без повторов; хвостовая пунктуация отрезается.
    static func parseLinks(_ text: String) -> [SonarLink] {
        let ns = text as NSString
        var out: [SonarLink] = []
        var seen = Set<String>()
        for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let kindRaw = ns.substring(with: m.range(at: 1)).lowercased()
            var raw = ns.substring(with: m.range(at: 2))
            while let last = raw.last, ".,;:!?)]".contains(last) { raw.removeLast() }
            guard !raw.isEmpty, let value = raw.removingPercentEncoding, !value.isEmpty,
                  let kind = SonarLink.Kind(rawValue: kindRaw) else { continue }
            let key = "\(kind.rawValue)/\(value)"
            if seen.insert(key).inserted { out.append(SonarLink(kind: kind, value: value)) }
        }
        return out
    }

    /// Проверить черновик: текст обрезается по краям, пустое без вложений не уходит, длина — в символах.
    static func checkDraft(_ text: String, attachments: [DMAttachment]) -> Result<String, DraftError> {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty && attachments.isEmpty { return .failure(.empty) }
        if clean.unicodeScalars.count > maxText { return .failure(.tooLong) }
        if attachments.count > maxAttachments { return .failure(.tooMany) }
        return .success(clean)
    }

    static func canEdit(_ msg: DMMessage, me: String, now: Int) -> Bool {
        msg.from == me && !msg.deleted && now - msg.sentAt <= editWindowMs
    }

    static func canDelete(_ msg: DMMessage, me: String) -> Bool { msg.from == me && !msg.deleted }

    static func edit(_ msg: DMMessage, me: String, text: String, now: Int) -> DMMessage? {
        guard canEdit(msg, me: me, now: now), case let .success(clean) = checkDraft(text, attachments: msg.attachments),
              clean != msg.text else { return nil }
        var next = msg
        next.text = clean
        next.editedAt = now
        return next
    }

    static func delete(_ msg: DMMessage, me: String) -> DMMessage? {
        guard canDelete(msg, me: me) else { return nil }
        var next = msg
        next.text = ""
        next.attachments = []
        next.deleted = true
        return next
    }

    static func unreadCount(_ thread: DMThread, _ messages: [DMMessage], me: String) -> Int {
        messages.filter { $0.threadID == thread.id && $0.from != me && !$0.deleted && $0.sentAt > thread.myReadAt }.count
    }

    static func seenByPeer(_ thread: DMThread, _ msg: DMMessage, me: String) -> Bool {
        msg.from == me && msg.sentAt <= thread.peerReadAt
    }

    /// Цитата ответа: первая строка до `max` символов; без текста — вложение; удалённое — nil.
    static func replyPreview(_ msg: DMMessage?, max: Int = 80) -> String? {
        guard let msg, !msg.deleted else { return nil }
        let line = (msg.text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "")
            .trimmingCharacters(in: .whitespaces)
        if !line.isEmpty {
            let scalars = Array(line.unicodeScalars)
            guard scalars.count > max else { return line }
            var cut = String.UnicodeScalarView()
            cut.append(contentsOf: scalars.prefix(max - 1))
            return String(cut) + "…"
        }
        switch msg.attachments.first {
        case let .track(_, title, artist, _)?: return "\(artist) — \(title)"
        case let .playlist(_, title, _, _)?: return title
        case let .room(_, _, title)?: return title
        case nil: return nil
        }
    }

    /// Лента треда по времени; повтор id — берём последний (сервер может прислать заново после обрыва).
    static func timeline(_ messages: [DMMessage], thread: String) -> [DMMessage] {
        var byID: [String: DMMessage] = [:]
        var order: [String] = []
        for m in messages where m.threadID == thread {
            if byID[m.id] == nil { order.append(m.id) }
            byID[m.id] = m
        }
        return order.compactMap { byID[$0] }.sorted { ($0.sentAt, $0.id) < ($1.sentAt, $1.id) }
    }

    /// Группы «один автор подряд» с разрывом не больше `gap`.
    static func groupRuns(_ messages: [DMMessage], gap: Int = 5 * 60_000) -> [[DMMessage]] {
        var runs: [[DMMessage]] = []
        for m in messages {
            if let prev = runs.last?.last, prev.from == m.from, m.sentAt - prev.sentAt <= gap {
                runs[runs.count - 1].append(m)
            } else {
                runs.append([m])
            }
        }
        return runs
    }
}
