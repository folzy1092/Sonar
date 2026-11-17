import Foundation

// Значения настроек раздела «Плеер» (SETTINGS.md: Аудио, Плеер, Очередь): rawValue — то, что лежит в
// `SettingsStore`, ключи и значения общие с ПК. Умолчания — `SettingsDefaults+Player.swift`. Незнакомое
// значение (пришло с другой версии) — умолчание, а не падение.

/// Значение настройки-перечисления: ключ, умолчание, подпись и значок.
protocol PlayerChoice: RawRepresentable, CaseIterable, Identifiable, Hashable, Sendable where RawValue == String, AllCases == [Self] {
    static var key: String { get }
    static var fallback: Self { get }
    var title: String { get }
    var icon: IconName { get }
    /// Сохранённая строка → значение; незнакомое — умолчание.
    static func from(_ raw: String) -> Self
}

extension PlayerChoice {
    var id: String { rawValue }

    static func from(_ raw: String) -> Self {
        Self(rawValue: raw) ?? fallback
    }

    @MainActor
    static func current(_ settings: SettingsStore) -> Self {
        from(settings.string(key))
    }

    @MainActor
    func save(_ settings: SettingsStore) {
        settings.set(Self.key, .string(rawValue))
    }
}

/// Целые и дробные настройки: `SettingsStore` хранит число как int или double — читаем оба.
enum PlayerPrefs {
    @MainActor
    static func int(_ settings: SettingsStore, _ key: String) -> Int {
        switch settings.value(key) {
        case let .int(value)?: value
        case let .double(value)?: Int(value.rounded())
        case let .bool(value)?: value ? 1 : 0
        default: 0
        }
    }

    /// Кроссфейд в секундах, 0 — выключен (`audio.crossfade`; ПК хранит так же, числом).
    @MainActor
    static func crossfade(_ settings: SettingsStore) -> Int {
        max(0, min(Fades.maxCrossfade, int(settings, "audio.crossfade")))
    }
}

// MARK: - Аудио

/// Качество `audio.quality` (потолок для Яндекса; SoundCloud отдаёт свой максимум сам). `lossless` —
/// старое значение iPhone, читается как «Максимальное».
enum AudioQuality: String, PlayerChoice {
    case low, medium, high, max

    static let key = "audio.quality"
    static let fallback = AudioQuality.max

    static func from(_ raw: String) -> AudioQuality {
        raw == "lossless" ? .max : AudioQuality(rawValue: raw) ?? fallback
    }

    var title: String {
        switch self {
        case .low: "Низкое"
        case .medium: "Среднее"
        case .high: "Высокое"
        case .max: "Максимальное"
        }
    }

    var subtitle: String {
        switch self {
        case .low: "192 кбит/с"
        case .medium: "256 кбит/с"
        case .high: "320 кбит/с"
        case .max: "FLAC, от 1411 кбит/с"
        }
    }

    var icon: IconName {
        switch self {
        case .low: .music
        case .medium: .headphone
        case .high: .chartBar
        case .max: .disc
        }
    }
}

/// Звонок, Siri, будильник (`audio.on_interruption`). На iPhone их всегда ставит на паузу сама система —
/// выбор в том, что после: `duck` — вернуть музыку плавно (с 20 % громкости), `pause` — оставить на
/// паузе, `none` — вернуть сразу как было.
enum InterruptionMode: String, PlayerChoice {
    case duck, pause, none

    static let key = "audio.on_interruption"
    static let fallback = InterruptionMode.duck

    var title: String {
        switch self {
        case .duck: "Вернуть плавно"
        case .pause: "Оставить на паузе"
        case .none: "Вернуть сразу"
        }
    }

    var subtitle: String {
        switch self {
        case .duck: "Музыка продолжится тихо и за 2 секунды наберёт громкость"
        case .pause: "Продолжишь сам — кнопкой или с наушников"
        case .none: "Продолжится с той же громкостью"
        }
    }

    var icon: IconName {
        switch self {
        case .duck: .volume
        case .pause: .pause
        case .none: .play
        }
    }
}

// MARK: - Вид плеера

/// Стиль полного плеера `player.style`. `large` — обложка на весь фон (`player.jpg`, как было на iPhone),
/// `standard` — квадрат по центру, `vinyl` — пластинка крутится, пока играет.
enum PlayerStyle: String, PlayerChoice {
    case standard, vinyl, large

    static let key = "player.style"
    static let fallback = PlayerStyle.large

    var title: String {
        switch self {
        case .standard: "Обычный"
        case .vinyl: "Пластинка"
        case .large: "Большой"
        }
    }

    var icon: IconName {
        switch self {
        case .standard: .pic
        case .vinyl: .disc
        case .large: .fullscreen
        }
    }
}

/// Фон плеера `player.background` (для «Обычного» и «Пластинки»; у «Большого» фон — сама обложка).
enum PlayerBackground: String, PlayerChoice {
    case none, cover_blur, cover_color

    static let key = "player.background"
    static let fallback = PlayerBackground.cover_blur

    var title: String {
        switch self {
        case .none: "Без фона"
        case .cover_blur: "Размытая обложка"
        case .cover_color: "Цвет обложки"
        }
    }

    var icon: IconName {
        switch self {
        case .none: .eyeClosed
        case .cover_blur: .contrast
        case .cover_color: .palette
        }
    }
}

/// Выравнивание названия `player.title_align`.
enum TitleAlign: String, PlayerChoice {
    case left, center, right

    static let key = "player.title_align"
    static let fallback = TitleAlign.center

    var title: String {
        switch self {
        case .left: "Слева"
        case .center: "По центру"
        case .right: "Справа"
        }
    }

    var icon: IconName {
        switch self {
        case .left: .textLines
        case .center: .alignCenter
        case .right: .alignRight
        }
    }
}

/// Ползунок прогресса `player.slider`.
enum SliderStyle: String, PlayerChoice {
    case normal, thin, smooth, wavy, wave_bars

    static let key = "player.slider"
    static let fallback = SliderStyle.normal

    var title: String {
        switch self {
        case .normal: "Обычный"
        case .thin: "Тонкий"
        case .smooth: "Плавный"
        case .wavy: "Волнистый"
        case .wave_bars: "Волновой"
        }
    }

    var icon: IconName {
        switch self {
        case .normal: .dash
        case .thin: .thinLine
        case .smooth: .circle
        case .wavy: .waveLine
        case .wave_bars: .chartBar
        }
    }

    /// Высоты столбиков «Волнового» 0…1 — постоянные для трека (от его ref), чтобы не прыгали.
    static func bars(count: Int, seed: String) -> [Double] {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let phase = Double(hash % 1000) / 1000 * 6.28
        return (0 ..< max(0, count)).map { i in
            let x = Double(i)
            return 0.3 + 0.7 * abs(sin(x * 1.7 + phase) * cos(x * 0.31 + phase / 2))
        }
    }
}

/// Кнопка «играть» `player.play_button`.
enum PlayButtonStyle: String, PlayerChoice {
    case circle, square, clean

    static let key = "player.play_button"
    static let fallback = PlayButtonStyle.circle

    var title: String {
        switch self {
        case .circle: "Круг"
        case .square: "Квадрат"
        case .clean: "Без фона"
        }
    }

    var icon: IconName {
        switch self {
        case .circle: .playCircle
        case .square: .square
        case .clean: .play
        }
    }
}

// MARK: - Очередь

/// Вид строк очереди `queue.view`: `normal` — компактно, без обложек.
enum QueueView: String, PlayerChoice {
    case normal, extended

    static let key = "queue.view"
    static let fallback = QueueView.extended

    var title: String {
        switch self {
        case .normal: "Обычный"
        case .extended: "Развёрнутый"
        }
    }

    var icon: IconName {
        switch self {
        case .normal: .listCollapse
        case .extended: .listExpand
        }
    }
}

/// Что вернуть при запуске `general.restore`.
enum RestoreMode: String, PlayerChoice {
    case none, track, queue

    static let key = "general.restore"
    static let fallback = RestoreMode.queue

    var title: String {
        switch self {
        case .none: "Ничего"
        case .track: "Трек"
        case .queue: "Очередь"
        }
    }

    var icon: IconName {
        switch self {
        case .none: .close
        case .track: .music
        case .queue: .queue
        }
    }
}
