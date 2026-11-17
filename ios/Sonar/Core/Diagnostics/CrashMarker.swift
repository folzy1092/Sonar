import Foundation

// Маркер сбоя — файл `crash.marker`, открытый заранее при запуске. Пишут его обработчики
// (`CrashSignals.swift`): необработанное исключение Objective-C и сигнал (в обработчике сигнала —
// только `write()` в готовый дескриптор, поэтому формат простой построчный). Пустой файл — сбоя не было.
//
//   exception NSInvalidArgumentException
//   reason -[__NSArrayM objectAtIndex:]: index 3 beyond bounds
//   symbols
//   0   CoreFoundation   0x00000001a1b2c3d4 __exceptionPreprocess + 164
//   end-symbols
//   signal 6
//   time 1763380000
//   frames
//   0x00000001a2b3c4d5
//   end
//
// Исключение кончается `abort()` → SIGABRT, поэтому обычно в маркере есть и то и другое.

/// Что известно о сбое из маркера.
struct CrashMarker: Equatable, Sendable, Codable {
    var signal: Int32?
    var exceptionName: String?
    var exceptionReason: String?
    /// Стек исключения (`callStackSymbols`) — уже с именами.
    var exceptionSymbols: [String] = []
    /// Адреса стека из обработчика сигнала.
    var frames: [UInt64] = []
    var time: Date?

    var isEmpty: Bool { signal == nil && exceptionName == nil }

    /// Разобрать текст маркера; ничего внятного — `nil`.
    static func parse(_ text: String) -> CrashMarker? {
        var marker = CrashMarker()
        var mode: Mode = .head
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            switch mode {
            case .symbols:
                if line == "end-symbols" { mode = .head } else { marker.exceptionSymbols.append(line) }
                continue
            case .frames:
                if line == "end" { mode = .head; continue }
                let hex = line.hasPrefix("0x") ? String(line.dropFirst(2)) : line
                if let address = UInt64(hex, radix: 16) { marker.frames.append(address); continue }
                mode = .head // обрыв на полуслове — дальше разбираем как заголовок
            case .head:
                break
            }
            let (key, value) = split(line)
            switch key {
            case "signal": marker.signal = Int32(value)
            case "time": if let s = TimeInterval(value) { marker.time = Date(timeIntervalSince1970: s) }
            case "exception": marker.exceptionName = value.isEmpty ? nil : value
            case "reason": marker.exceptionReason = value.isEmpty ? nil : value
            case "symbols": mode = .symbols
            case "frames": mode = .frames
            default: break
            }
        }
        return marker.isEmpty ? nil : marker
    }

    private enum Mode { case head, symbols, frames }

    private static func split(_ line: String) -> (String, String) {
        guard let space = line.firstIndex(of: " ") else { return (line, "") }
        return (String(line[..<space]), String(line[line.index(after: space)...]))
    }

    /// Строки маркера для исключения — их пишет обработчик исключений (не сигнала, там можно Foundation).
    static func exceptionBlock(name: String, reason: String?, symbols: [String]) -> String {
        func flat(_ s: String) -> String { s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ⏎ ") }
        var out = "exception \(flat(name))\n"
        if let reason, !reason.isEmpty { out += "reason \(flat(reason))\n" }
        out += "symbols\n"
        for symbol in symbols { out += flat(symbol) + "\n" }
        out += "end-symbols\n"
        return out
    }

    var cause: CrashCause {
        if let exceptionName { return .exception(name: exceptionName, reason: exceptionReason) }
        return .signal(signal ?? 0)
    }
}

/// Причина сбоя — для подписи в окне и заголовка отчёта.
enum CrashCause: Equatable, Sendable, Codable {
    case signal(Int32)
    case exception(name: String, reason: String?)
    /// Известно только из MetricKit (наш обработчик не успел: нехватка памяти, сторож iOS и т.п.).
    case system(String)

    /// Имя сигнала: 11 → `SIGSEGV`.
    static func signalName(_ signal: Int32) -> String {
        switch signal {
        case 4: "SIGILL"
        case 5: "SIGTRAP"
        case 6: "SIGABRT"
        case 8: "SIGFPE"
        case 9: "SIGKILL"
        case 10: "SIGBUS"
        case 11: "SIGSEGV"
        case 13: "SIGPIPE"
        default: "сигнал \(signal)"
        }
    }

    /// Человеческим языком, по-русски — это ключ перевода: интерфейс показывает `t(cause.summary)`.
    /// Номера сигналов — Darwin (на iOS SIGBUS = 10).
    var summary: String {
        switch self {
        case let .signal(signal):
            switch signal {
            case 11, 10: "Обращение к памяти, которой уже нет"
            case 6: "Sonar остановил сам себя после внутренней ошибки"
            case 5: "Сработала проверка в коде — что-то пошло не по плану"
            case 4: "Процессор встретил недопустимую команду"
            case 8: "Ошибка в вычислениях (например, деление на ноль)"
            case 9: "iOS принудительно закрыла Sonar"
            default: "Sonar неожиданно закрылся"
            }
        case .exception: "Внутренняя ошибка в системной части приложения"
        case .system: "iOS закрыла Sonar"
        }
    }

    /// Техническая строка: `SIGSEGV (11)`, `NSRangeException: …` — показывается мелко и в отчёте.
    var technical: String {
        switch self {
        case let .signal(signal): "\(Self.signalName(signal)) (\(signal))"
        case let .exception(name, reason): reason.map { "\(name): \($0)" } ?? name
        case let .system(text): text
        }
    }
}
