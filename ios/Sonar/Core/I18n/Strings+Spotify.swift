// Строки Spotify на iPhone (этап 3 NEXT_PROMPT): «Сервисы», окно входа, ошибки `Spotify.swift`. Отдельным
// словарём, чтобы не трогать общий сгенерированный Strings+Windows.swift; ключ — русская строка, переводы —
// те же, что в windows/src/i18n/{en,uk}/sp.ts.

extension I18n {
    static let spotifyEN: [String: String] = [
        "Вход в SoundCloud": "Sign in to SoundCloud",
        "Вход в Spotify": "Sign in to Spotify",
        "Войти в Spotify": "Sign in to Spotify",
        "Ключ sp_dc": "sp_dc key",
        "Подключено": "Connected",
        "Подключено · Premium": "Connected · Premium",
        "На iPhone Spotify не играет: лайки, плейлисты и поиск — отсюда, а трек сыграет резервный сервис. На ПК с Premium Spotify играет сам.":
            "Spotify does not play on iPhone: likes, playlists and search come from it, and the track plays through a fallback service. On a PC with Premium, Spotify plays by itself.",
        "Любимые треки": "Liked Songs",
        "Spotify: нужен резервный сервис": "Spotify: a fallback service is needed",
        "Spotify не подключён — открой Настройки → Сервисы": "Spotify is not connected — open Settings → Services",
        "Вставь значение cookie sp_dc с open.spotify.com": "Paste the sp_dc cookie value from open.spotify.com",
        "Spotify: ключ sp_dc не подошёл — войди заново": "Spotify: the sp_dc key did not work — sign in again",
        "Spotify: ключ веб-плеера устарел — нужно обновление Sonar": "Spotify: the web player key is outdated — Sonar needs an update",
        "Spotify: непонятный ответ веб-плеера": "Spotify: unexpected web player response",
        "Spotify: open.spotify.com недоступен": "Spotify: open.spotify.com is unreachable",
        "Spotify: альбом не найден": "Spotify: album not found",
        "Spotify: исполнитель не найден": "Spotify: artist not found",
        "Spotify: плейлист не найден": "Spotify: playlist not found",
    ]

    static let spotifyUK: [String: String] = [
        "Вход в SoundCloud": "Вхід у SoundCloud",
        "Вход в Spotify": "Вхід у Spotify",
        "Войти в Spotify": "Увійти в Spotify",
        "Ключ sp_dc": "Ключ sp_dc",
        "Подключено": "Підключено",
        "Подключено · Premium": "Підключено · Premium",
        "На iPhone Spotify не играет: лайки, плейлисты и поиск — отсюда, а трек сыграет резервный сервис. На ПК с Premium Spotify играет сам.":
            "На iPhone Spotify не грає: лайки, плейлисти й пошук — звідси, а трек зіграє резервний сервіс. На ПК з Premium Spotify грає сам.",
        "Любимые треки": "Улюблені треки",
        "Spotify: нужен резервный сервис": "Spotify: потрібен резервний сервіс",
        "Spotify не подключён — открой Настройки → Сервисы": "Spotify не підключено — відкрий Налаштування → Сервіси",
        "Вставь значение cookie sp_dc с open.spotify.com": "Встав значення cookie sp_dc з open.spotify.com",
        "Spotify: ключ sp_dc не подошёл — войди заново": "Spotify: ключ sp_dc не підійшов — увійди знову",
        "Spotify: ключ веб-плеера устарел — нужно обновление Sonar": "Spotify: ключ веб-плеєра застарів — потрібне оновлення Sonar",
        "Spotify: непонятный ответ веб-плеера": "Spotify: незрозуміла відповідь веб-плеєра",
        "Spotify: open.spotify.com недоступен": "Spotify: open.spotify.com недоступний",
        "Spotify: альбом не найден": "Spotify: альбом не знайдено",
        "Spotify: исполнитель не найден": "Spotify: виконавця не знайдено",
        "Spotify: плейлист не найден": "Spotify: плейлист не знайдено",
    ]
}
