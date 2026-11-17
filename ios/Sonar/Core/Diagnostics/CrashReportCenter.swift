import Foundation
import Observation

/// Состояние окна «Sonar закрылся с ошибкой»: какой отчёт ждёт, как идёт отправка.
@MainActor
@Observable
final class CrashReportCenter {
    static let shared = CrashReportCenter()

    enum Phase: Equatable {
        case idle
        case sending
        case sent
        /// Не вышло; текст — для подписи (ключ перевода или ответ Telegram).
        case failed(String)
    }

    /// Ждущий отчёт; `nil` — окна нет.
    private(set) var report: CrashReport?
    private(set) var phase: Phase = .idle
    /// Файл для системного «Поделиться» (бота нет в сборке или отправка не вышла и выбрали «Поделиться»).
    var shareFile: URL?

    /// Бот отчётов есть в сборке — иначе «Отправить лог» сразу открывает «Поделиться».
    let bot: ReportBot?
    private let sender: @Sendable (ReportBot, CrashReport) async throws -> Void
    private let dismissStore: () -> Void
    private let exporter: (CrashReport) throws -> URL
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init(bot: ReportBot? = ReportBot.bundled,
         report: CrashReport? = nil,
         sender: @escaping @Sendable (ReportBot, CrashReport) async throws -> Void = { bot, report in
             try await bot.send(caption: report.caption, fileName: report.fileName, file: Data(report.text.utf8))
         },
         dismiss: @escaping () -> Void = { CrashLog.dismiss() },
         exporter: @escaping (CrashReport) throws -> URL = CrashLog.exportFile) {
        self.bot = bot
        self.report = report
        self.sender = sender
        self.dismissStore = dismiss
        self.exporter = exporter
    }

    /// Подхватить ждущий отчёт и следить за новыми (MetricKit приходит позже запуска).
    func observe() {
        refresh()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: CrashLog.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CrashReportCenter.shared.refresh() }
        }
    }

    func refresh() {
        // во время отправки отчёт не подменяем — дополнение MetricKit уйдёт в следующий раз
        guard phase == .idle || report == nil else { return }
        report = CrashLog.pendingReport
    }

    /// «Отправить лог» / «Ещё раз».
    func send() async {
        guard let report, phase != .sending else { return }
        guard let bot else { share(); return }
        phase = .sending
        do {
            try await sender(bot, report)
            phase = .sent
            dismissStore()
        } catch let ReportBot.SendError.rejected(status, description) {
            phase = .failed(description.map { "Telegram: \($0)" } ?? "Telegram не принял отчёт (\(status))")
        } catch {
            phase = .failed("Нет связи с Telegram")
        }
    }

    /// «Поделиться»: файл отчёта для системного листа.
    func share() {
        guard let report else { return }
        do {
            shareFile = try exporter(report)
        } catch {
            phase = .failed("Не удалось сохранить файл отчёта")
        }
    }

    /// Лист «Поделиться» закрыт: отправили — отчёт снимаем, отменили — окно остаётся.
    func shareFinished(completed: Bool) {
        if let shareFile { try? FileManager.default.removeItem(at: shareFile) }
        shareFile = nil
        if completed {
            phase = .sent
            dismissStore()
        }
    }

    /// «Закрыть» (и закрытие после «Отправлено ✓»).
    func close() {
        if phase != .sent { dismissStore() }
        report = nil
        phase = .idle
        shareFile = nil
    }
}
