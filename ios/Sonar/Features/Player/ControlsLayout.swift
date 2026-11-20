import CoreGraphics

/// Размеры ряда кнопок полного плеера. С открытым текстом песни ряд компактный: капсула ⟲ ⏮ ▶ ⏭ ⤨ мельче,
/// а по бокам — круглые кнопки: слева ♥ (в Любимые), справа T (закрыть текст). Должно влезать и на iPhone SE
/// (ширина 375 минус поля плеера 2 × 18).
struct PlayerControlsLayout: Equatable {
    /// Высота капсулы.
    let rowHeight: CGFloat
    /// Сторона кнопки «Играть».
    let playSide: CGFloat
    /// ⏮ / ⏭.
    let skipIcon: CGFloat
    /// Повтор и перемешивание (`PlayerToggleIcon.size`).
    let toggleIcon: CGFloat
    /// Внутренние поля капсулы слева и справа.
    let capsulePadding: CGFloat
    /// Круглые кнопки по бокам; 0 — их нет.
    let sideButton: CGFloat
    /// Зазор между капсулой и боковыми кнопками.
    let gap: CGFloat

    static let regular = PlayerControlsLayout(rowHeight: 88, playSide: 72, skipIcon: 30, toggleIcon: 26,
                                              capsulePadding: 22, sideButton: 0, gap: 0)
    static let compact = PlayerControlsLayout(rowHeight: 60, playSide: 50, skipIcon: 22, toggleIcon: 18,
                                              capsulePadding: 12, sideButton: 46, gap: 6)

    static func current(lyricsOpen: Bool) -> Self { lyricsOpen ? .compact : .regular }

    var hasSideButtons: Bool { sideButton > 0 }

    /// «Играть» рисуется в размере 72 pt и масштабируется — так смена размера идёт одной анимацией.
    var playScale: CGFloat { playSide / Self.regular.playSide }

    /// Самый узкий ряд: капсула без растяжки (минимальные промежутки) и боковые кнопки.
    var minimumWidth: CGFloat {
        let toggle = toggleIcon + Self.togglePad
        let skip = skipIcon + Self.skipPad
        let capsule = capsulePadding * 2 + toggle * 2 + skip * 2 + playSide + Self.minSpacing * 4
        let sides = hasSideButtons ? (sideButton + gap) * 2 : 0
        return capsule + sides
    }

    /// Кружок вокруг значка повтора / перемешивания (`PlayerToggleIcon.pad`).
    static let togglePad: CGFloat = 18
    /// Место вокруг ⏮ / ⏭ под палец.
    static let skipPad: CGFloat = 8
    static let minSpacing: CGFloat = 4
}
