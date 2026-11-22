import UIKit

/// Тактильный отклик Sonar: лёгкий «тык» (средне-слабый) на всё нажимаемое — кнопки, вкладки, переключатели,
/// смену трека свайпом. Строки треков — без него.
/// Выключается в Профиль → Общее → «Тактильный отклик» (`general.haptics`).
/// Генераторы общие и заранее «прогреты» (`prepare`): новый генератор на каждое касание будит
/// Taptic Engine с задержкой и даёт рывок кадра в анимациях (герой Sonar Mix).
@MainActor
enum Haptics {
    static let key = "general.haptics"
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)

    static var enabled: Bool { SettingsStore.shared.bool(key) }

    /// Лёгкий тык — нажатие кнопки, строки, вкладки.
    static func tap() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.6)
    }

    /// Мягкий толчок — касание живой картинки (поле точек героя).
    static func nudge() {
        guard enabled else { return }
        soft.impactOccurred(intensity: 0.7)
        soft.prepare()
    }

    /// Ощутимый толчок — долгое нажатие открыло лист.
    static func hold() {
        guard enabled else { return }
        medium.impactOccurred()
    }

    /// Прогреть мягкий отклик заранее — экран с полем точек появился.
    static func prepareNudge() {
        guard enabled else { return }
        soft.prepare()
    }

    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()
    /// Когда был последний «тык» перехода: нажатие кнопки и сам переход (через ~0,1 с) — один отклик, не два.
    private static var lastStep = Date.distantPast

    /// Щелчок выбора — переключатель, сегмент, значение по кругу.
    static func select() {
        guard enabled else { return }
        selection.selectionChanged()
    }

    /// Готово — сохранилось, скопировано, проверено.
    static func success() {
        guard enabled else { return }
        notification.notificationOccurred(.success)
    }

    /// Переход: открылась страница (исполнитель, альбом, плейлист, настройки), назад, плеер открылся или
    /// закрылся. Если только что был «тык» нажатия — второй не нужен.
    static func step() {
        guard enabled, Date().timeIntervalSince(lastStep) > 0.35 else { return }
        lastStep = Date()
        light.impactOccurred(intensity: 0.5)
    }

    /// Нажатие, после которого сразу будет переход: отклик сейчас, переход его не повторит.
    static func tapThenStep() {
        tap()
        lastStep = Date()
    }
}
