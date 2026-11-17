import SwiftUI

/// Вид мини-плеера (Профиль → Мини-плеер, скрины владельца `IMG_6781..6783`): заготовка или «свой» —
/// фон, прогресс, форма обложки, скругление. Ключи — SETTINGS.md «Вид»: `appearance.mini_player`,
/// `appearance.mini_background`, `appearance.progress_indicator`, `appearance.cover_shape`,
/// `appearance.corner_radius`. Пустое значение — умолчание заготовки «Капсула».
struct MiniStyle: Equatable {
    enum Preset: String, CaseIterable, Identifiable {
        case capsule, standard, minimal, deck, custom
        var id: String { rawValue }

        /// Заготовки на экране настроек: от самой тихой к самой яркой.
        static let shown: [Preset] = [.minimal, .capsule, .deck, .standard]

        var title: String {
            switch self {
            case .capsule: "Капсула"
            case .standard: "Обложка"
            case .minimal: "Тихий"
            case .deck: "Лента"
            case .custom: "Свой"
            }
        }

        var icon: IconName {
            switch self {
            case .capsule: .capsule
            case .standard: .pic
            case .minimal: .square
            case .deck: .layers
            case .custom: .edit
            }
        }
    }

    enum Background: String, CaseIterable, Identifiable {
        case coverColor = "cover_color", cover, theme
        var id: String { rawValue }

        var title: String {
            switch self {
            case .coverColor: "Цвет обложки"
            case .cover: "Сама обложка"
            case .theme: "Цвет темы"
            }
        }

        var icon: IconName {
            switch self {
            case .coverColor: .palette
            case .cover: .pic
            case .theme: .brush
            }
        }
    }

    enum CoverShape: String, CaseIterable, Identifiable {
        case circle, rounded, hidden
        var id: String { rawValue }

        var title: String {
            switch self {
            case .circle: "Круг"
            case .rounded: "Закруглённая"
            case .hidden: "Скрыть"
            }
        }

        var icon: IconName {
            switch self {
            case .circle: .circle
            case .rounded: .square
            case .hidden: .eyeClosed
            }
        }
    }

    enum Corners: String, CaseIterable, Identifiable {
        case none, soft, rounded, pill
        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: "Нет"
            case .soft: "Мягкое"
            case .rounded: "Среднее"
            case .pill: "Круглое"
            }
        }

        var icon: IconName {
            switch self {
            case .none, .soft, .rounded: .square
            case .pill: .circle
            }
        }

        /// Радиус для высоты плеера.
        func radius(height: CGFloat) -> CGFloat {
            switch self {
            case .none: 4
            case .soft: 14
            case .rounded: 22
            case .pill: height / 2
            }
        }
    }

    var background: Background
    var progress: Set<ProgressIndicator>
    var cover: CoverShape
    var corners: Corners

    static let presets: [Preset: MiniStyle] = [
        .capsule: MiniStyle(background: .coverColor, progress: [.ring], cover: .circle, corners: .pill),
        .standard: MiniStyle(background: .cover, progress: [.fill], cover: .rounded, corners: .rounded),
        .minimal: MiniStyle(background: .theme, progress: [.line], cover: .rounded, corners: .soft),
        .deck: MiniStyle(background: .cover, progress: [.line], cover: .hidden, corners: .none),
    ]

    static let keys = (preset: "appearance.mini_player", background: "appearance.mini_background",
                       cover: "appearance.cover_shape", corners: "appearance.corner_radius")

    /// Текущий вид из настроек.
    @MainActor
    static func current(_ settings: SettingsStore) -> MiniStyle {
        let base = presets[.capsule]!
        return MiniStyle(
            background: Background(rawValue: settings.string(keys.background)) ?? base.background,
            progress: ProgressIndicator.parse(settings.string(ProgressIndicator.key)),
            cover: CoverShape(rawValue: settings.string(keys.cover)) ?? base.cover,
            corners: Corners(rawValue: settings.string(keys.corners)) ?? base.corners
        )
    }

    /// Какая заготовка совпадает с видом; ни одна — «Свой».
    var preset: Preset {
        Self.presets.first { $0.value == self }?.key ?? .custom
    }

    @MainActor
    func save(_ settings: SettingsStore) {
        settings.set(Self.keys.background, .string(background.rawValue))
        settings.set(ProgressIndicator.key, .string(ProgressIndicator.encode(progress)))
        settings.set(Self.keys.cover, .string(cover.rawValue))
        settings.set(Self.keys.corners, .string(corners.rawValue))
        settings.set(Self.keys.preset, .string(preset.rawValue))
    }
}

/// Фон мини-плеера по виду: цвет обложки (стекло в оттенке акцента), сама обложка (размытая и
/// затемнённая) или стандартный (поверхность темы). Форма — по скруглению.
struct MiniPlayerSurface: View {
    var height: CGFloat = 64
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        let style = MiniStyle.current(settings)
        let shape = RoundedRectangle(cornerRadius: style.corners.radius(height: height), style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial)
            switch style.background {
            case .coverColor:
                shape.fill(Theme.accent.opacity(ThemeStore.shared.isMono ? 0.32 : 0.58))
            case .cover:
                CoverImage(url: engine.current?.coverURL, cornerRadius: 0)
                    .blur(radius: 6)
                    .overlay(Color.black.opacity(0.42))
                    .clipShape(shape)
                    .id(engine.current?.ref)
                    .transition(.opacity)
            case .theme:
                shape.fill(Theme.raised.opacity(0.85))
            }
        }
        .overlay(shape.strokeBorder(Theme.text.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .animation(Motion.spring, value: style)
        .animation(.easeInOut(duration: 0.45), value: engine.current?.ref)
    }
}
