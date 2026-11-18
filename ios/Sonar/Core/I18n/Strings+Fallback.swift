// Строки резервного сервиса на iPhone (этап 4 NEXT_PROMPT): тост плеера, Плеер → Аудио, ошибки потока.
// Отдельным словарём, как Strings+Spotify.swift: общий Strings+Windows.swift — сгенерированный, его
// перепишет gen-i18n. Переводы — те же, что в windows/src/i18n/{en,uk}/fallback.ts; строки только для iPhone
// (порядок стрелками вместо перетаскивания) — в конце.

extension I18n {
    static let fallbackEN: [String: String] = [
        "Играет из {to} — в {from} недоступен": "Playing from {to} — unavailable on {from}",
        "Играет из {to} — в {from} только отрывок": "Playing from {to} — only a preview on {from}",
        "Играет из {to} — в {from} нужна подписка": "Playing from {to} — {from} needs a subscription",
        "Резервный сервис": "Fallback service",
        "Трек не играет в своём сервисе — тот же трек из другого": "A track won’t play on its own service — the same track from another one",
        "Порядок резервных сервисов": "Fallback service order",
        "Трек недоступен, есть только отрывок или нужна подписка — Sonar найдёт его в другом сервисе (исполнитель, название и длительность совпадают) и скажет, откуда играет.":
            "If a track is unavailable, only a preview, or needs a subscription, Sonar finds it on another service (same artist, title and length) and tells you where it’s playing from.",
        "SoundCloud: доступен только отрывок": "SoundCloud: only a preview is available",
        "Яндекс Музыка: доступно только превью": "Yandex Music: only a preview is available",
        "Где искать трек сначала — порядок меняют стрелки. Яндекс Музыка и VK Музыка ищутся, только если подключены.":
            "Where to look for the track first — reorder with the arrows. Yandex Music and VK Music are searched only when connected.",
        "Выше": "Move up",
        "Ниже": "Move down",
    ]

    static let fallbackUK: [String: String] = [
        "Играет из {to} — в {from} недоступен": "Грає з {to} — у {from} недоступний",
        "Играет из {to} — в {from} только отрывок": "Грає з {to} — у {from} лише уривок",
        "Играет из {to} — в {from} нужна подписка": "Грає з {to} — у {from} потрібна підписка",
        "Резервный сервис": "Резервний сервіс",
        "Трек не играет в своём сервисе — тот же трек из другого": "Трек не грає у своєму сервісі — той самий трек з іншого",
        "Порядок резервных сервисов": "Порядок резервних сервісів",
        "Трек недоступен, есть только отрывок или нужна подписка — Sonar найдёт его в другом сервисе (исполнитель, название и длительность совпадают) и скажет, откуда играет.":
            "Трек недоступний, є лише уривок або потрібна підписка — Sonar знайде його в іншому сервісі (виконавець, назва й тривалість збігаються) і скаже, звідки грає.",
        "SoundCloud: доступен только отрывок": "SoundCloud: доступний лише уривок",
        "Яндекс Музыка: доступно только превью": "Яндекс Музика: доступне лише прев’ю",
        "Где искать трек сначала — порядок меняют стрелки. Яндекс Музыка и VK Музыка ищутся, только если подключены.":
            "Де шукати трек спочатку — порядок змінюють стрілки. Яндекс Музика і VK Музика шукаються, лише якщо підключені.",
        "Выше": "Вище",
        "Ниже": "Нижче",
    ]
}
