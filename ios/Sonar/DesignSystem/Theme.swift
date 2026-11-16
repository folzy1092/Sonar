import SwiftUI

/// Цвета по умолчанию — как тёмная тема ПК-клиента (`windows/src/theme/tokens.css`). Позже их будет
/// перекрашивать `ThemeStore` под обложку (SPEC §4.4).
enum Theme {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let surface = Color(red: 0.075, green: 0.075, blue: 0.085)
    /// Карточки настроек — полупрозрачные, как стекло на `photo_1..3`.
    static let card = Color.white.opacity(0.07)
    static let cardPressed = Color.white.opacity(0.12)
    static let text = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.38)
    static let line = Color.white.opacity(0.08)
    static let accent = Color(red: 0.96, green: 0.55, blue: 0.62)
    /// Текст на акценте.
    static let accentInk = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let success = Color(red: 0.42, green: 0.86, blue: 0.56)

    static let cardRadius: CGFloat = 18
    static let gutter: CGFloat = 16
}
