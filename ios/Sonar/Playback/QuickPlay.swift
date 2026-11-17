import Foundation

/// Быстрый запуск без экранов: кнопки виджета (`sonar://play/…`), Siri и Команды (`SonarIntents.swift`).
/// Любимые — с начала (с ⤮ — со случайного), «Моя волна» — если уже играет, просто продолжить, быстрый
/// плейлист — по настройке `widget.quick_playlist` (Любимые, Скачанные или плейлист сервиса из Медиатеки).
@MainActor
enum QuickPlay {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Из ссылки виджета: ошибка — тостом.
    static func start(_ target: PlayTarget) async {
        do {
            try await play(target)
        } catch {
            PlaybackEngine.shared.message = error.localizedDescription
        }
    }

    /// Включить цель. Ошибку (пусто, сервис не подключён) отдаёт наверх — Siri её проговорит.
    static func play(_ target: PlayTarget) async throws {
        let engine = PlaybackEngine.shared
        let settings = SettingsStore.shared
        // запуск из Siri мог обойти `.task` приложения — качество из настроек на всякий случай
        await MusicCore.shared.configure(maxKbps: MusicCore.qualityKbps(settings.string("audio.quality")),
                                         soundCloudViaYandex: settings.bool("audio.sc_via_yandex"))
        switch target {
        case .liked:
            try playList(LibraryStore.shared.liked, context: "Любимые", empty: t("В Любимых пока пусто"))
        case .wave:
            if engine.isWave, engine.waveSeed == nil, engine.current != nil {
                if !engine.isPlaying { engine.resume() }
            } else {
                engine.playMyWave()
            }
        case .quick:
            try await playQuick(QuickPlaylist(setting: settings.string(QuickPlaylist.key)))
        }
    }

    private static func playQuick(_ choice: QuickPlaylist) async throws {
        switch choice {
        case .liked:
            try playList(LibraryStore.shared.liked, context: "Любимые", empty: t("В Любимых пока пусто"))
        case .downloaded:
            try playList(DownloadStore.shared.downloaded, context: "Скачанные", empty: t("Скачанных треков пока нет"))
        case let .service(ref):
            let (head, tracks) = try await MusicCore.shared.playlist(ref)
            try playList(tracks, context: head.title, empty: t("Плейлист «{title}» пуст", ["title": head.title]))
        }
    }

    private static func playList(_ list: [Track], context: String, empty: String) throws {
        guard !list.isEmpty else { throw Failure(message: empty) }
        let engine = PlaybackEngine.shared
        engine.play(list, at: engine.shuffle ? Int.random(in: 0 ..< list.count) : 0, context: context)
    }

    /// Для Siri: дождаться, пока музыка пойдёт (волна сначала подбирает треки по сети) — иначе iOS может
    /// усыпить приложение раньше. Ошибка плеера за это время — наверх.
    static func waitUntilPlaying(timeout: Duration = .seconds(12)) async throws {
        let engine = PlaybackEngine.shared
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if engine.isPlaying { return }
            if let message = engine.message, !engine.waveLoading, !engine.isLoading {
                engine.message = nil
                throw Failure(message: message)
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}
