import Foundation

// Текст песни на телефоне — тот же формат, что в Windows (docs/LYRICS.md §1, `windows/src-tauri/src/lyrics/mod.rs`),
// только время — начало и конец вместо начала и длительности. Тексты ищет само приложение (SPEC §3.7б):
// lrclib → NetEase → Genius, порядок — `LyricsFinder`.

/// Слово с таймингом (караоке по словам). Секунды трека.
struct LyricWord: Sendable, Equatable, Codable {
    var start: Double
    var end: Double
    var text: String
    /// После слова пробел (при сборке строки из слов). У последнего слова строки — `false`.
    var spaceAfter: Bool = true
    /// Слово в скобках — бэк-вокал (меньше и тише).
    var isBackground: Bool = false

    var duration: Double { max(0, end - start) }
}

/// Строка текста. Пустой `text` — пауза (проигрыш, там «• • •»).
struct LyricLine: Sendable, Equatable, Codable, Identifiable {
    /// Порядковый номер строки в тексте (0, 1, 2…).
    var id: Int
    var start: Double
    var end: Double
    var text: String
    /// Пусто — построчная синхронизация.
    var words: [LyricWord]
    /// Строка целиком в скобках — бэк-вокал.
    var isBackground: Bool = false

    var duration: Double { max(0, end - start) }
    var isPause: Bool { text.isEmpty }
}

struct Lyrics: Sendable, Equatable, Codable {
    var lines: [LyricLine]
    /// Есть время строк (lrclib synced, NetEase). Нет — обычный текст без подсветки и автопрокрутки.
    var synced: Bool
    /// Есть время слов (NetEase YRC, enhanced-LRC lrclib).
    var wordSynced: Bool
    /// «lrclib» / «NetEase» / «Genius» — так и показывается («Текст: Genius»).
    var source: String

    init(lines: [LyricLine], synced: Bool, wordSynced: Bool? = nil, source: String) {
        // номера строк — всегда по порядку
        self.lines = lines.enumerated().map { index, line in
            var line = line
            line.id = index
            return line
        }
        self.synced = synced
        self.wordSynced = wordSynced ?? (synced && lines.contains { !$0.words.isEmpty })
        self.source = source
    }

    static let lrclib = "lrclib"
    static let netease = "NetEase"
    static let genius = "Genius"
}

/// Аннотация Genius к фрагменту текста (кавычка у строки, свиток с пояснением).
struct LyricsAnnotation: Sendable, Equatable, Codable {
    /// Строки фрагмента, как на Genius.
    var lines: [String]
    var body: String
    /// Проверена редакцией Genius.
    var reviewed: Bool
}

// MARK: - Настройки вида (docs/SETTINGS.md «Текст песни», rawValue — значения ключей `lyrics.*`)

/// `lyrics.mode`: подсветка по словам или по строкам (как `LyricsMode` в Windows).
enum LyricsMode: String, CaseIterable, Sendable {
    case words, lines

    var title: String {
        switch self {
        case .words: "По словам"
        case .lines: "По строкам"
        }
    }
}

/// `lyrics.style` — стиль подсветки (как `lyricsStyles` в `lyrics.svelte.ts`).
enum LyricsTextStyle: String, CaseIterable, Sendable {
    case normal, scale, blur, cinema, shift

    var title: String {
        switch self {
        case .normal: "Обычный"
        case .scale: "Масштаб"
        case .blur: "Размытие"
        case .cinema: "Кино"
        case .shift: "Сдвиг"
        }
    }
}

/// `lyrics.animation` — смена строки и проявление слов (как `lyricsAnimations` в `lyrics.svelte.ts`).
enum LyricsAnimation: String, CaseIterable, Sendable {
    case normal, fade, blur, flip3d, bounce, wave, float, drift, zoom
    /// Строки подтягиваются вверх лесенкой — каждая следующая чуть позже («магнит»). Сами строки
    /// и слова ведут себя как в «Обычной».
    case ladder

    var title: String {
        switch self {
        case .normal: "Обычная"
        case .fade: "Фейд"
        case .blur: "Размытие"
        case .flip3d: "3D Переворот"
        case .bounce: "Отскок"
        case .wave: "Волна"
        case .float: "Всплытие"
        case .drift: "Дрифт"
        case .zoom: "Глубина"
        case .ladder: "Лесенка"
        }
    }

    /// Как строки и слова выглядят: «Лесенка» — это прокрутка, остальное как у «Обычной».
    var look: LyricsAnimation { self == .ladder ? .normal : self }
}

/// `lyrics.size` — размер текста: S / M / L / XL = 1.25 / 1.6 / 2 / 2.5 rem.
enum LyricsSize: String, CaseIterable, Sendable {
    case s = "S", m = "M", l = "L", xl = "XL"

    var rem: Double {
        switch self {
        case .s: 1.25
        case .m: 1.6
        case .l: 2
        case .xl: 2.5
        }
    }

    /// В пунктах (rem × 16): 20 / 25.6 / 32 / 40.
    var points: CGFloat { CGFloat(rem * 16) }
}
