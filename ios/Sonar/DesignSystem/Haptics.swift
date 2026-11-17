import UIKit

/// Тактильный отклик Sonar: лёгкий «тык» (средне-слабый) на всё нажимаемое — кнопки, вкладки, переключатели,
/// смену трека свайпом. Строки треков — без него.
/// Выключается в Профиль → Общее → «Тактильный отклик» (`general.haptics`).
@MainActor
enum Haptics {
    static let key = "general.haptics"
    private static let light = UIImpactFeedbackGenerator(style: .light)

    static var enabled: Bool { SettingsStore.shared.bool(key) }

    /// Лёгкий тык — нажатие кнопки, строки, вкладки.
    static func tap() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.6)
    }
}
