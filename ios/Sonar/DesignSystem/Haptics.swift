import UIKit

/// Тактильный отклик Sonar: почти незаметный «тык» на нажатия в настройках, вкладках и кнопке «Моей волны».
/// Выключается в Профиль → Общее → «Тактильный отклик» (`general.haptics`).
@MainActor
enum Haptics {
    static let key = "general.haptics"
    private static let light = UIImpactFeedbackGenerator(style: .soft)

    static var enabled: Bool { SettingsStore.shared.bool(key) }

    /// Лёгкий тык — нажатие кнопки, строки, вкладки.
    static func tap() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.35)
    }
}
