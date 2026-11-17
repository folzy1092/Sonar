import Foundation
import Observation

/// Значение настройки — JSON-совместимое, как `settings` в `docs/DB.md` (ключ `раздел.имя`).
enum SettingValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else { self = .string(try container.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        }
    }
}

/// Настройки приложения: ключи и умолчания — те же, что в Windows (`windows/src/lib/settings.svelte.ts`,
/// `docs/SETTINGS.md`). Пока сервера нет — в UserDefaults одним JSON; с синком уйдут на сервер.
/// Сюда попадает только то, что можно синхронизировать: пара для подписи — в `SigningStore`.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    /// Умолчания. Новый раздел — сначала строка в SETTINGS.md, потом сюда.
    static let defaults: [String: SettingValue] = [
        "update.auto_check": .bool(true),
        "update.channel": .string("stable"),
        "appearance.animations": .bool(true),
        // потолок качества Яндекса: low 192 · medium 256 · high 320 · lossless FLAC
        "audio.quality": .string("lossless"),
        "audio.sc_via_yandex": .bool(true),
        // «Авто похожие» после очереди, как в SoundCloud
        "general.similar_autoplay": .bool(true),
        // режим «Моей волны»: own · hard · calm · sad · fun · new (`WaveMode`)
        "wave.mode": .string("own"),
        // текст песни (SETTINGS.md «Текст песни»): rawValue `LyricsMode` / `LyricsSize` / `LyricsTextStyle` / `LyricsAnimation`
        "lyrics.mode": .string("words"),
        "lyrics.size": .string("L"),
        "lyrics.style": .string("blur"),
        "lyrics.animation": .string("normal"),
    ]

    private static let storageKey = "sonar.settings"
    private var values: [String: SettingValue]
    @ObservationIgnored private let storage: UserDefaults

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        if let data = storage.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: SettingValue].self, from: data) {
            values = saved
        } else {
            values = [:]
        }
    }

    func value(_ key: String) -> SettingValue? {
        values[key] ?? Self.defaults[key]
    }

    func bool(_ key: String) -> Bool {
        if case let .bool(value)? = value(key) { return value }
        return false
    }

    func string(_ key: String) -> String {
        if case let .string(value)? = value(key) { return value }
        return ""
    }

    func set(_ key: String, _ value: SettingValue) {
        values[key] = value
        if let data = try? JSONEncoder().encode(values) {
            storage.set(data, forKey: Self.storageKey)
        }
    }

    func set(_ key: String, _ value: Bool) {
        set(key, .bool(value))
    }
}
