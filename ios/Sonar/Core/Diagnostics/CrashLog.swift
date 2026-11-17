import Foundation

// Журнал сбоев на iPhone (решение владельца 2026-11-17, как на ПК — `crashlog.rs`):
// • `CrashLog.note("…")` / `.warn` / `.error` — строка в кольцевой журнал (последние 500), с любого
//   потока; запись на диск — фоновой очередью, главный поток не ждёт;
// • сбой (исключение Objective-C, сигнал) — маркер `crash.marker` (`CrashSignals.swift`), iOS сама
//   пишет `MXCrashDiagnostic` (`MetricCrash.swift`);
// • следующий запуск: маркер + хвост журнала + сведения о сборке → `report.json`, окно
//   «Sonar закрылся с ошибкой» (`Features/Crash/CrashReportSheet.swift`). Отправили или закрыли —
//   отчёт снимается.
//
// Папка — `Application Support/Diagnostics`: `session.log` (журнал этого запуска), `session.json`
// (сборка и адрес образа), `crash.marker`, `report.json` (ждущий отчёт), `handled.json` (когда были
// уже разобранные сбои — чтобы MetricKit не показал тот же сбой второй раз).

enum CrashLog {
    /// Запустить журнал: разобрать прошлый запуск и поставить обработчики. Вызывать первым делом
    /// при старте приложения (`init()` у `App`), один раз.
    static func start() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        var device = DeviceInfo.current()
        let image = CrashSignals.imageRange()
        device.imageStart = image?.start
        device.imageEnd = image?.end
        let dir = base.appendingPathComponent("Diagnostics", isDirectory: true)
        Journal.shared.start(directory: dir, device: device, symbol: CrashSignals.symbol)
        CrashSignals.install(markerPath: dir.appendingPathComponent(Journal.markerName).path)
        #if canImport(MetricKit) && os(iOS)
        MetricKitReceiver.shared.start()
        #endif
    }

    /// Событие: запуск, смена экрана или трека — коротко, по-русски или идентификатором.
    static func note(_ text: String) { Journal.shared.append(.info, text) }

    /// Что-то пошло не так, но работаем дальше (повтор запроса, запасной источник).
    static func warn(_ text: String) { Journal.shared.append(.warn, text) }

    /// Ошибка (сеть, плеер, разбор ответа) — попадает и в «Последние ошибки» отчёта.
    static func error(_ text: String) { Journal.shared.append(.error, text) }

    /// Ошибка с местом: `CrashLog.error(error, "плеер: ссылка потока")`.
    static func error(_ error: any Error, _ context: String) {
        Journal.shared.append(.error, "\(context): \(String(describing: error))")
    }

    /// Отчёт о сбое прошлого запуска, если он ждёт решения.
    static var pendingReport: CrashReport? { Journal.shared.pending }

    /// Отчёт отправлен или закрыт — снять его.
    static func dismiss() { Journal.shared.dismiss() }

    /// Файл отчёта во временной папке — для «Поделиться».
    static func exportFile(_ report: CrashReport) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(report.fileName)
        try Data(report.text.utf8).write(to: url, options: .atomic)
        return url
    }

    /// Сбои от MetricKit — к ждущему отчёту или отдельным отчётом.
    static func attach(metric: [MetricCrash], from: Date, to: Date) {
        Journal.shared.attach(metric: metric, from: min(from, to), to: max(from, to))
    }

    /// Пост на главном потоке, когда ждущий отчёт появился, изменился или снят.
    static let didChange = Notification.Name("SonarCrashReportDidChange")
}

/// Журнал и файлы отчёта. Всё дисковое — на своей последовательной очереди.
final class Journal: @unchecked Sendable {
    static let shared = Journal()

    static let sessionName = "session.log"
    static let metaName = "session.json"
    static let markerName = "crash.marker"
    static let reportName = "report.json"
    static let handledName = "handled.json"
    /// Файл журнала больше — переписываем его из кольца (на диске тоже не больше ~500 строк с запасом).
    static let maxFileBytes = 256 * 1024

    private let queue = DispatchQueue(label: "com.folzy.sonar.crashlog", qos: .utility)
    private let lock = NSLock()
    // поля ниже — только на `queue`
    private var ring: LogRing
    private var directory: URL?
    private var device: DeviceInfo?
    private var handle: FileHandle?
    private var written = 0
    // под `lock`
    private var pendingReport: CrashReport?
    /// Вызывается на главном потоке при смене ждущего отчёта (по умолчанию — уведомление).
    var onChange: @Sendable () -> Void = {
        NotificationCenter.default.post(name: CrashLog.didChange, object: nil)
    }

    init(capacity: Int = LogRing.defaultCapacity) {
        ring = LogRing(capacity: capacity)
    }

    var pending: CrashReport? {
        lock.lock()
        defer { lock.unlock() }
        return pendingReport
    }

    private func setPending(_ report: CrashReport?) {
        lock.lock()
        pendingReport = report
        lock.unlock()
        let notify = onChange
        DispatchQueue.main.async { notify() }
    }

    private func url(_ name: String) -> URL? { directory?.appendingPathComponent(name) }

    /// Разобрать прошлый запуск и начать новый журнал. Синхронно: к возврату `pending` уже известен.
    func start(directory: URL, device: DeviceInfo, symbol: @escaping (UInt64) -> String? = { _ in nil }) {
        queue.sync {
            let fm = FileManager.default
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            self.directory = directory
            self.device = device
            let decoder = JSONDecoder()

            var report = (try? Data(contentsOf: directory.appendingPathComponent(Self.reportName)))
                .flatMap { try? decoder.decode(CrashReport.self, from: $0) }
            let markerText = (try? String(contentsOf: directory.appendingPathComponent(Self.markerName), encoding: .utf8)) ?? ""
            if let marker = CrashMarker.parse(markerText) {
                let previous = (try? Data(contentsOf: directory.appendingPathComponent(Self.metaName)))
                    .flatMap { try? decoder.decode(DeviceInfo.self, from: $0) } ?? device
                let journal = (try? String(contentsOf: directory.appendingPathComponent(Self.sessionName), encoding: .utf8)) ?? ""
                let stack = marker.frames.map { CrashStack.describe($0, crashed: previous, current: device, symbol: symbol) }
                report = CrashReport.make(marker: marker, device: previous, journal: journal, stack: stack)
                save(report)
            }
            try? fm.removeItem(at: directory.appendingPathComponent(Self.markerName))
            if let meta = try? JSONEncoder().encode(device) {
                try? meta.write(to: directory.appendingPathComponent(Self.metaName), options: .atomic)
            }
            // новый журнал: то, что записали до start(), и строка запуска
            ring.append(LogLine(at: Date(), level: .info, text: device.line))
            let session = directory.appendingPathComponent(Self.sessionName)
            let text = ring.text
            try? Data(text.utf8).write(to: session, options: .atomic)
            written = text.utf8.count
            handle = try? FileHandle(forWritingTo: session)
            _ = try? handle?.seekToEnd()
            if let report { setPending(report) }
        }
    }

    func append(_ level: LogLevel, _ text: String) {
        let line = LogLine(at: Date(), level: level, text: text)
        queue.async { self.write(line) }
    }

    private func write(_ line: LogLine) {
        ring.append(line)
        guard let handle else { return }
        let data = Data((line.formatted + "\n").utf8)
        if written + data.count > Self.maxFileBytes, let session = url(Self.sessionName) {
            try? handle.close()
            let text = ring.text
            try? Data(text.utf8).write(to: session, options: .atomic)
            written = text.utf8.count
            self.handle = try? FileHandle(forWritingTo: session)
            _ = try? self.handle?.seekToEnd()
            return
        }
        try? handle.write(contentsOf: data)
        written += data.count
    }

    /// Дождаться записи (тесты).
    func flush() { queue.sync {} }

    /// Строки журнала в памяти (тесты, отладка).
    var lines: [LogLine] { queue.sync { ring.lines } }

    private func save(_ report: CrashReport?) {
        guard let file = url(Self.reportName) else { return }
        if let report, let data = try? JSONEncoder().encode(report) {
            try? data.write(to: file, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func handled() -> [Date] {
        guard let file = url(Self.handledName), let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([Date].self, from: data)) ?? []
    }

    func dismiss() {
        guard let report = pending else { return }
        setPending(nil)
        queue.async {
            self.save(nil)
            let dates = (self.handled() + [report.crashedAt]).suffix(30)
            if let file = self.url(Self.handledName), let data = try? JSONEncoder().encode(Array(dates)) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }

    /// MetricKit отдал сбои за окно `from...to`. Есть ждущий отчёт — дополняем его; нет — новый отчёт,
    /// если в этом окне (± час) не было уже разобранного сбоя.
    func attach(metric: [MetricCrash], from: Date, to: Date) {
        guard !metric.isEmpty else { return }
        queue.async {
            guard let device = self.device else { return }
            if var report = self.pending {
                let fresh = metric.filter { !report.metric.contains($0) }
                guard !fresh.isEmpty else { return }
                report.metric += fresh
                self.save(report)
                self.setPending(report)
                return
            }
            let window = from.addingTimeInterval(-3600)...to.addingTimeInterval(3600)
            guard !self.handled().contains(where: { window.contains($0) }) else { return }
            let report = CrashReport.make(metric: metric, device: device, at: to)
            self.save(report)
            self.setPending(report)
        }
    }
}
