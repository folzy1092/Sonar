import Foundation

extension SettingsDefaults {
    /// Аккаунт и Система: Статистика, Общее, Хранилище, Интеграции — ключи и умолчания как в docs/SETTINGS.md.
    /// `general.language` умолчания здесь нет намеренно: не выбран — язык системы (ru / en / uk, иначе ru),
    /// см. `Lang.resolve`.
    static let system: [String: SettingValue] = [
        // Общее: откуда главная берёт волну и рекомендации; куда добавлять треки в плейлистах
        "general.platform": .string("soundcloud"),
        "general.add_position": .string("start"),
        // тактильный отклик на нажатия (настройки, вкладки, Sonar Mix) — почти незаметный
        "general.haptics": .bool(true),
        // Хранилище (iOS): потолок кэша обложек на диске, МБ — 128 / 256 / 512 / 1024
        "storage.covers_limit_mb": .int(256),
        // Статистика: открытый период — week / month / year / all
        "stats.period": .string("month"),
        // Итоги месяца и года: какие уже открывали или скрыли на Главной (`month-2026-11` / `year-2026`)
        "stats.recap_seen": .string(""),
        // Виджет и Siri: что играет «Быстрый плейлист» (sonar://play/quick) — liked / downloaded / ref плейлиста
        // сервиса (`QuickPlaylist`); название плейлиста сервиса — для строки в настройках
        "widget.quick_playlist": .string("liked"),
        "widget.quick_playlist_title": .string(""),
    ]
}
