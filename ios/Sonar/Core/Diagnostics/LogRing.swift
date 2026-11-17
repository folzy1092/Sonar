import Foundation

// Кольцевой журнал событий (как `session.log` на ПК, `windows/src-tauri/src/crashlog.rs`): последние
// ~500 строк «время уровень текст». Держится в памяти и дописывается на диск фоновой очередью
// (`CrashLog`); после сбоя хвост журнала уходит в отчёт.

/// Уровень строки журнала. Ширина — 5 знаков, как на ПК (`INFO `, `ERROR`).
enum LogLevel: String, Codable, Sendable, CaseIterable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case crash = "CRASH"

    var padded: String { rawValue.padding(toLength: 5, withPad: " ", startingAt: 0) }
}

/// Одна строка журнала.
struct LogLine: Equatable, Sendable {
    var at: Date
    var level: LogLevel
    var text: String

    /// `12:34:56.789 ERROR текст` (UTC, как на ПК); переносы строк — с отступом под текст.
    var formatted: String {
        "\(LogLine.stamp(at)) \(level.padded) \(text.replacingOccurrences(of: "\n", with: "\n                   "))"
    }

    /// Время `HH:mm:ss.SSS` в UTC без форматтера (быстро и одинаково на любой локали).
    static func stamp(_ date: Date) -> String {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
        let s = ms / 1000
        func two(_ v: Int64) -> String { v < 10 ? "0\(v)" : "\(v)" }
        let milli = ms % 1000
        let m3 = milli < 10 ? "00\(milli)" : milli < 100 ? "0\(milli)" : "\(milli)"
        return "\(two((s / 3600) % 24)):\(two((s / 60) % 60)):\(two(s % 60)).\(m3)"
    }

    /// Разобрать строку из файла журнала; продолжение многострочной записи — `nil`.
    static func parse(_ raw: String) -> LogLine? {
        let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 12, parts[0].dropFirst(8).first == "." else { return nil }
        let rest = parts[1]
        let levelRaw = rest.prefix(5).trimmingCharacters(in: .whitespaces)
        guard let level = LogLevel(rawValue: levelRaw) else { return nil }
        let text = rest.count > 6 ? String(rest.dropFirst(6)) : ""
        return LogLine(at: .distantPast, level: level, text: text)
    }
}

/// Кольцевой буфер строк фиксированной ёмкости. Не потокобезопасен — живёт на очереди `CrashLog`.
struct LogRing: Sendable {
    static let defaultCapacity = 500
    /// Сколько последних ошибок держать отдельно (для «Последние ошибки» в отчёте).
    static let errorCapacity = 20
    /// Одна запись не длиннее — бесконечный текст ошибки не должен съесть журнал.
    static let maxLineLength = 2000

    let capacity: Int
    private var storage: [LogLine] = []
    private var head = 0
    private(set) var errors: [LogLine] = []
    /// Сколько строк записано за всё время (вытесненные тоже).
    private(set) var total = 0

    init(capacity: Int = LogRing.defaultCapacity) {
        self.capacity = max(1, capacity)
        storage.reserveCapacity(self.capacity)
    }

    mutating func append(_ line: LogLine) {
        var line = line
        if line.text.count > Self.maxLineLength {
            line.text = String(line.text.prefix(Self.maxLineLength)) + "…"
        }
        total += 1
        if storage.count < capacity {
            storage.append(line)
        } else {
            storage[head] = line
            head = (head + 1) % capacity
        }
        if line.level == .error || line.level == .crash {
            errors.append(line)
            if errors.count > Self.errorCapacity { errors.removeFirst(errors.count - Self.errorCapacity) }
        }
    }

    /// Строки от старой к новой.
    var lines: [LogLine] {
        storage.count < capacity ? storage : Array(storage[head...] + storage[..<head])
    }

    var count: Int { storage.count }

    /// Весь буфер текстом — для перезаписи файла журнала, когда он вырос.
    var text: String { lines.map(\.formatted).joined(separator: "\n") + (storage.isEmpty ? "" : "\n") }
}

enum LogTail {
    /// Последние `limit` записей файла журнала (многострочные записи — целиком).
    static func last(_ text: String, limit: Int = LogRing.defaultCapacity) -> String {
        var records: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if LogLine.parse(line) != nil || records.isEmpty {
                if !line.isEmpty || !records.isEmpty { records.append(line) }
            } else if !line.isEmpty {
                records[records.count - 1] += "\n" + line
            }
        }
        return records.suffix(limit).joined(separator: "\n")
    }

    /// Строки ошибок из текста журнала (последние `limit`).
    static func errors(_ text: String, limit: Int = LogRing.errorCapacity) -> [String] {
        let found = text.split(separator: "\n").map(String.init).filter { line in
            guard let parsed = LogLine.parse(line) else { return false }
            return parsed.level == .error || parsed.level == .crash
        }
        return Array(found.suffix(limit))
    }
}
