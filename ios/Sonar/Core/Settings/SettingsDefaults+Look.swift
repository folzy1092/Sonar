import Foundation

extension SettingsDefaults {
    /// Интерфейс: Вид, Вкладки, Профиль — ключи и умолчания как в docs/SETTINGS.md.
    /// У `appearance.corner_radius` и других ключей мини-плеера умолчаний здесь нет: пусто — заготовка
    /// «Капсула» (`MiniStyle.current`).
    static let look: [String: SettingValue] = [
        "appearance.mode": .string("dark"),
        "appearance.cover_theme": .bool(true),
        "appearance.cover_strength": .string("medium"),
        "appearance.preset": .string("neutral"),
        // iPhone — «Эхо»: поверхности в оттенке обложки, как на скринах владельца (ПК — «Sonar» = Монолит)
        "appearance.style": .string("echo"),
        "appearance.surface": .string("echo"),
        "appearance.background": .string("cover_color"),
        "appearance.bg_dim": .int(0),
        "appearance.bg_blur": .int(0),
        // iPhone: панели стеклом с самого начала (на ПК прозрачность окна по умолчанию выключена)
        "appearance.glass": .bool(true),
        "appearance.glass_type": .string("ultra"),
        "appearance.opacity": .int(80),
        "appearance.tab_style": .string("floating"),
        "tabs.adapt": .bool(false),
        "tabs.collapse": .bool(true),
        "profile.name": .string(""),
        "profile.username": .string(""),
        "profile.avatar": .string(""),
    ]
}
