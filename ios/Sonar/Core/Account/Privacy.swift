import Foundation

// Аккаунт → Приватность (решение владельца 2026-11-18), порт ПК `lib/public-profile.ts` и
// `pages/settings/Privacy.svelte`: кто что видит по ссылке на профиль и кто может позвать в друзья.
// До сервера это только настройки `privacy.*` (docs/SETTINGS.md); сервер потом отдаёт профиль по тем же ключам.
// `privacy.hidden_playlists` (скрыть один плейлист) — только на ПК: у настроек iPhone нет списков.

/// Кому открыт раздел профиля.
enum Audience: String, CaseIterable, Sendable, Identifiable {
    case everyone, friends, nobody

    var id: String { rawValue }

    /// Ключ перевода (`t(...)`).
    var title: String {
        switch self {
        case .everyone: "Все"
        case .friends: "Друзья"
        case .nobody: "Никто"
        }
    }

    /// Из значения настройки, как ПК `audienceOf`: строка как есть, старое «да / нет» — все / никто,
    /// остальное — все.
    static func of(_ value: SettingValue?) -> Audience {
        switch value {
        case let .bool(on)?: on ? .everyone : .nobody
        case let .string(raw)?: Audience(rawValue: raw) ?? .everyone
        default: .everyone
        }
    }

    /// Видит ли смотрящий (ПК `canSee`): «Все» — любой, «Друзья» — только друг.
    func visible(toFriend isFriend: Bool) -> Bool {
        self == .everyone || (self == .friends && isFriend)
    }
}

/// Кто может отправить заявку в друзья.
enum FriendRequests: String, CaseIterable, Sendable, Identifiable {
    case everyone, fof, nobody

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone: "Все"
        case .fof: "Друзья друзей"
        case .nobody: "Никто"
        }
    }

    static func of(_ value: SettingValue?) -> FriendRequests {
        if case let .string(raw)? = value { return FriendRequests(rawValue: raw) ?? .everyone }
        return .everyone
    }

    /// Можно ли позвать в друзья (ПК `canRequestFriend`): «Друзья друзей» — только при общих друзьях.
    func allows(hasMutualFriends: Bool) -> Bool {
        self == .everyone || (self == .fof && hasMutualFriends)
    }
}

/// Ключи и строки экрана «Приватность» — порядок как на ПК.
enum PrivacyKey {
    static let friendRequests = "privacy.friend_requests"

    struct Row: Identifiable, Sendable {
        let key: String
        /// Ключи перевода.
        let title: String
        let hint: String
        /// Только «Друзья» и «Никто» (личные сообщения — только между друзьями, антиспам).
        var friendsOnly = false
        var id: String { key }

        var audiences: [Audience] { friendsOnly ? [.friends, .nobody] : Audience.allCases }
    }

    static let rows: [Row] = [
        Row(key: "privacy.playlists", title: "Плейлисты", hint: "Все плейлисты разом"),
        Row(key: "privacy.likes", title: "Любимые", hint: "Треки с лайком"),
        Row(key: "privacy.now_playing", title: "Что играет сейчас", hint: "Трек, который звучит прямо сейчас"),
        Row(key: "privacy.stats", title: "Статистика", hint: "Прослушивания, часы и любимые артисты"),
    ]

    /// Комнаты и сообщения — по умолчанию «Друзья», порядок как на ПК.
    static let social: [Row] = [
        Row(key: "privacy.messages", title: "Кто может писать мне", hint: "Личные сообщения и треки от других", friendsOnly: true),
        Row(key: "privacy.room_invites", title: "Кто может звать в комнату", hint: "Приглашения слушать вместе"),
        Row(key: "privacy.room_visible", title: "Кто видит мою комнату", hint: "Можно зайти без приглашения"),
    ]
}
