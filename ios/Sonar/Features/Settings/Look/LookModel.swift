import Foundation

/// Интерфейс → Вид / Вкладки / Профиль: значения настроек `appearance.*`, `tabs.*`, `profile.*`
/// (docs/SETTINGS.md) и чистая логика темы — без SwiftUI, гоняется тестами. Эталон — Windows
/// `pages/settings/Look.svelte`, `Style.svelte`, `TabsView.svelte`, `Profile.svelte`, `theme/*.ts`.
enum LookKey {
    static let mode = "appearance.mode"
    static let coverTheme = "appearance.cover_theme"
    static let preset = "appearance.preset"
    static let style = "appearance.style"
    static let surface = "appearance.surface"
    static let background = "appearance.background"
    static let bgDim = "appearance.bg_dim"
    static let bgBlur = "appearance.bg_blur"
    static let glass = "appearance.glass"
    static let glassType = "appearance.glass_type"
    static let opacity = "appearance.opacity"
    static let animations = "appearance.animations"
    static let tabStyle = "appearance.tab_style"
    static let tabsAdapt = "tabs.adapt"
    static let tabsCollapse = "tabs.collapse"
    static let profileName = "profile.name"
    static let profileUsername = "profile.username"
    static let profileAvatar = "profile.avatar"
}

/// Тема: тёмная, светлая или как в системе (`appearance.mode`).
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case dark, light, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Тёмная"
        case .light: "Светлая"
        case .system: "Как в системе"
        }
    }

    func isLight(systemDark: Bool) -> Bool {
        switch self {
        case .dark: false
        case .light: true
        case .system: !systemDark
        }
    }
}

/// Фон приложения (`appearance.background`): тема, мягкий цвет обложки сверху, сама обложка
/// (размытая) или своя картинка из галереи (файл на телефоне).
enum BackdropMode: String, CaseIterable, Identifiable, Sendable {
    case standard, coverColor = "cover_color", cover, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Стандартный"
        case .coverColor: "Цвет обложки"
        case .cover: "Сама обложка"
        case .custom: "Свой"
        }
    }

    /// У фона-картинки есть затемнение и размытие.
    var isPicture: Bool { self == .cover || self == .custom }
}

/// Тип стекла панелей (`appearance.glass_type`).
enum GlassType: String, CaseIterable, Identifiable, Sendable {
    case balance, ultra, noBlur = "no_blur"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .balance: "Баланс"
        case .ultra: "Ультра"
        case .noBlur: "Без размытия"
        }
    }

    var subtitle: String {
        switch self {
        case .balance: "Плотное стекло, текст читается лучше"
        case .ultra: "Тонкое стекло, видно, что под ним"
        case .noBlur: "Только прозрачность, без размытия"
        }
    }
}

/// Стиль нижней панели (`appearance.tab_style`, скрин владельца «Стиль вкладок»).
enum TabBarStyle: String, CaseIterable, Identifiable, Sendable {
    case standard, rounded, floating, compact
    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Стандартный"
        case .rounded: "Закруглённый"
        case .floating: "Плавающий"
        case .compact: "Компактный"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: "Во всю ширину у края"
        case .rounded: "Во всю ширину, углы сверху"
        case .floating: "Парящая капсула"
        case .compact: "Узкая капсула, только значки"
        }
    }

    /// Панель во всю ширину экрана, прижата к нижнему краю.
    var fullWidth: Bool { self == .standard || self == .rounded }

    /// Подписи под значками.
    var showsTitles: Bool { fullWidth }

    var barHeight: Double { self == .compact ? 56 : 64 }

    /// Ширина панели в развёрнутом виде при ширине экрана `width` и боковом отступе `gutter`.
    func barWidth(screen width: Double, gutter: Double, tabs: Int) -> Double {
        switch self {
        case .standard, .rounded: width
        case .floating: max(0, width - gutter * 2)
        case .compact: min(max(0, width - gutter * 2), Double(tabs) * 58 + 12)
        }
    }

    /// Радиусы углов развёрнутой панели: верх, низ.
    func radii(height: Double) -> (top: Double, bottom: Double) {
        switch self {
        case .standard: (0, 0)
        case .rounded: (26, 0)
        case .floating, .compact: (height / 2, height / 2)
        }
    }
}

/// Готовый стиль Sonar (`appearance.style`, SETTINGS.md «Стиль», ПК `theme/style.ts` `STYLES`): ставит все
/// оси. На iPhone пока применяется поверхность; остальные оси пишутся как на ПК — чтобы синк не
/// превращал стиль в «Свой».
struct StylePreset: Identifiable, Sendable {
    let id: String
    let title: String
    let surface: Surface
    let font: String
    let fontDisplay: String
    let iconStroke: Double
    let animTrack: String
    let animLike: String
    let animNav: String
    let progressLook: String
    let loading: String

    static let all: [StylePreset] = [
        StylePreset(id: "sonar", title: "Sonar", surface: .monolith, font: "Golos Text Variable", fontDisplay: "Unbounded Variable",
                    iconStroke: 2, animTrack: "edge", animLike: "signal", animNav: "dot", progressLook: "line", loading: "color"),
        StylePreset(id: "echo", title: "Эхо", surface: .echo, font: "Onest Variable", fontDisplay: "Science Gothic Variable",
                    iconStroke: 1.75, animTrack: "echo", animLike: "echo", animNav: "dot", progressLook: "line", loading: "ring"),
        StylePreset(id: "signal", title: "Сигнал", surface: .signal, font: "Golos Text Variable", fontDisplay: "Unbounded Variable",
                    iconStroke: 2, animTrack: "signal", animLike: "signal", animNav: "capsule", progressLook: "wave", loading: "ring"),
        StylePreset(id: "edge", title: "Грань", surface: .edge, font: "Geist Variable", fontDisplay: "Geist Variable",
                    iconStroke: 1.75, animTrack: "edge", animLike: "edge", animNav: "plate", progressLook: "line", loading: "color"),
        StylePreset(id: "tactile", title: "Тактиль", surface: .tactile, font: "IBM Plex Sans Variable", fontDisplay: "IBM Plex Sans Variable",
                    iconStroke: 2, animTrack: "tactile", animLike: "tactile", animNav: "inset", progressLook: "groove", loading: "ring"),
        StylePreset(id: "monolith", title: "Монолит", surface: .monolith, font: "Inter Tight Variable", fontDisplay: "Inter Tight Variable",
                    iconStroke: 2, animTrack: "monolith", animLike: "monolith", animNav: "dot", progressLook: "line", loading: "color"),
    ]

    static func named(_ id: String) -> StylePreset? {
        all.first { $0.id == id }
    }

    /// Все оси стиля — ключи и значения, как пишет ПК `theme.applyStyle`.
    var axes: [String: SettingValue] {
        [
            LookKey.surface: .string(surface.rawValue),
            "appearance.font": .string(font),
            "appearance.font_display": .string(fontDisplay),
            "appearance.title_style": .string("plain"),
            "appearance.icon_stroke": .double(iconStroke),
            "appearance.anim_track": .string(animTrack),
            "appearance.anim_like": .string(animLike),
            "appearance.anim_nav": .string(animNav),
            "appearance.progress_look": .string(progressLook),
            "appearance.loading": .string(loading),
        ]
    }
}

/// Всё, от чего зависит тема, одним значением: меняется — `ThemeStore` пересчитывает токены.
struct LookInputs: Equatable, Sendable {
    var mode: AppearanceMode = .dark
    var coverTheme = true
    var preset = "neutral"
    var surface: Surface = .monolith

    @MainActor
    init(_ settings: SettingsStore) {
        mode = AppearanceMode(rawValue: settings.string(LookKey.mode)) ?? .dark
        coverTheme = settings.bool(LookKey.coverTheme)
        preset = settings.string(LookKey.preset)
        surface = Surface(rawValue: settings.string(LookKey.surface)) ?? .monolith
    }

    init(mode: AppearanceMode = .dark, coverTheme: Bool = true, preset: String = "neutral", surface: Surface = .monolith) {
        self.mode = mode
        self.coverTheme = coverTheme
        self.preset = preset
        self.surface = surface
    }
}

enum LookTheme {
    /// Токены темы, как ПК `Theme.apply`: под обложку — её цвет (серая или нет обложки — монохром),
    /// иначе готовая тема; формулы — выбранной поверхности, светлые или тёмные. AMOLED — только в тёмной.
    static func tokens(_ inputs: LookInputs, coverAccent: RGB?, systemDark: Bool) -> ThemeTokens {
        let light = inputs.mode.isLight(systemDark: systemDark)
        let preset = ThemePreset.named(inputs.preset)
        let source = inputs.coverTheme ? coverAccent : preset.accent
        let tokens = Palette.theme(from: source, surface: inputs.surface, light: light)
        return !inputs.coverTheme && preset.black && !light ? Palette.amoled(tokens) : tokens
    }

    /// Образец для плитки темы: акцент и фон (как ПК `swatch`). Neutral / AMOLED без цвета — светлый
    /// кружок на тёмном (чёрном).
    static func swatch(_ accent: RGB?, black: Bool = false, surface: Surface, light: Bool) -> (accent: RGB, bg: RGB) {
        guard let accent else { return (RGB(245, 245, 246), black ? RGB(0, 0, 0) : RGB(38, 38, 43)) }
        let t = Palette.theme(from: accent, surface: surface, light: light)
        return (t.accent, t.bg)
    }
}

/// Значение настройки-числа: на ПК числа приходят и целыми, и дробными.
extension SettingsStore {
    func number(_ key: String, fallback: Double) -> Double {
        switch value(key) {
        case let .int(v)?: Double(v)
        case let .double(v)?: v
        default: fallback
        }
    }
}

/// Локальный профиль до сервера (`profile.*`): имя, @username, аватар.
enum LocalProfile {
    static let fallbackName = "Sonar"
    static let nameLimit = 40

    /// Имя для шапки: `profile.name`, пусто — «Sonar».
    @MainActor
    static func name(_ settings: SettingsStore) -> String {
        let name = settings.string(LookKey.profileName).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallbackName : name
    }

    /// Имя к сохранению: без пробелов по краям, не длиннее 40 знаков.
    static func cleanName(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
    }

    /// @username без «@» и пробелов, как ПК `cleanUsername`.
    static func cleanUsername(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("@") { s.removeFirst() }
        return s
    }

    /// Латиница, цифры и «_», 3–32 знака (ПК `USERNAME_RE`). Пусто — можно (без @username).
    static func usernameValid(_ raw: String) -> Bool {
        let s = cleanUsername(raw)
        if s.isEmpty { return true }
        guard (3 ... 32).contains(s.count) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Первая буква для заглушки аватара.
    static func initial(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "S"
    }

    /// Аватар хранится в `profile.avatar` как data URL (как ПК — синхронизируется вместе с настройками).
    static func dataURL(jpeg: Data) -> String {
        "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    /// Байты картинки из data URL (`data:image/…;base64,…`); иное — nil.
    static func imageData(_ url: String) -> Data? {
        guard url.hasPrefix("data:image/"), let comma = url.firstIndex(of: ","),
              url[..<comma].hasSuffix(";base64") else { return nil }
        return Data(base64Encoded: String(url[url.index(after: comma)...]))
    }
}
