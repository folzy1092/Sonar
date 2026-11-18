import Foundation

// Экспорт плейлиста в файл (NEXT_PROMPT, этап 8) — те же правила, что на ПК (`windows/src/lib/export.ts`,
// имя файла — и `src-tauri/src/export.rs`): M3U8 (`#EXTINF:<сек>,<артист> - <название>` + ссылка на трек
// в сервисе), CSV (title, artist, album, duration, service, link, added) и JSON (массив `Track` как в
// docs/API.md + `added_at`). Только Foundation: текст файла и имя, лист «Поделиться» — `ExportSheet`.

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case m3u8, csv, json

    var id: String { rawValue }
    var fileExtension: String { rawValue }
    /// Название формата — его не переводят.
    var label: String { rawValue.uppercased() }
}

/// Трек списка и когда он добавлен (мс с 1970; у Любимых и плейлистов сервисов на iPhone — неизвестно).
struct ExportItem: Sendable {
    let track: Track
    let addedAt: Int64?
}

enum PlaylistExport {
    /// Длинное имя файла обрезаем (то же число на ПК — `MAX_NAME_CHARS`).
    static let maxNameChars = 100
    /// Имя, если от названия плейлиста ничего не осталось.
    static let fallbackName = "Sonar"
    static let csvColumns = ["title", "artist", "album", "duration", "service", "link", "added"]

    private static let forbidden = Set("<>:\"/\\|?*".unicodeScalars)
    private static let reserved: Set<String> = Set(
        ["con", "prn", "aux", "nul"] + (1...9).flatMap { ["com\($0)", "lpt\($0)"] }
    )
    /// Начало ячейки, которое Excel и Таблицы считают формулой. Сверяем первый Unicode scalar, а не
    /// `Character`: «\r\n» и «=» с комбинируемым знаком — один `Character`, но формула (как на ПК).
    private static let formulaStart = Set("=+-@\t\r".unicodeScalars)
    /// Что `encodeURIComponent` оставляет как есть.
    private static let uriComponent = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    // MARK: - Имя файла

    /// Название плейлиста → имя файла без расширения: запрещённые знаки и управляющие символы — пробел,
    /// пробелы схлопываются, точки и пробелы по краям убираются, до `maxNameChars` символов (Unicode scalar,
    /// как на ПК), имя устройства Windows (CON, NUL…) — с `_` в начале, пустое — `Sonar`.
    static func safeFileName(_ name: String) -> String {
        var replaced = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            let bad = forbidden.contains(scalar) || scalar.properties.generalCategory == .control
            replaced.append(bad ? " " : scalar)
        }
        let words = String(replaced).unicodeScalars
            .split(whereSeparator: { $0.properties.isWhitespace })
            .map { String(String.UnicodeScalarView($0)) }
        let collapsed = words.joined(separator: " ")
        let cut = String(String.UnicodeScalarView(collapsed.unicodeScalars.prefix(maxNameChars)))
        let trimmed = cut.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        guard !trimmed.isEmpty else { return fallbackName }
        let stem = (trimmed.split(separator: ".", omittingEmptySubsequences: false).first.map(String.init) ?? trimmed)
            .trimmingCharacters(in: .whitespaces)
        return reserved.contains(stem.lowercased()) ? "_" + trimmed : trimmed
    }

    // MARK: - Ссылки

    /// Ссылка на трек на сайте сервиса: своя ссылка трека (если http/https), иначе — по ref из реестра.
    /// У SoundCloud без ссылки и у локальных файлов — nil.
    static func trackWebURL(_ track: Track) -> String? {
        if let url = track.url, url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://") {
            return url
        }
        guard let parsed = ServiceRegistry.parse(ref: track.ref), parsed.kind == .track,
              let colon = track.ref.firstIndex(of: ":") else { return nil }
        let raw = String(track.ref[track.ref.index(after: colon)...])
        guard !raw.isEmpty, let id = raw.addingPercentEncoding(withAllowedCharacters: uriComponent) else { return nil }
        switch parsed.info.id {
        case .ym: return "https://music.yandex.ru/track/\(id)"
        case .yt: return "https://music.youtube.com/watch?v=\(id)"
        case .sp: return "https://open.spotify.com/track/\(id)"
        case .vk: return "https://vk.com/audio\(id)"
        case .sc, .local: return nil
        }
    }

    /// Название сервиса трека по реестру (как есть, без перевода).
    static func serviceName(_ ref: String) -> String {
        ServiceRegistry.parse(ref: ref)?.info.name ?? ""
    }

    // MARK: - Форматы

    /// M3U8 (UTF-8): заголовок, `#EXTINF:<сек>,<артист> - <название>`, следующей строкой — ссылка
    /// (нет ссылки — ref). Неизвестная длительность — `-1`.
    static func m3u8(name: String, items: [ExportItem]) -> String {
        var lines = ["#EXTM3U", "#PLAYLIST:\(oneLine(name))"]
        for item in items {
            let sec = seconds(item.track.durationMs)
            let label = [oneLine(item.track.artist), oneLine(item.track.title)].filter { !$0.isEmpty }.joined(separator: " - ")
            lines.append("#EXTINF:\(sec > 0 ? sec : -1),\(label)")
            lines.append(oneLine(trackWebURL(item.track) ?? item.track.ref))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Ячейка CSV по RFC 4180: в кавычках, если есть запятая, кавычка или перенос строки; кавычки
    /// удваиваются. `text` — пользовательский текст: начало-формулу гасим апострофом.
    static func csvCell(_ value: String, text: Bool = false) -> String {
        let safe = text && value.unicodeScalars.first.map(formulaStart.contains) == true ? "'" + value : value
        let needsQuotes = safe.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }
        guard needsQuotes else { return safe }
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// CSV: BOM (чтобы Excel узнал UTF-8), строки через CRLF. `duration` — секунды, `added` — дата
    /// ISO 8601 в UTC (пусто, если неизвестна), `service` — название сервиса (`label`).
    static func csv(items: [ExportItem], label: (String) -> String = serviceName) -> String {
        var rows = [csvColumns.joined(separator: ",")]
        for item in items {
            let track = item.track
            rows.append([
                csvCell(track.title, text: true),
                csvCell(track.artist, text: true),
                csvCell(track.album?.title ?? "", text: true),
                String(seconds(track.durationMs)),
                csvCell(label(track.ref), text: true),
                csvCell(trackWebURL(track) ?? ""),
                isoDate(item.addedAt),
            ].joined(separator: ","))
        }
        return "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"
    }

    /// JSON: массив `Track` в форме API.md + `added_at` (мс или null). Поля клиента (`plays`, `tags`,
    /// `loudness`) в файл не идут; ключи по алфавиту — один и тот же файл на любой версии iOS.
    static func json(items: [ExportItem]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(items.map(JSONRow.init))
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// Текст файла в нужном формате.
    static func text(_ format: ExportFormat, name: String, items: [ExportItem],
                     label: (String) -> String = serviceName) throws -> String {
        switch format {
        case .m3u8: return m3u8(name: name, items: items)
        case .csv: return csv(items: items, label: label)
        case .json: return try json(items: items)
        }
    }

    /// Записать файл `<имя плейлиста>.<формат>` в свою папку внутри `directory` (для листа «Поделиться»
    /// у каждого экспорта своя папка — имя файла остаётся названием плейлиста).
    static func write(_ format: ExportFormat, name: String, items: [ExportItem], in directory: URL,
                      label: (String) -> String = serviceName) throws -> URL {
        let text = try text(format, name: name, items: items, label: label)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(safeFileName(name) + "." + format.fileExtension)
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Помощники

    private static func oneLine(_ s: String) -> String {
        s.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func seconds(_ ms: Int) -> Int {
        ms > 0 ? Int((Double(ms) / 1000).rounded()) : 0
    }

    private static func isoDate(_ ms: Int64?) -> String {
        guard let ms else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    /// Строка JSON: поля `Track` из API.md (null пишется явно) + `added_at`.
    private struct JSONRow: Encodable {
        let item: ExportItem

        private enum Key: String, CodingKey {
            case ref, title, artist, artists, album, url, explicit, available
            case durationMs = "duration_ms"
            case coverURL = "cover_url"
            case addedAt = "added_at"
        }

        private struct Artist: Encodable {
            let ref: String
            let name: String
            let avatarURL: String?

            private enum Key: String, CodingKey {
                case ref, name
                case avatarURL = "avatar_url"
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: Key.self)
                try c.encode(ref, forKey: .ref)
                try c.encode(name, forKey: .name)
                try c.encode(avatarURL, forKey: .avatarURL)
            }
        }

        init(_ item: ExportItem) { self.item = item }

        func encode(to encoder: Encoder) throws {
            let track = item.track
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(track.ref, forKey: .ref)
            try c.encode(track.title, forKey: .title)
            try c.encode(track.artist, forKey: .artist)
            try c.encode(track.artists.map { Artist(ref: $0.ref, name: $0.name, avatarURL: $0.avatarURL) }, forKey: .artists)
            try c.encode(track.album, forKey: .album)
            try c.encode(track.durationMs, forKey: .durationMs)
            try c.encode(track.coverURL, forKey: .coverURL)
            try c.encode(track.url, forKey: .url)
            try c.encode(track.explicit, forKey: .explicit)
            try c.encode(track.available, forKey: .available)
            try c.encode(item.addedAt, forKey: .addedAt)
        }
    }
}
