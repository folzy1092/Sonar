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
                    // сервер: синхронизация и версия устройства — без включённого сервера ничего не делают
                    SyncService.shared.start()
                    await AccountStore.shared.reportLaunch()
                    await MusicCore.shared.configure(maxKbps: MusicCore.qualityKbps(settings.string("audio.quality")),
                                                     soundCloudViaYandex: settings.bool("audio.sc_via_yandex"),
                                                     youTubeHigh: MusicCore.youTubeHigh(settings.string(YouTubeQuality.key)))
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { checker.checkIfStale(settings: settings) }
                }
                // «выйди на рабочий стол» — в своём окне поверх всего (Update/HomeHintWindow.swift)
                .onChange(of: updater.stage, initial: true) { _, stage in
                    HomeHintWindow.shared.update(for: stage)
                }
                .onOpenURL { url in
                    // sonar://play/<liked|wave|quick> (виджет), sonar://auth/<code>; track и user — разбор позже
                    DeepLink.handle(url)
                }
        }
    }
}
