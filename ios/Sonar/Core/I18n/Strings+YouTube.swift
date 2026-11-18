// Строки YouTube Music на iPhone: вход, вставка cookie, качество. Те, что есть на ПК
// (windows/src/i18n/*/yt.ts), повторяют его перевод — после `gen-i18n.mjs` они просто совпадут.
// Ключ — русская строка, как в Strings+iOS.swift.

extension I18n {
    static let youtubeEN: [String: String] = [
        "AAC · 128 кбит/с": "AAC · 128 kbps",
        "AAC · до 256 кбит/с": "AAC · up to 256 kbps",
        "Без входа работают поиск, исполнители, альбомы и прослушивание. Вход нужен для «Лайков» и твоих плейлистов. Если Google не пустит во встроенный браузер — вставь cookie music.youtube.com вручную.":
            "Search, artists, albums and playback work without signing in. Sign in for «Likes» and your playlists. If Google won’t let you in through the built-in browser, paste the music.youtube.com cookie by hand.",
        "Вход в YouTube Music": "Sign in to YouTube Music",
        "Войти в YouTube Music": "Sign in to YouTube Music",
        "Качество треков YouTube Music: обычное бережёт трафик, высокое звучит лучше": "YouTube Music track quality: normal saves data, high sounds better",
        "На iPhone — AAC: высокое — 256 кбит/с, если YouTube его отдаёт, иначе 128.": "On iPhone it’s AAC: high is 256 kbps when YouTube serves it, otherwise 128.",
        "Cookie music.youtube.com": "music.youtube.com cookie",
        "YouTube::Обычное": "Normal",
        // ошибки (ServiceError) — экран «Сервисы» и плашка «Не играет» пропускают их через t()
        "Не играет «{title}»: {reason}": "Can’t play «{title}»: {reason}",
        "Вставь cookie YouTube Music": "Paste your YouTube Music cookie",
        "В cookie нет SAPISID — войди на music.youtube.com и скопируй cookie заново": "The cookie has no SAPISID — sign in at music.youtube.com and copy the cookie again",
        "YouTube Music не подключён": "YouTube Music isn’t connected",
        "YouTube Music не подключён — открой Профиль → Сервисы": "YouTube Music isn’t connected — open Profile → Services",
        "YouTube Music: cookie не подошёл или устарел — войди заново": "YouTube Music: the cookie didn’t work or has expired — sign in again",
        "YouTube Music: в cookie нет SAPISID — войди заново": "YouTube Music: the cookie has no SAPISID — sign in again",
        "YouTube Music: альбом не найден": "YouTube Music: album not found",
        "YouTube Music: исполнитель не найден": "YouTube Music: artist not found",
        "YouTube Music: плейлист не найден": "YouTube Music: playlist not found",
        "YouTube Music: не выдал visitorData": "YouTube Music didn’t return visitorData",
        "YouTube Music: у трека нет аудио AAC": "YouTube Music: this track has no AAC audio",
        "YouTube Music: у трека нет аудио с прямой ссылкой": "YouTube Music: this track has no direct audio link",
        "YouTube Music: файл скачался не целиком": "YouTube Music: the file didn’t download completely",
        "Не удалось сохранить файл": "Couldn’t save the file",
    ]

    static let youtubeUK: [String: String] = [
        "AAC · 128 кбит/с": "AAC · 128 кбіт/с",
        "AAC · до 256 кбит/с": "AAC · до 256 кбіт/с",
        "Без входа работают поиск, исполнители, альбомы и прослушивание. Вход нужен для «Лайков» и твоих плейлистов. Если Google не пустит во встроенный браузер — вставь cookie music.youtube.com вручную.":
            "Без входу працюють пошук, виконавці, альбоми й прослуховування. Вхід потрібен для «Лайків» і твоїх плейлистів. Якщо Google не пустить у вбудований браузер — встав cookie music.youtube.com вручну.",
        "Вход в YouTube Music": "Вхід у YouTube Music",
        "Войти в YouTube Music": "Увійти в YouTube Music",
        "Качество треков YouTube Music: обычное бережёт трафик, высокое звучит лучше": "Якість треків YouTube Music: звичайна береже трафік, висока звучить краще",
        "На iPhone — AAC: высокое — 256 кбит/с, если YouTube его отдаёт, иначе 128.": "На iPhone — AAC: висока — 256 кбіт/с, якщо YouTube її віддає, інакше 128.",
        "Cookie music.youtube.com": "Cookie music.youtube.com",
        "YouTube::Обычное": "Звичайна",
        // помилки (ServiceError) — екран «Сервіси» і плашка «Не грає» пропускають їх через t()
        "Не играет «{title}»: {reason}": "Не грає «{title}»: {reason}",
        "Вставь cookie YouTube Music": "Встав cookie YouTube Music",
        "В cookie нет SAPISID — войди на music.youtube.com и скопируй cookie заново": "У cookie немає SAPISID — увійди на music.youtube.com і скопіюй cookie знову",
        "YouTube Music не подключён": "YouTube Music не підключено",
        "YouTube Music не подключён — открой Профиль → Сервисы": "YouTube Music не підключено — відкрий Профіль → Сервіси",
        "YouTube Music: cookie не подошёл или устарел — войди заново": "YouTube Music: cookie не підійшов або застарів — увійди знову",
        "YouTube Music: в cookie нет SAPISID — войди заново": "YouTube Music: у cookie немає SAPISID — увійди знову",
        "YouTube Music: альбом не найден": "YouTube Music: альбом не знайдено",
        "YouTube Music: исполнитель не найден": "YouTube Music: виконавця не знайдено",
        "YouTube Music: плейлист не найден": "YouTube Music: плейлист не знайдено",
        "YouTube Music: не выдал visitorData": "YouTube Music не видав visitorData",
        "YouTube Music: у трека нет аудио AAC": "YouTube Music: у треку немає аудіо AAC",
        "YouTube Music: у трека нет аудио с прямой ссылкой": "YouTube Music: у треку немає аудіо з прямим посиланням",
        "YouTube Music: файл скачался не целиком": "YouTube Music: файл завантажився не повністю",
        "Не удалось сохранить файл": "Не вдалося зберегти файл",
    ]
}
