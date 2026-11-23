import SwiftUI

/// Точка входа. Пока без сервера: приложение работает автономно, как Windows-клиент (SPEC §9) —
/// токены сервисов в Keychain, данные на устройстве.
@main
struct SonarApp: App {
    init() {
        // журнал сбоев — первым делом: ловит сбои и читает отчёт прошлого запуска
        CrashLog.start()
        // офлайн-режим — до любого запроса: сторож сети и флаг из настроек (docs/OFFLINE.md §4.1)
        OfflineMode.bootstrap()
        // тап по уведомлению «Новинки», которое запустило Sonar с нуля, — делегат нужен до конца запуска
        ReleaseNotifier.installDelegate()
    }

    @State private var chrome = ChromeState()
    @State private var settings = SettingsStore.shared
    @State private var checker = UpdateChecker.shared
    @State private var updater = SelfUpdater.shared
    @State private var signing = SigningModel()
    @State private var engine = PlaybackEngine.shared
    @State private var library = LibraryStore.shared
    @State private var router = Router()
    @State private var releases = ReleaseNotifier.shared
    @State private var offline = OfflineMode.shared
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
                .environment(offline)
                .tint(Theme.accent)
                .task {
                    // «Классика» — основной вид: один раз переключаем и прежних пользователей
                    ClassicSwitch.applyOnce(settings)
                    // при запуске и раз в 6 часов (update.auto_check)
                    checker.startAutomatic(settings: settings)
                    // кэш текстов чистится при создании хранилища (неделя / две у Любимых)
                    _ = LyricsStore.shared
                    StorageUsage.applyCoverLimit(settings)
                    // Last.fm убран (docs/LASTFM_EXIT.md): прежний вход и очередь стираются один раз
                    RetiredIntegrations.forgetOnDevice()
                    // офлайн: ни входа в SoundCloud, ни синка — включат сеть, синк стартует сам (OfflineMode.set)
                    if !offline.isOn {
                        // SoundCloud: тихий вход и плашка «Войди заново», если ключи перестали работать
                        await SoundCloudRelogin.shared.start()
                        // сервер: синхронизация и версия устройства — без включённого сервера ничего не делают
                        SyncService.shared.start()
                        await AccountStore.shared.reportLaunch()
                    }
                    await MusicCore.shared.configure(maxKbps: MusicCore.qualityKbps(settings.string("audio.quality")),
                                                     soundCloudViaYandex: settings.bool("audio.sc_via_yandex"),
                                                     youTubeHigh: MusicCore.youTubeHigh(settings.string(YouTubeQuality.key)),
                                                     fallback: FallbackSettings(enabled: settings.bool(FallbackPlan.enabledKey),
                                                                                saved: settings.string(FallbackPlan.orderKey)))
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, !offline.isOn {
                        checker.checkIfStale(settings: settings)
                        // SoundCloud: освежить вход заранее, пока Sonar на экране (в фоне тихий вход ненадёжен)
                        Task { await MusicCore.shared.refreshSoundCloudIfOld() }
                        // новинки любимых исполнителей — не чаще раза в 3 ч (notify.releases)
                        Task { await releases.checkIfStale() }
                    }
                }
                // тап по уведомлению «Новинки»: альбом — открыть, трек — сыграть
                .onChange(of: releases.pendingURL, initial: true) { _, url in
                    guard let url else { return }
                    releases.pendingURL = nil
                    DeepLink.handle(url, router: router, chrome: chrome)
                }
                // «выйди на рабочий стол» — в своём окне поверх всего (Update/HomeHintWindow.swift)
                .onChange(of: updater.stage, initial: true) { _, stage in
                    HomeHintWindow.shared.update(for: stage)
                }
                .onOpenURL { url in
                    // sonar://play/<liked|wave|quick> (виджет), sonar://auth/<code>, album и track (новинки)
                    DeepLink.handle(url, router: router, chrome: chrome)
                }
        }
        // фоновое обновление iOS: новинки исполнителей, пока Sonar закрыт (ReleaseNotifier)
        .backgroundTask(.appRefresh(ReleaseNotifier.taskID)) {
            await ReleaseNotifier.shared.runInBackground()
        }
    }
}
