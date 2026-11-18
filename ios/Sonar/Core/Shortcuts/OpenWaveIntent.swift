import AppIntents
import Foundation

// Общий с виджетом файл (ios/project.yml, цели Sonar и SonarWidget): кнопка «Моя волна» в Пункте управления
// и на экране блокировки (iOS 18, `SonarWidget/SonarWidget.swift` `SonarWaveControl`).
// Интент открывает Sonar (`openAppWhenRun`) и отдаёт системе ссылку `sonar://play/wave`: дальше — как у
// виджета «Домой», `.onOpenURL` → `DeepLink.handle` → `QuickPlay.start(.wave)`. Поэтому файл не трогает
// плеер и собирается и в расширении. Apple требует, чтобы интент с `openAppWhenRun` был в обеих целях.
// В «Командах» его не видно (`isDiscoverable`): там уже есть «Включить «Мою волну»» (`App/SonarIntents.swift`).

struct OpenWaveIntent: AppIntent {
    /// Что включает кнопка.
    static let target = PlayTarget.wave

    static var title: LocalizedStringResource { "Открыть «Мою волну»" }
    static var description: IntentDescription { IntentDescription("Открывает Sonar и включает «Мою волну».") }
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(Self.target.url))
    }
}
