import AppIntents
import Foundation

// Siri и Команды (App Intents): особых прав (entitlement) не нужно — работает и в IPA, переподписанной
// своей парой. Все команды — `AudioPlaybackIntent`: выполняются в самом Sonar в фоне, без открытия окна.
// Фразы — `SonarShortcuts` ниже; английские — `Resources/en.lproj/AppShortcuts.strings`.
// Русского языка у Siri нет — по-русски команды видны в «Командах» и в поиске Spotlight; голосом Siri
// понимает английские фразы («Play Sonar Mix in Sonar»). CarPlay — нельзя: нужен entitlement от Apple.

/// Ошибка для Siri: проговаривает текст.
struct SonarIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource("\(message)")
    }
}

@MainActor
private func runQuick(_ target: PlayTarget) async throws {
    do {
        try await QuickPlay.play(target)
        try await QuickPlay.waitUntilPlaying()
    } catch {
        throw SonarIntentError(message: error.localizedDescription)
    }
}

struct PlayWaveIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource { "Включить Sonar Mix" }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await runQuick(.wave)
        return .result()
    }
}

struct PlayLikedIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource { "Включить Любимые" }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await runQuick(.liked)
        return .result()
    }
}

struct PlayQuickPlaylistIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource { "Включить быстрый плейлист" }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await runQuick(.quick)
        return .result()
    }
}

struct PausePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource { "Пауза" }

    @MainActor
    func perform() async throws -> some IntentResult {
        PlaybackEngine.shared.pause()
        return .result()
    }
}

struct ResumePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource { "Продолжить" }

    @MainActor
    func perform() async throws -> some IntentResult {
        let engine = PlaybackEngine.shared
        guard engine.current != nil else {
            // очереди нет (первый запуск) — Sonar Mix, как кнопка на Главной
            try await runQuick(.wave)
            return .result()
        }
        engine.resume()
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource { "Следующий трек" }

    @MainActor
    func perform() async throws -> some IntentResult {
        let engine = PlaybackEngine.shared
        guard engine.current != nil else { throw SonarIntentError(message: t("Сейчас ничего не играет")) }
        engine.next()
        return .result()
    }
}

/// Готовые команды: появляются в «Командах» и Spotlight сами, без настройки.
struct SonarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayWaveIntent(), phrases: [
            "Включи Sonar Mix в \(.applicationName)",
            "Sonar Mix в \(.applicationName)",
            "\(.applicationName) микс",
        ], shortTitle: "Sonar Mix", systemImageName: "dot.radiowaves.left.and.right")
        AppShortcut(intent: PlayLikedIntent(), phrases: [
            "Включи любимые в \(.applicationName)",
            "\(.applicationName) любимые",
        ], shortTitle: "Любимые", systemImageName: "heart.fill")
        AppShortcut(intent: PlayQuickPlaylistIntent(), phrases: [
            "Включи быстрый плейлист в \(.applicationName)",
            "\(.applicationName) быстрый плейлист",
        ], shortTitle: "Быстрый плейлист", systemImageName: "bolt.fill")
        AppShortcut(intent: PausePlaybackIntent(), phrases: [
            "Пауза в \(.applicationName)",
            "Поставь \(.applicationName) на паузу",
        ], shortTitle: "Пауза", systemImageName: "pause.fill")
        AppShortcut(intent: ResumePlaybackIntent(), phrases: [
            "Продолжи \(.applicationName)",
            "Играй \(.applicationName)",
        ], shortTitle: "Продолжить", systemImageName: "play.fill")
        AppShortcut(intent: NextTrackIntent(), phrases: [
            "Следующий трек в \(.applicationName)",
            "\(.applicationName) дальше",
        ], shortTitle: "Следующий трек", systemImageName: "forward.fill")
    }
}
