import SwiftUI

/// Цвета по умолчанию — как тёмная тема ПК-клиента (`windows/src/theme/tokens.css`). Позже их будет
/// перекрашивать `ThemeStore` под обложку (SPEC §4.4).
enum Theme {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let surface = Color(red: 0.075, green: 0.075, blue: 0.085)
    static let text = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let line = Color.white.opacity(0.08)
    static let accent = Color(red: 0.96, green: 0.55, blue: 0.62)
}
