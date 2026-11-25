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
        // Офлайн-режим (docs/OFFLINE.md): ни байта в сеть; только это устройство, не синхронизируется
        "general.offline": .bool(false),
        // пропала сеть — плашка «Включить офлайн-режим» (сам режим не включается)
        "general.offline_suggest": .bool(true),
        // Скачивать только по Wi-Fi (OFFLINE.md §8): по сотовой очередь ждёт
        "storage.download_wifi_only": .bool(true),
        // Автоскачивание Любимых (OFFLINE.md §8.3): свежие лайки первыми, пока всё скачанное влезает в лимит, ГБ
        "storage.auto_download_liked": .bool(false),
        "storage.auto_download_limit_gb": .int(5),
        // Уведомления: новинки любимых исполнителей (ReleaseNotifier), общий ключ с ПК
        "notify.releases": .bool(true),
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
        // Приватность: кто может позвать в друзья (everyone / fof / nobody) и кто видит разделы профиля
        // (everyone / friends / nobody); `privacy.hidden_playlists` — только ПК (у iPhone нет списков)
        "privacy.friend_requests": .string("everyone"),
        "privacy.playlists": .string("everyone"),
        "privacy.likes": .string("everyone"),
        "privacy.now_playing": .string("everyone"),
        "privacy.stats": .string("everyone"),
        // Комнаты и сообщения (docs/ROOMS.md, docs/DM.md): кто может писать, звать в комнату, видит мою комнату
        "privacy.messages": .string("friends"),
        "privacy.room_invites": .string("friends"),
        "privacy.room_visible": .string("friends"),
    ]
}
