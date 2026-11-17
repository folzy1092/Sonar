import SwiftUI

/// Точка входа. Пока без сервера: приложение работает автономно, как Windows-клиент (SPEC §9) —
/// токены сервисов в Keychain, данные на устройстве.
@main
struct SonarApp: App {
    init() {
        // журнал сбоев — первым делом: ловит сбои и читает отчёт прошлого запуска
        CrashLog.start()
    }

    @State private var chrome = ChromeState()
    @State private var settings = SettingsStore.shared
    @State private var checker = UpdateChecker.shared
    @State private var updater = SelfUpdater.shared
    @State private var signing = SigningModel()
    @State private var engine = PlaybackEngine.shared
    @State private var library = LibraryStore.shared
    @State private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(chrome)
                .environment(settings)
                .environment(checker)
                .environment(updater)
                .environment(signing)
                .environment(engine)
                .environment(library)
                .environment(router)
                .tint(Theme.accent)
                .task {
                    // при запуске и раз в 6 часов (update.auto_check)
                    checker.startAutomatic(settings: settings)
                    // кэш текстов чистится при создании хранилища (неделя / две у Любимых)
                    _ = LyricsStore.shared
                    StorageUsage.applyCoverLimit(settings)
                    LastfmScrobbler.shared.flush()
                    await MusicCore.shared.configure(maxKbps: MusicCore.qualityKbps(settings.string("audio.quality")),
                                                     soundCloudViaYandex: settings.bool("audio.sc_via_yandex"))
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { checker.checkIfStale(settings: settings) }
                }
                .onOpenURL { url in
                    // sonar://track/<ref>, sonar://auth/<code>, sonar://user/<username> — разбор позже
                    DeepLink.handle(url)
                }
        }
    }
}

/// Ссылки `sonar://` (BOT.md, SPEC §4.5а). Заготовка: пока только узнаём вид ссылки.
enum DeepLink: Equatable {
    case track(String)
    case auth(String)
    case user(String)

    init?(_ url: URL) {
        guard url.scheme == "sonar", let host = url.host() else { return nil }
        let value = url.pathComponents.dropFirst().joined(separator: "/")
        guard !value.isEmpty else { return nil }
        switch host {
        case "track": self = .track(value)
        case "auth": self = .auth(value)
        case "user": self = .user(value)
        default: return nil
        }
    }

    static func handle(_ url: URL) {
        _ = DeepLink(url)
    }
}
