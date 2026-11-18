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
    ]
}
