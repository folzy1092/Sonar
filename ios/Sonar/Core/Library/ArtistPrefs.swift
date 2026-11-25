import Foundation

/// Вкус по артистам: «Чаще · Реже · Никогда» (docs/TASTE_ROOMS_PROMPT.md §1, настройка `wave.artist_prefs`) —
/// зеркало ПК `lib/artist-prefs-core.ts` и `wave.rs` `artist_prefs`. На ПК значение — объект JSON
/// `{ "<имя в нижнем регистре>": { "name": "Имя", "level": "more" | "less" | "never" } }`; `SettingValue` объектов не
/// хранит, поэтому на телефоне это тот же JSON строкой, а синк (`SettingsSyncAdapter`) переводит строку ⇄ объект.
/// `never` — артиста (и его соавторские) нет в волне и «Авто похожих», `more` / `less` — признак оценки ±1.
enum ArtistLevel: String, Codable, CaseIterable, Sendable {
    case more, less, never

    /// Подпись на кнопке (ключ перевода общий с ПК).
    var title: String {
        switch self {
        case .more: "вкус::Чаще"
        case .less: "вкус::Реже"
        case .never: "вкус::Никогда"
        }
    }
}

struct ArtistPref: Codable, Equatable, Sendable {
    var name: String
    var level: ArtistLevel
}

enum ArtistPrefs {
    static let key = "wave.artist_prefs"
    /// Вес признака «Чаще» / «Реже» в оценке волны (`wave.rs` `PREF_WEIGHT`).
    static let weight = 2.0

    /// Ключ артиста: нижний регистр без крайних пробелов (как `Track.artistKeys`).
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Разбор JSON: битые записи и чужие уровни пропускаются, ключ нормализуется.
    static func parse(_ json: JSONValue?) -> [String: ArtistPref] {
        guard case let .object(map)? = json else { return [:] }
        var out: [String: ArtistPref] = [:]
        for (k, entry) in map {
            guard case let .object(fields) = entry, let raw = fields["level"]?.string, let level = ArtistLevel(rawValue: raw) else { continue }
            let key = key(k)
            guard !key.isEmpty else { continue }
            let name = fields["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            out[key] = ArtistPref(name: name.isEmpty ? key : name, level: level)
        }
        return out
    }

    static func decode(_ raw: String) -> [String: ArtistPref] {
        guard let data = raw.data(using: .utf8), let json = try? JSONValue(data: data) else { return [:] }
        return parse(json)
    }

    static func json(_ prefs: [String: ArtistPref]) -> JSONValue {
        .object(prefs.mapValues { .object(["name": .string($0.name), "level": .string($0.level.rawValue)]) })
    }

    static func encode(_ prefs: [String: ArtistPref]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(json(prefs)) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Уровень трека по всем соавторам: `never` любого — `never`, иначе `more` перебивает `less` (`pref_of`).
    static func level(_ prefs: [String: ArtistPref], track: Track) -> ArtistLevel? {
        var best: ArtistLevel?
        for key in track.artistKeys {
            guard let level = prefs[key]?.level else { continue }
            if level == .never { return .never }
            if level == .more { best = .more } else if best == nil { best = .less }
        }
        return best
    }

    static func level(_ prefs: [String: ArtistPref], name: String) -> ArtistLevel? {
        prefs[key(name)]?.level
    }

    /// С уровнем артиста; nil — снять запись. Пустое имя — без изменений.
    static func with(_ prefs: [String: ArtistPref], name: String, level: ArtistLevel?) -> [String: ArtistPref] {
        let key = key(name)
        guard !key.isEmpty else { return prefs }
        var out = prefs
        out[key] = level.map { ArtistPref(name: name.trimmingCharacters(in: .whitespacesAndNewlines), level: $0) }
        return out
    }

    /// Для волны: «Чаще» / «Реже» — признак ±1, «Никогда» — набор для фильтра.
    static func split(_ prefs: [String: ArtistPref]) -> (pref: [String: Double], never: Set<String>) {
        var pref: [String: Double] = [:]
        var never = Set<String>()
        for (key, p) in prefs {
            switch p.level {
            case .more: pref[key] = 1
            case .less: pref[key] = -1
            case .never: never.insert(key)
            }
        }
        return (pref, never)
    }

    /// Список для экрана «Вкус»: по имени, с поиском по подстроке.
    static func list(_ prefs: [String: ArtistPref], query: String = "") -> [ArtistPrefRow] {
        let q = key(query)
        return prefs.map { ArtistPrefRow(id: $0.key, pref: $0.value) }
            .filter { q.isEmpty || $0.pref.name.lowercased().contains(q) }
            .sorted { $0.pref.name.localizedCaseInsensitiveCompare($1.pref.name) == .orderedAscending }
    }
}

/// Строка экрана «Вкус»: ключ артиста и запись.
struct ArtistPrefRow: Identifiable, Equatable, Sendable {
    let id: String
    let pref: ArtistPref
}

@MainActor
extension SettingsStore {
    /// Вкус по артистам из настройки (JSON строкой).
    var artistPrefs: [String: ArtistPref] {
        ArtistPrefs.decode(string(ArtistPrefs.key))
    }

    func setArtistPrefs(_ prefs: [String: ArtistPref]) {
        set(ArtistPrefs.key, .string(ArtistPrefs.encode(prefs)))
    }
}
