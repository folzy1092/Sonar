import Foundation

// Поиск по настройкам iPhone — строка сверху Профиля (порт ПК `windows/src/lib/settings-catalog.ts`). Каталог —
// статичный список пунктов: экран, на котором пункт лежит, название ровно как на экране (русская строка — ключ
// перевода) и слова-синонимы. Ищет по переводу текущего языка и по русскому ключу, без учёта регистра и ё/е.
// Только Foundation — экраны и значки к `SettingsPane` привязывает `Features/Settings/SettingsSearchViews.swift`.
// Новый пункт на экране настроек — строка сюда (тест `SettingsSearchTests` проверит, что у названия есть перевод).

/// Экран настроек, на который ведёт пункт: те же строки, что в Профиле (`ProfileView`).
enum SettingsPane: String, CaseIterable, Sendable {
    case profile, stats, security, privacy, subscription
    case look, appIcon, tabs
    case audio, playerView, queue, taste, miniPlayer, gestures
    case soundcloud, yandex, youtube
    case apiKey
    case general, updates, storage

    /// Название экрана — как строка в Профиле (русский ключ перевода).
    var title: String {
        switch self {
        case .profile: "Профиль"
        case .stats: "Статистика"
        case .security: "Безопасность"
        case .privacy: "Приватность"
        case .subscription: "Подписка"
        case .look: "Вид"
        case .appIcon: "Значок приложения"
        case .tabs: "Вкладки"
        case .audio: "Аудио"
        case .playerView: "Вид плеера"
        case .queue: "Очередь"
        case .taste: "Вкус"
        case .miniPlayer: "Мини-плеер"
        case .gestures: "Жесты"
        case .soundcloud: "SoundCloud"
        case .yandex: "Яндекс Музыка"
        case .youtube: "YouTube Music"
        case .apiKey: "Ключ API"
        case .general: "Общее"
        case .updates: "Обновления"
        case .storage: "Хранилище"
        }
    }

    /// Раздел Профиля, в котором лежит экран.
    var section: String {
        switch self {
        case .profile, .stats, .security, .privacy, .subscription: "Аккаунт"
        case .look, .appIcon, .tabs: "Интерфейс"
        case .audio, .playerView, .queue, .taste, .miniPlayer, .gestures: "Плеер"
        case .soundcloud, .yandex, .youtube: "Сервисы"
        case .apiKey: "Интеграции"
        case .general, .updates, .storage: "Система"
        }
    }

    /// Экран, из которого открывается этот (не из Профиля напрямую).
    var parent: SettingsPane? {
        self == .appIcon ? .look : nil
    }

    /// Путь до экрана: раздел, промежуточные экраны и сам экран (русские ключи).
    var path: [String] {
        [section] + (parent.map { [$0.title] } ?? []) + [title]
    }
}

/// Пункт каталога: где лежит, как называется на экране, по каким ещё словам находится.
struct SettingsItem: Hashable, Sendable {
    let pane: SettingsPane
    /// Название ровно как на экране — русская строка, ключ перевода (можно с контекстом `контекст::Слово`).
    let title: String
    /// Синонимы и английские названия — ищутся как есть, без перевода.
    let words: String

    /// Пункт — сам экран (строка Профиля), а не настройка на нём.
    var isPane: Bool { title == pane.title }

    /// Подпись под названием в результатах: «Раздел → Экран»; у самого экрана — без него.
    var path: [String] {
        isPane ? Array(pane.path.dropLast()) : pane.path
    }
}

enum SettingsSearch {
    /// Больше на экран телефона не влезает с клавиатурой — как `MAX_HITS` на ПК.
    static let maxHits = 12

    /// Вес совпадения: название с начала слова важнее середины, русского ключа и синонимов (как на ПК).
    private enum Weight {
        static let titleStart = 6
        static let title = 4
        static let original = 3
        static let words = 1
    }

    // MARK: каталог — порядок как пункты идут на экранах

    private static func items(_ pane: SettingsPane, _ rows: [(String, String)]) -> [SettingsItem] {
        rows.map { SettingsItem(pane: pane, title: $0.0, words: $0.1) }
    }

    static let catalog: [SettingsItem] =
        items(.profile, [
            ("Профиль", "аватар имя ник username profile"),
            ("Отображаемое имя", "имя name"),
            ("Имя пользователя", "username ник логин @"),
        ])
        + items(.stats, [("Статистика", "итоги прослушивания минуты часы stats")])
        + items(.security, [("Безопасность", "пароль устройства сессии выход password devices security")])
        + items(.privacy, [
            ("Приватность", "скрыть профиль privacy"),
            ("Кто может добавить в друзья", "друзья заявки приватность"),
            ("Плейлисты", "приватность скрыть"),
            ("Любимые", "приватность скрыть лайки"),
            ("Что играет сейчас", "приватность скрыть now playing"),
            ("Статистика", "приватность скрыть"),
            ("Кто может писать мне", "сообщения лс чат приватность"),
            ("Кто может звать в комнату", "комната вместе приглашение приватность"),
            ("Кто видит мою комнату", "комната вместе приватность"),
        ])
        + items(.subscription, [("Подписка", "sonar deep тариф оплата premium плюс ping echo pod fleet")])
        + items(.look, [
            ("Вид", "оформление внешний look"),
            ("Тема", "темная светлая ночь dark light theme"),
            ("Цвет", "акцент под трек обложка color"),
            ("Сила темы под обложку", "оттенок слабо сильно"),
            ("Стиль", "классика оформление style"),
            ("Фон", "картинка обои фото background"),
            ("Затемнение", "фон темнее dim"),
            ("Размытие", "фон blur"),
            ("Прозрачность", "стекло glass"),
            ("Непрозрачность", "стекло opacity"),
            ("Тип стекла", "glass"),
            ("Скругление", "углы corners"),
            ("Анимации", "движение переходы motion animation"),
        ])
        + items(.appIcon, [("Значок приложения", "иконка icon app")])
        + items(.tabs, [
            ("Вкладки", "таб-бар панель tabs"),
            ("Подстраивать вкладки", "цвет панель таб-бар"),
            ("Сворачивать при прокрутке", "таб-бар панель мини-плеер"),
        ])
        + items(.audio, [
            ("Аудио", "звук sound audio"),
            ("Качество", "flac 320 битрейт кбит kbps quality youtube"),
            ("SoundCloud в качестве Яндекса", "качество flac yandex"),
            ("Резервный сервис", "резерв замена недоступен превью отрывок fallback"),
            ("Нормализация громкости", "громкость уровень loudness r128"),
            ("Бесшовное воспроизведение", "без паузы gapless"),
            ("Кроссфейд", "переход затухание crossfade"),
            ("Сведение", "dj переход blend микс"),
            ("Эквалайзер", "eq частоты басы equalizer"),
            ("После звонка и Siri", "звонок будильник пауза прерывание interruption"),
        ])
        + items(.playerView, [
            ("Вид плеера", "плеер player"),
            ("Стиль плеера", "плеер обложка"),
            ("Фон плеера", "плеер background"),
            ("Выравнивание названия", "плеер название центр"),
            ("Ползунок", "прогресс время slider"),
            ("Кнопка «играть»", "play пауза"),
            ("Аватарки артистов", "исполнитель аватар"),
            ("Таймер сна в плеере", "сон sleep timer"),
        ])
        + items(.queue, [
            ("Очередь", "queue"),
            ("Продолжить с прошлого раза", "восстановить очередь resume"),
            ("Вид очереди", "очередь"),
            ("Предпросмотр следующего", "дальше следующий трек"),
            ("Авто похожие", "автоплей autoplay похожие"),
            ("Добавлять следующие", "очередь после"),
            ("Sonar Mix", "моя волна wave микс"),
            ("Волна без сети", "sonar mix офлайн wi-fi wifi"),
            ("Почему этот трек", "sonar mix похож причина"),
        ])
        + items(.taste, [
            ("Вкус", "артисты чаще реже никогда taste"),
            ("Не нравится", "дизлайк dislike"),
        ])
        + items(.miniPlayer, [
            ("Мини-плеер", "мини плеер mini player"),
            ("Индикаторы прогресса", "мини-плеер прогресс"),
            ("Форма обложки", "мини-плеер обложка"),
            ("Скругление границ", "мини-плеер углы"),
        ])
        + items(.gestures, [
            ("Жесты", "свайп смахнуть swipe gestures"),
            ("Обложка плеера", "двойной тап тройной лайк сердце жесты"),
        ])
        + items(.soundcloud, [("SoundCloud", "саундклауд client_id oauth токен вход")])
        + items(.yandex, [("Яндекс Музыка", "yandex токен вход y0")])
        + items(.youtube, [("YouTube Music", "ютуб youtube google cookie вход")])
        + items(.apiKey, [("Ключ API", "selfbot токен now playing сейчас играет api key")])
        + items(.general, [
            ("Общее", "general"),
            ("Офлайн-режим", "без сети интернет offline"),
            ("Предлагать офлайн-режим", "сеть пропала offline"),
            ("Язык интерфейса", "language english русский украинский"),
            ("Платформа", "главная sonar mix волна soundcloud яндекс"),
            ("Добавление", "плейлист в начало в конец"),
            ("Тактильный отклик", "вибрация haptic"),
            ("Новинки исполнителей", "уведомления релизы альбом сингл"),
            ("Синхронизация", "синк sync аккаунт"),
            ("Сбросить настройки", "сброс reset"),
        ])
        + items(.updates, [
            ("Обновления", "версия update"),
            ("Проверять автоматически", "автообновление update"),
            ("Канал", "бета стабильный beta"),
            ("Сертификат для подписи", "p12 mobileprovision подпись установка"),
            ("Архив версий", "история версии changelog"),
        ])
        + items(.storage, [
            ("Хранилище", "место память кэш кеш storage"),
            ("Скачанные треки", "загрузки скачать офлайн downloads"),
            ("Только по Wi‑Fi", "wifi wi-fi сотовая скачивание"),
            ("Скачивать Любимые", "автоскачивание лайки"),
            ("Лимит для Любимых", "место скачанные"),
            ("Очистка кеша", "кэш кеш обложки тексты cache"),
            ("История прослушиваний", "данные удалить"),
            ("История поиска", "данные удалить"),
        ])

    // MARK: поиск

    /// Нижний регистр, ё → е, неразрывный дефис → обычный, лишние пробелы прочь.
    static func normalize(_ text: String) -> String {
        fold(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Слова запроса после `normalize`; пусто — запроса нет.
    static func tokens(_ query: String) -> [String] {
        normalize(query).split(separator: " ").map(String.init)
    }

    /// Пункты по запросу: все слова запроса должны найтись; `translate` — перевод текущего языка (`I18n.translate`).
    /// При равном счёте — порядок каталога (он же порядок пунктов на экранах).
    static func search(_ query: String, translate: (String) -> String, limit: Int = maxHits) -> [SettingsItem] {
        let toks = tokens(query)
        guard !toks.isEmpty else { return [] }
        let scored: [(item: SettingsItem, score: Int, order: Int)] = catalog.enumerated().compactMap { order, item in
            let title = normalize(translate(item.title))
            let original = normalize(plain(item.title))
            let words = normalize(item.words)
            let scores = toks.map { score($0, title: title, original: original, words: words) }
            guard !scores.contains(0) else { return nil }
            return (item, scores.reduce(0, +), order)
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            .prefix(limit)
            .map(\.item)
    }

    /// Кусок текста: совпал со словом запроса или нет — для подсветки в результатах.
    struct Piece: Equatable, Sendable {
        let text: String
        let isMatch: Bool
    }

    /// Текст на куски с отметкой совпадений со словами запроса (регистр и ё/е не важны).
    static func marks(in text: String, query: String) -> [Piece] {
        let chars = Array(text)
        let folded = chars.map { fold(String($0)) }
        let matched = tokens(query).reduce(into: Array(repeating: false, count: chars.count)) { flags, tok in
            for range in occurrences(of: Array(tok).map(String.init), in: folded) {
                flags.replaceSubrange(range, with: repeatElement(true, count: range.count))
            }
        }
        return zip(chars, matched).reduce(into: [Piece]()) { pieces, pair in
            if let last = pieces.last, last.isMatch == pair.1 {
                pieces[pieces.count - 1] = Piece(text: last.text + String(pair.0), isMatch: last.isMatch)
            } else {
                pieces.append(Piece(text: String(pair.0), isMatch: pair.1))
            }
        }
    }

    // MARK: внутреннее

    private static func fold(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "\u{2011}", with: "-")
    }

    /// Ключ с контекстом `контекст::Слово` — на экране только «Слово».
    private static func plain(_ key: String) -> String {
        key.range(of: "::").map { String(key[$0.upperBound...]) } ?? key
    }

    private static func score(_ tok: String, title: String, original: String, words: String) -> Int {
        if let at = title.range(of: tok)?.lowerBound {
            let atWordStart = at == title.startIndex || title[title.index(before: at)] == " "
            return atWordStart ? Weight.titleStart : Weight.title
        }
        if original.contains(tok) { return Weight.original }
        return words.contains(tok) ? Weight.words : 0
    }

    /// Где в тексте (по символам) встречается слово, без наложений.
    private static func occurrences(of needle: [String], in haystack: [String]) -> [Range<Int>] {
        guard !needle.isEmpty, needle.count <= haystack.count else { return [] }
        var found: [Range<Int>] = []
        var at = 0
        while at + needle.count <= haystack.count {
            if Array(haystack[at ..< at + needle.count]) == needle {
                found.append(at ..< at + needle.count)
                at += needle.count
            } else {
                at += 1
            }
        }
        return found
    }
}
