import Foundation

/// Сборка, система и устройство — шапка отчёта. Пишется в `session.json` при каждом запуске, чтобы
/// отчёт показал ту сборку, что упала (после обновления текущая уже другая).
struct CrashDevice: Codable, Equatable, Sendable {
    var version: String
    var build: String
    /// `iOS 18.1.1`
    var system: String
    /// `iPhone15,2`; на симуляторе — модель, которую он изображает.
    var model: String
    /// Начало и конец сегмента `__TEXT` приложения в том запуске — чтобы разобрать адреса стека.
    var imageStart: UInt64?
    var imageEnd: UInt64?

    static func current(bundle: [String: Any]? = Bundle.main.infoDictionary) -> CrashDevice {
        let version = bundle?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let patch = os.patchVersion > 0 ? ".\(os.patchVersion)" : ""
        #if os(iOS)
        let system = "iOS \(os.majorVersion).\(os.minorVersion)\(patch)"
        #else
        let system = "\(ProcessInfo.processInfo.operatingSystemVersionString)"
        #endif
        return CrashDevice(version: version, build: build, system: system, model: machine())
    }

    private static func machine() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (симулятор)"
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// `Sonar 0.1.0 (сборка 239) · iOS 18.1 · iPhone15,2`
    var line: String { "Sonar \(version) (сборка \(build)) · \(system) · \(model)" }
}

/// Отчёт о сбое прошлого запуска: собирается при старте и лежит в `report.json`, пока его не
/// отправят или не закроют.
struct CrashReport: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var device: CrashDevice
    var crashedAt: Date
    var cause: CrashCause
    var marker: CrashMarker?
    /// Стек из обработчика сигнала, уже с именами (`CrashSymbolicator`) — или голые адреса.
    var stack: [String]
    /// Хвост журнала того запуска (до 500 строк).
    var journal: String
    var lastErrors: [String]
    var metric: [MetricCrash] = []

    /// Подпись под заголовком окна — ключ перевода (`t(report.summary)`).
    var summary: String { cause.summary }

    /// Имя файла: `sonar-ios-0.1.0-239-20261117-123456.log`.
    var fileName: String {
        "sonar-ios-\(device.version)-\(device.build)-\(Self.compact(crashedAt)).log"
    }

    /// Подпись к файлу в Telegram (не длиннее 1024 знаков — предел Bot API).
    var caption: String {
        var text = "💥 Падение \(device.line)\n\(cause.technical)"
        if let last = lastErrors.last { text += "\nпоследняя ошибка: \(last)" }
        if !metric.isEmpty { text += "\nMetricKit: \(metric.count)" }
        return String(text.prefix(1000))
    }

    /// Полный текст отчёта — как у ПК: шапка, причина, стек, последние ошибки, журнал.
    var text: String {
        var out: [String] = []
        out.append(device.line)
        out.append("Время сбоя: \(Self.iso(crashedAt)) UTC")
        out.append("Причина: \(cause.technical) — \(cause.summary)")
        if let marker, let name = marker.exceptionName {
            out.append("Исключение: \(name)\(marker.exceptionReason.map { ": \($0)" } ?? "")")
        }
        out.append("")
        if let symbols = marker?.exceptionSymbols, !symbols.isEmpty {
            out.append("== Стек исключения ==")
            out += symbols
            out.append("")
        }
        if !stack.isEmpty {
            out.append("== Стек (сигнал) ==")
            out += stack.enumerated().map { "\($0.offset)\t\($0.element)" }
            out.append("")
        }
        out.append("== Последние ошибки ==")
        out += lastErrors.isEmpty ? ["—"] : lastErrors
        out.append("")
        for (index, crash) in metric.enumerated() {
            out.append("== MetricKit \(index + 1) ==")
            out.append(crash.text)
            out.append("")
        }
        out.append("== Журнал ==")
        out.append(journal.isEmpty ? "—" : journal)
        return out.joined(separator: "\n") + "\n"
    }

    static func iso(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    static func compact(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    /// Собрать отчёт из того, что осталось от упавшего запуска.
    static func make(marker: CrashMarker, device: CrashDevice, journal: String, stack: [String], now: Date = Date()) -> CrashReport {
        let crashedAt = marker.time ?? now
        return CrashReport(id: "\(Int(crashedAt.timeIntervalSince1970))-\(marker.signal ?? 0)", device: device,
                           crashedAt: crashedAt, cause: marker.cause, marker: marker, stack: stack,
                           journal: LogTail.last(journal), lastErrors: LogTail.errors(journal))
    }

    /// Отчёт только из MetricKit (наш обработчик сбой не застал).
    static func make(metric: [MetricCrash], device: CrashDevice, at date: Date) -> CrashReport {
        var device = device
        if let first = metric.first {
            device.version = first.appVersion ?? device.version
            device.build = first.appBuild ?? device.build
            device.system = first.osVersion ?? device.system
            device.model = first.deviceType ?? device.model
        }
        return CrashReport(id: "mx-\(Int(date.timeIntervalSince1970))", device: device, crashedAt: date,
                           cause: metric.first?.cause ?? .system("?"), marker: nil, stack: [], journal: "",
                           lastErrors: [], metric: metric)
    }
}

/// Разбор адресов стека (кроме самого `dladdr`, он — в `CrashSignals.swift`): адрес внутри
/// приложения прошлого запуска → смещение `Sonar + 0x…`, по нему символизируется через `atos`.
enum CrashStack {
    /// Смещение адреса в образе приложения прошлого запуска, если адрес — его.
    static func offset(_ address: UInt64, start: UInt64?, end: UInt64?) -> UInt64? {
        guard let start, let end, address >= start, address < end else { return nil }
        return address - start
    }

    /// Строка кадра: `Sonar + 0x1a2b  имя` / `swift_retain + 12  (0x1a2b3c4d5)` / `0x1a2b3c4d5`.
    /// `crashed` — образ приложения в упавшем запуске, `current` — в этом (адреса сдвинуты ASLR);
    /// `symbol` ищет имя по адресу этого запуска (`dladdr`). Системные библиотеки лежат в общем кэше,
    /// его сдвиг меняется только при перезагрузке — их ищем по старому адресу.
    static func describe(_ address: UInt64, crashed: CrashDevice, current: CrashDevice?, symbol: (UInt64) -> String?) -> String {
        let hex = "0x" + String(address, radix: 16)
        if let offset = offset(address, start: crashed.imageStart, end: crashed.imageEnd) {
            let inSonar = "Sonar + 0x\(String(offset, radix: 16))"
            // символы приложения — только если это та же сборка
            guard let base = current?.imageStart, current?.build == crashed.build else { return inSonar }
            return symbol(base + offset).map { "\(inSonar)  \($0)" } ?? inSonar
        }
        return symbol(address).map { "\($0)  (\(hex))" } ?? hex
    }
}
