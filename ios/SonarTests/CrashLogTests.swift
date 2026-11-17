import XCTest
@testable import Sonar

/// Журнал сбоев: кольцевой журнал, маркер, отчёт, MetricKit, бот отчётов, окно — без сети и сбоев.
final class CrashLogTests: XCTestCase {
    private let device = CrashDevice(version: "0.1.0", build: "239", system: "iOS 18.1", model: "iPhone15,2",
                                    imageStart: 0x1_0000_0000, imageEnd: 0x1_0040_0000)

    // MARK: - Кольцевой журнал

    func testRingKeepsLastLinesInOrder() {
        var ring = LogRing(capacity: 3)
        for i in 1...5 { ring.append(LogLine(at: Date(), level: .info, text: "\(i)")) }
        XCTAssertEqual(ring.lines.map(\.text), ["3", "4", "5"])
        XCTAssertEqual(ring.count, 3)
        XCTAssertEqual(ring.total, 5)
    }

    func testRingCollectsErrorsSeparately() {
        var ring = LogRing(capacity: 2)
        for i in 0..<30 { ring.append(LogLine(at: Date(), level: .error, text: "e\(i)")) }
        ring.append(LogLine(at: Date(), level: .info, text: "ok"))
        XCTAssertEqual(ring.errors.count, LogRing.errorCapacity)
        XCTAssertEqual(ring.errors.last?.text, "e29")
        XCTAssertEqual(ring.lines.map(\.text), ["e29", "ok"])
    }

    func testRingCutsHugeLines() {
        var ring = LogRing(capacity: 2)
        ring.append(LogLine(at: Date(), level: .warn, text: String(repeating: "x", count: 5000)))
        XCTAssertEqual(ring.lines[0].text.count, LogRing.maxLineLength + 1)
    }

    func testLineFormatLikeWindows() {
        let date = Date(timeIntervalSince1970: 1_763_380_000.123) // 11:46:40.123 UTC
        let line = LogLine(at: date, level: .error, text: "плеер: нет потока\nвторая строка")
        XCTAssertEqual(line.formatted, "11:46:40.123 ERROR плеер: нет потока\n                   вторая строка")
        XCTAssertEqual(LogLine(at: date, level: .info, text: "x").formatted, "11:46:40.123 INFO  x")
        let parsed = LogLine.parse("11:46:40.123 WARN  медленно")
        XCTAssertEqual(parsed?.level, .warn)
        XCTAssertEqual(parsed?.text, "медленно")
        XCTAssertNil(LogLine.parse("                   вторая строка"))
        XCTAssertNil(LogLine.parse("12:00 ERROR x"))
    }

    func testTailKeepsMultilineRecordsWhole() {
        let text = """
        10:00:00.000 INFO  запуск
        10:00:01.000 ERROR сеть: таймаут
                           подробности
        10:00:02.000 INFO  экран: Поиск
        10:00:03.000 CRASH конец

        """
        XCTAssertEqual(LogTail.last(text, limit: 3), """
        10:00:01.000 ERROR сеть: таймаут
                           подробности
        10:00:02.000 INFO  экран: Поиск
        10:00:03.000 CRASH конец
        """)
        XCTAssertEqual(LogTail.errors(text), ["10:00:01.000 ERROR сеть: таймаут", "10:00:03.000 CRASH конец"])
        XCTAssertEqual(LogTail.last(""), "")
    }

    // MARK: - Маркер

    func testMarkerWithExceptionAndSignal() throws {
        let text = CrashMarker.exceptionBlock(name: "NSRangeException", reason: "index 3\nbeyond bounds",
                                              symbols: ["0 CoreFoundation 0x1 __exceptionPreprocess + 164", "1 Sonar 0x2 main"])
            + "signal 6\ntime 1763380000\nframes\n0x1a2b3c\n0x100000010\nend\n"
        let marker = try XCTUnwrap(CrashMarker.parse(text))
        XCTAssertEqual(marker.exceptionName, "NSRangeException")
        XCTAssertEqual(marker.exceptionReason, "index 3 ⏎ beyond bounds")
        XCTAssertEqual(marker.exceptionSymbols.count, 2)
        XCTAssertEqual(marker.signal, 6)
        XCTAssertEqual(marker.time, Date(timeIntervalSince1970: 1_763_380_000))
        XCTAssertEqual(marker.frames, [0x1a2b3c, 0x1_0000_0010])
        XCTAssertEqual(marker.cause, .exception(name: "NSRangeException", reason: "index 3 ⏎ beyond bounds"))
    }

    func testMarkerSignalOnlyAndTruncated() throws {
        let marker = try XCTUnwrap(CrashMarker.parse("signal 11\ntime 5\nframes\n0xdead\n0xbe"))
        XCTAssertEqual(marker.signal, 11)
        XCTAssertEqual(marker.frames, [0xdead, 0xbe])
        XCTAssertEqual(marker.cause, .signal(11))
        XCTAssertNil(CrashMarker.parse(""))
        XCTAssertNil(CrashMarker.parse("time 5\nframes\nend\n"))
    }

    func testCauseTexts() {
        XCTAssertEqual(CrashCause.signal(11).technical, "SIGSEGV (11)")
        XCTAssertEqual(CrashCause.signal(10).technical, "SIGBUS (10)")
        XCTAssertEqual(CrashCause.signal(5).technical, "SIGTRAP (5)")
        XCTAssertEqual(CrashCause.signal(11).summary, CrashCause.signal(10).summary)
        XCTAssertNotEqual(CrashCause.signal(6).summary, CrashCause.signal(5).summary)
        XCTAssertEqual(CrashCause.exception(name: "X", reason: "y").technical, "X: y")
        XCTAssertEqual(CrashCause.exception(name: "X", reason: nil).technical, "X")
    }

    // MARK: - MetricKit

    private let metricJSON = #"""
    {"callStackTree":{"callStackPerThread":true,"callStacks":[
      {"threadAttributed":false,"callStackRootFrames":[{"binaryName":"libsystem_kernel.dylib","offsetIntoBinaryTextSegment":1,"address":1}]},
      {"threadAttributed":true,"callStackRootFrames":[{"binaryName":"Sonar","offsetIntoBinaryTextSegment":4660,"address":4295037492,
        "subFrames":[{"binaryName":"SwiftUI","offsetIntoBinaryTextSegment":99,"address":255}]}]}]},
     "diagnosticMetaData":{"appBuildVersion":"238","appVersion":"0.1.0","osVersion":"iPhone OS 18.1 (22B83)",
       "deviceType":"iPhone15,2","signal":5,"exceptionType":6,"exceptionCode":1,"terminationReason":"Namespace SIGNAL, Code 5"}}
    """#

    func testMetricCrashParse() throws {
        let crash = try XCTUnwrap(MetricCrash.parse(Data(metricJSON.utf8)))
        XCTAssertEqual(crash.signal, 5)
        XCTAssertEqual(crash.appBuild, "238")
        XCTAssertEqual(crash.deviceType, "iPhone15,2")
        XCTAssertEqual(crash.frames, ["Sonar + 4660  (0x100011234)", "SwiftUI + 99  (0xff)"])
        XCTAssertEqual(crash.cause, .signal(5))
        XCTAssertTrue(crash.text.contains("SIGTRAP (5)"))
        XCTAssertTrue(crash.text.contains("Namespace SIGNAL"))
        XCTAssertNil(MetricCrash.parse(Data("[]".utf8)))
    }

    func testMetricCrashWithoutSignalIsSystem() throws {
        let crash = try XCTUnwrap(MetricCrash.parse(Data(#"{"diagnosticMetaData":{"terminationReason":"jetsam"}}"#.utf8)))
        XCTAssertEqual(crash.cause, .system("jetsam"))
        let objc = try XCTUnwrap(MetricCrash.parse(Data(#"{"diagnosticMetaData":{"objectiveCexceptionReason":{"exceptionName":"NSRangeException","composedMessage":"bad index"}}}"#.utf8)))
        XCTAssertEqual(objc.exceptionReason, "NSRangeException: bad index")
    }

    // MARK: - Стек

    func testStackDescribe() {
        var current = device
        current.imageStart = 0x2_0000_0000
        current.imageEnd = 0x2_0040_0000
        var asked: [UInt64] = []
        let symbol: (UInt64) -> String? = { address in
            asked.append(address)
            return address == 0x2_0000_1234 ? "Sonar PlaybackEngine.play() + 8" : address == 0x18_0000_0000 ? "libswiftCore.dylib swift_retain + 12" : nil
        }
        XCTAssertEqual(CrashStack.describe(0x1_0000_1234, crashed: device, current: current, symbol: symbol),
                       "Sonar + 0x1234  Sonar PlaybackEngine.play() + 8")
        XCTAssertEqual(CrashStack.describe(0x18_0000_0000, crashed: device, current: current, symbol: symbol),
                       "libswiftCore.dylib swift_retain + 12  (0x1800000000)")
        XCTAssertEqual(CrashStack.describe(0x42, crashed: device, current: current, symbol: symbol), "0x42")
        current.build = "240"
        asked = []
        XCTAssertEqual(CrashStack.describe(0x1_0000_1234, crashed: device, current: current, symbol: symbol), "Sonar + 0x1234")
        XCTAssertTrue(asked.isEmpty, "у другой сборки имена из этого запуска не подходят")
    }

    // MARK: - Отчёт

    private func sampleReport() -> CrashReport {
        let marker = CrashMarker(signal: 11, frames: [0x1_0000_0010], time: Date(timeIntervalSince1970: 1_763_380_000))
        let journal = "11:46:30.000 INFO  запуск\n11:46:35.000 ERROR сеть: таймаут\n11:46:39.000 INFO  трек: sc:1\n"
        return CrashReport.make(marker: marker, device: device, journal: journal, stack: ["Sonar + 0x10"])
    }

    func testReportTextLikeWindows() {
        let report = sampleReport()
        let text = report.text
        XCTAssertTrue(text.hasPrefix("Sonar 0.1.0 (сборка 239) · iOS 18.1 · iPhone15,2\nВремя сбоя: 2025-11-17 11:46:40 UTC\n"), text)
        XCTAssertTrue(text.contains("Причина: SIGSEGV (11)"))
        XCTAssertTrue(text.contains("== Стек (сигнал) ==\n0\tSonar + 0x10"))
        XCTAssertTrue(text.contains("== Последние ошибки ==\n11:46:35.000 ERROR сеть: таймаут"))
        XCTAssertTrue(text.contains("== Журнал ==\n11:46:30.000 INFO  запуск"))
        XCTAssertEqual(report.fileName, "sonar-ios-0.1.0-239-20251117-114640.log")
        XCTAssertTrue(report.caption.hasPrefix("💥 Падение Sonar 0.1.0 (сборка 239)"))
        XCTAssertTrue(report.caption.contains("последняя ошибка: 11:46:35.000 ERROR сеть: таймаут"))
        var long = report
        long.lastErrors = [String(repeating: "я", count: 3000)]
        XCTAssertLessThanOrEqual(long.caption.count, 1000)
    }

    func testReportCodableRoundTrip() throws {
        var report = sampleReport()
        report.metric = [try XCTUnwrap(MetricCrash.parse(Data(metricJSON.utf8)))]
        let back = try JSONDecoder().decode(CrashReport.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(back, report)
        XCTAssertTrue(back.text.contains("== MetricKit 1 =="))
    }

    // MARK: - Бот отчётов

    func testBotKeysFromInfoPlist() {
        XCTAssertNil(ReportBot.from(info: nil))
        XCTAssertNil(ReportBot.from(info: ["SonarReportBotToken": "$(SONAR_REPORT_BOT_TOKEN)", "SonarReportChat": "-100"]))
        XCTAssertNil(ReportBot.from(info: ["SonarReportBotToken": "1:abc", "SonarReportChat": " "]))
        let bot = ReportBot.from(info: ["SonarReportBotToken": " 1:abc ", "SonarReportChat": "-100", "SonarReportThread": ""])
        XCTAssertEqual(bot, ReportBot(token: "1:abc", chat: "-100", thread: nil))
        XCTAssertEqual(ReportBot.from(info: ["SonarReportBotToken": "1:abc", "SonarReportChat": "-100", "SonarReportThread": "42"])?.thread, "42")
    }

    func testMultipartBody() {
        let body = Multipart.body(fields: [("chat_id", "-100"), ("caption", "привет")], fileField: "document",
                                  fileName: "a\"b.log", mime: "text/plain", file: Data("LOG".utf8), boundary: "XX")
        let expected = "--XX\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n-100\r\n"
            + "--XX\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\nпривет\r\n"
            + "--XX\r\nContent-Disposition: form-data; name=\"document\"; filename=\"a'b.log\"\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n\r\nLOG\r\n--XX--\r\n"
        XCTAssertEqual(String(decoding: body, as: UTF8.self), expected)
    }

    func testSendDocumentRequest() throws {
        let bot = ReportBot(token: "1:abc", chat: "-100", thread: "7")
        let request = bot.request(caption: "c", fileName: "r.log", file: Data("x".utf8), boundary: "B")
        XCTAssertEqual(request.url?.absoluteString, "https://api.telegram.org/bot1:abc/sendDocument")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=B")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"chat_id\"\r\n\r\n-100\r\n"))
        XCTAssertTrue(body.contains("name=\"message_thread_id\"\r\n\r\n7\r\n"))
        XCTAssertTrue(body.contains("filename=\"r.log\""))
        let noThread = ReportBot(token: "1:abc", chat: "-100", thread: nil).request(caption: "c", fileName: "r", file: Data(), boundary: "B")
        XCTAssertFalse(String(decoding: noThread.httpBody ?? Data(), as: UTF8.self).contains("message_thread_id"))
    }

    func testTelegramReply() {
        XCTAssertTrue(ReportBot.parseReply(Data(#"{"ok":true,"result":{}}"#.utf8)).ok)
        let bad = ReportBot.parseReply(Data(#"{"ok":false,"description":"Bad Request: chat not found"}"#.utf8))
        XCTAssertFalse(bad.ok)
        XCTAssertEqual(bad.description, "Bad Request: chat not found")
        XCTAssertFalse(ReportBot.parseReply(Data("<html>".utf8)).ok)
    }

    // MARK: - Журнал на диске

    private func file(_ dir: URL, _ name: String) -> String {
        (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }

    func testCleanStartHasNoReportAndWritesJournal() {
        let dir = tempDirectory()
        let journal = Journal()
        journal.append(.info, "до запуска")
        journal.start(directory: dir, device: device)
        XCTAssertNil(journal.pending)
        journal.append(.info, "экран: Главная")
        journal.append(.error, "сеть: 500")
        journal.flush()
        let text = file(dir, Journal.sessionName)
        XCTAssertTrue(text.contains("INFO  до запуска"))
        XCTAssertTrue(text.contains("INFO  Sonar 0.1.0 (сборка 239)"))
        XCTAssertTrue(text.contains("ERROR сеть: 500"))
        XCTAssertEqual(journal.lines.count, 4)
    }

    func testCrashMarkerBecomesReportOnNextStart() throws {
        let dir = tempDirectory()
        // прошлый запуск: сборка 238, журнал, маркер
        var previous = device
        previous.build = "238"
        try JSONEncoder().encode(previous).write(to: dir.appendingPathComponent(Journal.metaName))
        try "10:00:00.000 INFO  запуск\n10:00:01.000 ERROR плеер: нет потока\n"
            .write(to: dir.appendingPathComponent(Journal.sessionName), atomically: true, encoding: .utf8)
        try "signal 11\ntime 1763380000\nframes\n0x100000010\nend\n"
            .write(to: dir.appendingPathComponent(Journal.markerName), atomically: true, encoding: .utf8)

        let journal = Journal()
        journal.start(directory: dir, device: device)
        let report = try XCTUnwrap(journal.pending)
        XCTAssertEqual(report.device.build, "238")
        XCTAssertEqual(report.cause, .signal(11))
        XCTAssertEqual(report.stack, ["Sonar + 0x10"])
        XCTAssertEqual(report.lastErrors, ["10:00:01.000 ERROR плеер: нет потока"])
        XCTAssertTrue(report.journal.contains("INFO  запуск"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(Journal.markerName).path))
        XCTAssertFalse(file(dir, Journal.sessionName).contains("плеер: нет потока"), "новый журнал — с чистого листа")

        // отчёт не закрыли — при следующем запуске он всё ещё ждёт
        let again = Journal()
        again.start(directory: dir, device: device)
        XCTAssertEqual(again.pending, report)

        again.dismiss()
        XCTAssertNil(again.pending)
        again.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(Journal.reportName).path))
        let third = Journal()
        third.start(directory: dir, device: device)
        XCTAssertNil(third.pending)
    }

    func testMetricKitAttachesOrCreatesOnce() throws {
        let crash = try XCTUnwrap(MetricCrash.parse(Data(metricJSON.utf8)))
        let dir = tempDirectory()
        let journal = Journal()
        journal.start(directory: dir, device: device)
        let day = Date(timeIntervalSince1970: 1_763_380_000)
        journal.attach(metric: [crash], from: day.addingTimeInterval(-86400), to: day)
        journal.flush()
        let report = try XCTUnwrap(journal.pending)
        XCTAssertEqual(report.metric, [crash])
        XCTAssertEqual(report.device.build, "238")
        XCTAssertEqual(report.cause, .signal(5))
        // тот же сбой ещё раз — не дублируем
        journal.attach(metric: [crash], from: day, to: day)
        journal.flush()
        XCTAssertEqual(journal.pending?.metric.count, 1)

        // закрыли; MetricKit отдал сбой за то же окно — окно не показываем снова
        journal.dismiss()
        journal.attach(metric: [crash], from: day.addingTimeInterval(-86400), to: day)
        journal.flush()
        XCTAssertNil(journal.pending)
        // а сбой за другие сутки — новый отчёт
        journal.attach(metric: [crash], from: day.addingTimeInterval(86400 * 3), to: day.addingTimeInterval(86400 * 4))
        journal.flush()
        XCTAssertNotNil(journal.pending)
    }

    func testMetricKitJoinsPendingCrashReport() throws {
        let dir = tempDirectory()
        try "signal 6\ntime 1763380000\n".write(to: dir.appendingPathComponent(Journal.markerName), atomically: true, encoding: .utf8)
        let journal = Journal()
        journal.start(directory: dir, device: device)
        let crash = try XCTUnwrap(MetricCrash.parse(Data(metricJSON.utf8)))
        journal.attach(metric: [crash], from: Date(), to: Date())
        journal.flush()
        XCTAssertEqual(journal.pending?.cause, .signal(6), "причина — из своего маркера")
        XCTAssertEqual(journal.pending?.metric.count, 1)
        let saved = try JSONDecoder().decode(CrashReport.self, from: Data(contentsOf: dir.appendingPathComponent(Journal.reportName)))
        XCTAssertEqual(saved.metric.count, 1)
    }

    func testJournalFileStaysSmall() throws {
        let dir = tempDirectory()
        let journal = Journal(capacity: 10)
        journal.start(directory: dir, device: device)
        let long = String(repeating: "ж", count: 1500)
        for i in 0..<200 { journal.append(.info, "\(i) \(long)") }
        journal.flush()
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(Journal.sessionName).path)[.size] as? Int)
        XCTAssertLessThan(size, Journal.maxFileBytes)
        XCTAssertTrue(file(dir, Journal.sessionName).contains("199 жжж"))
        XCTAssertEqual(journal.lines.count, 10)
    }

    // MARK: - Окно

    @MainActor
    func testCenterSendSuccess() async {
        var dismissed = 0
        let center = CrashReportCenter(bot: ReportBot(token: "t", chat: "c", thread: nil), report: sampleReport(),
                                       sender: { _, _ in }, dismiss: { dismissed += 1 }, exporter: { _ in URL(fileURLWithPath: "/tmp/x") })
        await center.send()
        XCTAssertEqual(center.phase, .sent)
        XCTAssertEqual(dismissed, 1)
        center.close()
        XCTAssertNil(center.report)
        XCTAssertEqual(dismissed, 1, "после отправки отчёт уже снят")
    }

    @MainActor
    func testCenterSendFailureThenShare() async throws {
        var dismissed = 0
        let tmp = tempDirectory().appendingPathComponent("r.log")
        let center = CrashReportCenter(bot: ReportBot(token: "t", chat: "c", thread: nil), report: sampleReport(),
                                       sender: { _, _ in throw ReportBot.SendError.rejected(status: 400, description: "chat not found") },
                                       dismiss: { dismissed += 1 },
                                       exporter: { report in try Data(report.text.utf8).write(to: tmp); return tmp })
        await center.send()
        XCTAssertEqual(center.phase, .failed("Telegram: chat not found"))
        XCTAssertEqual(dismissed, 0)
        center.share()
        XCTAssertEqual(center.shareFile, tmp)
        center.shareFinished(completed: false)
        XCTAssertNil(center.shareFile)
        XCTAssertNotNil(center.report, "отменили «Поделиться» — окно остаётся")
        XCTAssertEqual(dismissed, 0)
        center.close()
        XCTAssertEqual(dismissed, 1)
    }

    @MainActor
    func testCenterWithoutBotShares() async {
        var dismissed = 0
        let center = CrashReportCenter(bot: nil, report: sampleReport(), sender: { _, _ in XCTFail("бота нет") },
                                       dismiss: { dismissed += 1 }, exporter: { _ in URL(fileURLWithPath: "/tmp/r.log") })
        await center.send()
        XCTAssertEqual(center.shareFile, URL(fileURLWithPath: "/tmp/r.log"))
        XCTAssertEqual(center.phase, .idle)
        center.shareFinished(completed: true)
        XCTAssertEqual(center.phase, .sent)
        XCTAssertEqual(dismissed, 1)
    }
}
