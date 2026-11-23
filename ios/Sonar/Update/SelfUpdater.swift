import Foundation
import Observation
import os
import UIKit
import ZipArchive

/// Стадии обновления на устройстве.
enum SelfUpdateStage: Equatable, Sendable {
    case idle
    case downloading(received: Int64, total: Int64)
    case unpacking(Double)
    case signing
    case packing(Double)
    case startingServer
    /// Окно iOS «Установить?» на экране (или должно быть). hint — iOS долго не начинает загрузку.
    case waitingForConfirmation(hint: Bool)
    case sending(sent: Int64, total: Int64)
    /// Вся IPA у iOS — сейчас она закроет Sonar и поставит новую сборку.
    case installing
    case failed(String)

    /// Доля для полосы прогресса; nil — без процентов.
    var fraction: Double? {
        switch self {
        case let .downloading(received, total): total > 0 ? Double(received) / Double(total) : nil
        case let .unpacking(value), let .packing(value): value
        case let .sending(sent, total): total > 0 ? Double(sent) / Double(total) : 0
        case .installing: 1
        default: nil
        }
    }
}

/// «Обновить»: качает объявленную IPA, делает её похожей на установленную копию (`BundlePreparer`),
/// подписывает на устройстве парой из «Обновлений» (zsign), упаковывает и отдаёт iOS через
/// `itms-services` с локального сервера. iOS заменяет приложение; контейнер с данными остаётся, потому что
/// bundle id и команда те же. Порт ShadowSelfUpdater на async/await.
///
/// Установка — как «Semi Local» в IPA Hub (Feather): IPA на http://127.0.0.1, манифест — с
/// api.palera.in, страница в Safari передаёт ссылку iOS. Что видела установка — в `diagnostics`.
/// Один запуск на всё приложение: уход с экрана его не останавливает.
@MainActor
@Observable
final class SelfUpdater {
    static let shared = SelfUpdater()

    /// Сколько ждать, пока iOS начнёт загрузку после ссылки, прежде чем показать причину.
    static let hintDelay: Duration = .seconds(10)

    private(set) var stage: SelfUpdateStage = .idle
    private(set) var build: Int?
    private(set) var version: String?
    /// Подписанная IPA — поделиться и поставить через ESign, если системная установка не стартовала.
    private(set) var signedIPA: URL?
    private(set) var diagnostics: InstallDiagnostics?

    var isRunning: Bool {
        switch stage {
        case .idle, .failed, .installing: false
        default: true
        }
    }

    @ObservationIgnored private var runId = 0
    @ObservationIgnored private var download: IPADownload?
    @ObservationIgnored private var cancelFlag = CancelFlag()
    @ObservationIgnored private var server: InstallServer?
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    @ObservationIgnored private let keepAwake = KeepAwake()
    @ObservationIgnored private var installItem: InstallServer.Item?
    @ObservationIgnored private var installLink: URL?
    @ObservationIgnored private var installPageURL: URL?
    /// Ссылку в этом запуске уже показали: уход в неактивное — значит, пришло окно iOS.
    @ObservationIgnored private var didOpen = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var workDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SonarUpdate", isDirectory: true)
    }

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appWillResignActive() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appDidBecomeActive() }
        })
    }

    // MARK: - Запуск и отмена

    func start(_ release: UpdateRelease) {
        guard !isRunning, let url = release.downloadURL else { return }
        runId += 1
        let run = runId
        cleanUp()
        keepAwake.begin()
        build = release.build
        version = release.version
        signedIPA = nil
        diagnostics = nil
        stage = .downloading(received: 0, total: 0)
        let flag = CancelFlag()
        cancelFlag = flag
        let destination = workDirectory.appendingPathComponent("download.ipa")
        let download = IPADownload(destination: destination) { [weak self] received, total in
            Task { @MainActor in
                guard let self, self.runId == run else { return }
                self.stage = .downloading(received: received, total: total)
            }
        }
        self.download = download
        let work = workDirectory
        let installed = BundlePreparer.Installed.current()
        let build = release.build
        let title = "Sonar" + (release.version.map { " \($0)" } ?? "")
        Task {
            do {
                try await download.run(url)
                guard self.runId == run else { return }
                self.download = nil
                let progress: @Sendable (SelfUpdateStage) -> Void = { [weak self] stage in
                    Task { @MainActor in
                        guard let self, self.runId == run else { return }
                        self.stage = stage
                    }
                }
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try SelfUpdater.prepare(downloaded: destination, work: work, build: build, installed: installed,
                                     store: .shared, cancelled: { flag.isSet }, progress: progress)
                }.value
                guard self.runId == run else { return }
                self.signedIPA = prepared.ipa
                self.beginInstall(InstallServer.Item(ipaURL: prepared.ipa, bundleId: installed.bundleId,
                                                     bundleVersion: prepared.bundleVersion, title: title), run: run)
            } catch {
                guard self.runId == run else { return }
                self.fail(error)
            }
        }
    }

    func cancel() {
        runId += 1
        cancelFlag.set()
        finish(.idle)
        build = nil
        signedIPA = nil
        diagnostics = nil
        cleanUp()
    }

    // MARK: - Подготовка (не на главном потоке)

    /// Распаковать → подготовить бандл → подписать → упаковать. Возвращает подписанную IPA.
    nonisolated static func prepare(
        downloaded: URL,
        work: URL,
        build: Int,
        installed: BundlePreparer.Installed,
        store: SigningStore,
        cancelled: @Sendable () -> Bool,
        progress: @escaping @Sendable (SelfUpdateStage) -> Void
    ) throws -> (ipa: URL, bundleVersion: String) {
        guard store.isConfigured else { throw SelfUpdateError.notConfigured }
        let root = work.appendingPathComponent("package", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        progress(.unpacking(0))
        var lastUnzip = -1
        var unzipError: Error?
        let unzipped = SSZipArchive.unzipFile(atPath: downloaded.path, toDestination: root.path, overwrite: true, password: nil,
                                              progressHandler: { _, _, entry, total in
            guard total > 0 else { return }
            let percent = Int(Double(entry) * 100 / Double(total))
            if percent != lastUnzip {
                lastUnzip = percent
                progress(.unpacking(Double(percent) / 100))
            }
        }, completionHandler: { _, _, error in
            unzipError = error
        })
        try? FileManager.default.removeItem(at: downloaded)
        guard !cancelled() else { throw SelfUpdateError.cancelled }
        guard unzipped, let app = BundlePreparer.findApp(inPayloadParent: root) else {
            throw unzipError ?? SelfUpdateError.badArchive
        }
        // профиль на «*» подходит и к виджету — его можно оставить, даже если раньше его не было
        try BundlePreparer.prepare(app: app, installed: installed, profileURL: store.profileURL,
                                   keepNewPlugIns: store.profile?.isWildcard ?? false)

        progress(.signing)
        try AppSigner.sign(app: app, store: store)
        guard !cancelled() else { throw SelfUpdateError.cancelled }
        let bundleVersion = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "\(build)"

        progress(.packing(0))
        let ipa = work.appendingPathComponent("Sonar-\(build)-signed.ipa")
        try? FileManager.default.removeItem(at: ipa)
        var lastZip = -1
        // уровень 1: быстро, а IPA остаётся примерно размером со скачанную
        let zipped = SSZipArchive.createZipFile(atPath: ipa.path, withContentsOfDirectory: root.path, keepParentDirectory: false,
                                                compressionLevel: 1, password: nil, aes: false, progressHandler: { entry, total in
            guard total > 0 else { return }
            let percent = Int(Double(entry) * 100 / Double(total))
            if percent != lastZip {
                lastZip = percent
                progress(.packing(Double(percent) / 100))
            }
        })
        try? FileManager.default.removeItem(at: root)
        guard !cancelled() else { throw SelfUpdateError.cancelled }
        guard zipped else { throw SelfUpdateError.packing }
        return (ipa, bundleVersion)
    }

    // MARK: - Установка

    private func beginInstall(_ item: InstallServer.Item, run: Int) {
        installItem = item
        diagnostics = InstallDiagnostics()
        startServer(opener: .safariPage, run: run)
    }

    /// Новый сервер (и порт); ссылки — когда он готов.
    private func startServer(opener: InstallDiagnostics.Opener, run: Int) {
        guard let item = installItem else { return }
        hintTask?.cancel()
        server?.stop()
        let server = InstallServer(item: item)
        self.server = server
        installLink = nil
        installPageURL = nil
        stage = .startingServer
        diagnostics?.opener = opener
        diagnostics?.server = InstallActivity()
        diagnostics?.openResult = nil
        diagnostics?.promptSeen = false
        diagnostics?.externalManifest = .pending
        diagnostics?.fallbackManifest = nil

        server.onActivity = { [weak self, weak server] activity in
            Task { @MainActor in
                guard let self, let server, self.isCurrent(server, run: run) else { return }
                self.diagnostics?.server = activity
            }
        }
        server.onPayloadRequested = { [weak self, weak server] in
            Task { @MainActor in
                guard let self, let server, self.isCurrent(server, run: run) else { return }
                // пользователь нажал «Установить»: iOS качает IPA
                self.hintTask?.cancel()
                InstallPage.shared.hide()
                if case .waitingForConfirmation = self.stage {
                    self.stage = .sending(sent: 0, total: 0)
                }
            }
        }
        server.onPayloadProgress = { [weak self, weak server] sent, total in
            Task { @MainActor in
                guard let self, let server, self.isCurrent(server, run: run), case .sending = self.stage else { return }
                self.stage = .sending(sent: sent, total: total)
            }
        }
        server.onPayloadFinished = { [weak self, weak server] in
            Task { @MainActor in
                guard let self, let server, self.isCurrent(server, run: run) else { return }
                InstallPage.shared.hide()
                // сервер не гасим: iOS может запросить IPA ещё раз
                self.finish(.installing)
            }
        }
        Task {
            do {
                let port = try await server.start()
                guard self.isCurrent(server, run: run) else { return }
                await self.serverReady(port: port, run: run)
            } catch {
                guard self.isCurrent(server, run: run) else { return }
                self.fail(error)
            }
        }
    }

    private func isCurrent(_ server: InstallServer, run: Int) -> Bool {
        runId == run && self.server === server
    }

    private func serverReady(port: UInt16, run: Int) async {
        let payload = InstallLinks.payloadURL(port: port)
        guard let item = installItem,
              let manifest = InstallLinks.externalManifestURL(bundleId: item.bundleId, bundleVersion: item.bundleVersion,
                                                               title: item.title, payload: payload),
              let link = InstallLinks.itmsURL(manifest: manifest) else {
            diagnostics?.externalManifest = .failed("bundle id")
            fail(SelfUpdateError.installLink)
            return
        }
        installLink = link
        installPageURL = InstallLinks.pageURL(port: port)
        server?.setPageTarget(link)
        // iOS сама возьмёт манифест с api.palera.in; спрашиваем первыми — тогда мёртвый сервис или VPN
        // видны как причина
        let problem = await Self.manifestProblem(manifest, payload: payload, timeout: 5)
        guard runId == run else { return }
        diagnostics?.externalManifest = problem.map { .failed($0) } ?? .ok
        // palera лежит (так было 2026-11-19, Cloudflare 521) — запасной манифест из репо под постоянный порт
        if problem != nil, let fallback = InstallLinks.fallbackManifestURL(bundleId: item.bundleId, port: port),
           let fallbackLink = InstallLinks.itmsURL(manifest: fallback) {
            diagnostics?.fallbackManifest = .pending
            let fallbackProblem = await Self.manifestProblem(fallback, payload: payload, timeout: 8)
            guard runId == run else { return }
            diagnostics?.fallbackManifest = fallbackProblem.map { .failed($0) } ?? .ok
            if fallbackProblem == nil {
                installLink = fallbackLink
                server?.setPageTarget(fallbackLink)
            }
        }
        // без манифеста всё равно показываем ссылку: iOS может его получить, а причина будет в подсказке
        present(run: run)
    }

    /// Свой GET манифеста: nil — это plist для нашей IPA, иначе коротко, что не так.
    private nonisolated static func manifestProblem(_ url: URL, payload: URL, timeout: TimeInterval) async -> String? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("Sonar", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return InstallLinks.externalManifestProblem(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode,
                                                        error: nil, payload: payload)
        } catch {
            return InstallLinks.externalManifestProblem(data: nil, statusCode: nil, error: error, payload: payload)
        }
    }

    /// Показывает ссылку установки: страницу в Safari или `UIApplication.open`.
    private func present(run: Int) {
        guard let link = installLink else { return }
        stage = .waitingForConfirmation(hint: false)
        diagnostics?.openResult = nil
        diagnostics?.promptSeen = false
        didOpen = true
        armHint(run: run)
        switch diagnostics?.opener ?? .openURL {
        case .safariPage:
            if let installPageURL { InstallPage.shared.show(installPageURL) }
        case .openURL:
            InstallPage.shared.hide()
            Task {
                let opened = await UIApplication.shared.open(link)
                guard self.runId == run else { return }
                self.diagnostics?.openResult = opened
            }
        }
    }

    /// iOS не начала загрузку за `hintDelay` после ссылки — под статусом причина.
    private func armHint(run: Int) {
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: SelfUpdater.hintDelay)
            guard !Task.isCancelled, let self, self.runId == run,
                  case .waitingForConfirmation(hint: false) = self.stage else { return }
            if let server = self.server {
                let activity = await server.snapshot()
                guard self.runId == run else { return }
                self.diagnostics?.server = activity
                if activity.payloadRequested { return }
            }
            // страница никуда не привела: причина и кнопки — под статусом; уход из приложения отсюда
            // (поменять VPN) — это уже не окно установки
            InstallPage.shared.hide()
            self.didOpen = false
            self.stage = .waitingForConfirmation(hint: true)
        }
    }

    /// «Показать окно установки»: окно закрыли или оно не пришло.
    func retryInstallPrompt() {
        guard case .waitingForConfirmation = stage, let server, let diagnostics else { return }
        let run = runId
        Task {
            let activity = await server.snapshot()
            guard self.runId == run, self.server === server else { return }
            self.diagnostics?.server = activity
            guard activity.isReady else {
                // сервер остановился (Sonar был в фоне или порт заняли) — новый сервер, порт и ссылки
                self.startServer(opener: diagnostics.opener, run: run)
                return
            }
            // в прошлый раз окна не было — другой способ открыть ссылку
            if !diagnostics.promptSeen {
                self.diagnostics?.opener = diagnostics.opener == .safariPage ? .openURL : .safariPage
            }
            self.present(run: run)
        }
    }

    /// Системное окно установки закрыло приложение — значит, оно появилось. Только пока ссылка свежая:
    /// когда подсказка уже на экране, пользователь уходит сам.
    private func appWillResignActive() {
        guard case .waitingForConfirmation(hint: false) = stage, didOpen else { return }
        hintTask?.cancel()
        diagnostics?.promptSeen = true
    }

    /// Вернулись из окна: «Установить» вскоре начнёт загрузку, «Отмена» — нет.
    private func appDidBecomeActive() {
        if isRunning { keepAwake.renew() }
        guard case .waitingForConfirmation(hint: false) = stage, let diagnostics, diagnostics.promptSeen,
              !diagnostics.server.payloadRequested else { return }
        armHint(run: runId)
    }

    // MARK: - Состояние

    private func fail(_ error: Error) {
        if (error as? SelfUpdateError) == .cancelled { return }
        finish(.failed(error.localizedDescription))
        server?.stop()
        server = nil
        InstallPage.shared.hide()
    }

    /// Конец запуска: экран снова может гаснуть.
    private func finish(_ stage: SelfUpdateStage) {
        hintTask?.cancel()
        hintTask = nil
        keepAwake.end()
        self.stage = stage
    }

    private func cleanUp() {
        download?.cancel()
        download = nil
        server?.stop()
        server = nil
        InstallPage.shared.hide()
        installItem = nil
        installLink = nil
        installPageURL = nil
        didOpen = false
        try? FileManager.default.removeItem(at: workDirectory)
    }
}

enum SelfUpdateError: LocalizedError, Equatable {
    case notConfigured
    case badArchive
    case packing
    case http(Int)
    case installLink
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Добавь сертификат и профиль в «Обновлениях»."
        case .badArchive: "Скачанный файл — не IPA Sonar."
        case .packing: "Не удалось упаковать подписанную IPA."
        case let .http(status): "Сервер вернул \(status) при загрузке IPA."
        case .installLink: "Не удалось составить ссылку установки. Поделись подписанной IPA и поставь её через ESign."
        case .cancelled: "Отменено."
        }
    }
}

/// Флаг отмены для шагов, которые идут не на главном потоке.
final class CancelFlag: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    var isSet: Bool { lock.withLock { $0 } }

    func set() {
        lock.withLock { $0 = true }
    }
}

/// Не гасить экран и не засыпать, пока готовится и уходит IPA: iOS забирает её с локального сервера, а
/// он умирает, когда приложение приостановлено. Фоновое время — около 30 с; кончилось — вернувшись,
/// берём новое.
@MainActor
final class KeepAwake {
    private var task: UIBackgroundTaskIdentifier = .invalid
    private var active = false

    func begin() {
        active = true
        UIApplication.shared.isIdleTimerDisabled = true
        renew()
    }

    func renew() {
        guard active, task == .invalid else { return }
        task = UIApplication.shared.beginBackgroundTask(withName: "Sonar update") { [weak self] in
            MainActor.assumeIsolated { self?.endTask() }
        }
    }

    func end() {
        active = false
        UIApplication.shared.isIdleTimerDisabled = false
        endTask()
    }

    private func endTask() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}

/// Загрузка IPA с прогрессом (делегат URLSession — колбэки на его последовательной очереди).
final class IPADownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Int64, Int64) -> Void
    private var session: URLSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var movedError: Error?
    private var didMove = false
    private var lastPermille: Int64 = -1

    init(destination: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func run(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // продолжение — до старта задачи: делегат не может ответить раньше
            self.continuation = continuation
            let configuration = Net.configuration()
            configuration.timeoutIntervalForRequest = 60
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func cancel() {
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // вызывается на каждый пакет — экрану хватит шага 0,1 %
        let total = max(totalBytesExpectedToWrite, 0)
        let permille = total > 0 ? totalBytesWritten * 1000 / total : totalBytesWritten / (1024 * 1024)
        if permille != lastPermille {
            lastPermille = permille
            progress(totalBytesWritten, total)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let response = downloadTask.response as? HTTPURLResponse, !(200 ..< 300).contains(response.statusCode) {
            movedError = SelfUpdateError.http(response.statusCode)
            return
        }
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            didMove = true
        } catch {
            movedError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        let result: Result<Void, Error>
        if let error {
            result = .failure((error as? URLError)?.code == .cancelled ? SelfUpdateError.cancelled : error)
        } else if let movedError {
            result = .failure(movedError)
        } else if !didMove {
            result = .failure(SelfUpdateError.badArchive)
        } else {
            result = .success(())
        }
        continuation?.resume(with: result)
        continuation = nil
    }
}
