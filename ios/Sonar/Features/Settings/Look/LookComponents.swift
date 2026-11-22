import SwiftUI
import UIKit

// Общие детали экранов Интерфейса (Вид, Вкладки, Профиль) — в стиле «Мини-плеера»
// (`MiniPlayerSettingsView`): шапка «‹ · Название», плитки, карточки со строками, нижние листы выбора.

/// Экран: круглая «Назад» и капсула-заголовок, прокрутка (сворачивает нижнюю панель), прозрачный фон
/// поверх фона приложения.
struct LookScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(ChromeState.self) private var chrome
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    CircleButton(icon: .back, label: "Назад") { dismiss() }
                    Text(title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.raised.opacity(0.92), in: Capsule())
                }
                .padding(.top, 8)
                content
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            chrome.scrolled(to: offset)
        }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Подпись над группой.
struct LookCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.leading, 6)
            .padding(.top, 4)
    }
}

/// Карточка со строками, как у мини-плеера.
struct LookCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.vertical, 6)
            .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// Строка: название, текущее значение под ним, значок справа. Тап — лист выбора.
struct LookRow: View {
    let title: String
    let value: String
    let icon: IconName
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            LookRowLabel(title: title, value: value, icon: icon)
        }
        .buttonStyle(PressableStyle(scale: 0.99))
    }
}

struct LookRowLabel: View {
    let title: String
    let value: String
    let icon: IconName

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer()
            SonarIcon(icon, size: 26).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
    }
}

/// Тумблер с подписью («Прозрачность — Включено (80%)»).
struct LookToggle: View {
    let title: String
    let value: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn.animation(Motion.spring)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.opacity)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 22)
        .frame(minHeight: 72)
    }
}

/// Ползунок с числом справа; значение пишется при отпускании и на ходу (вид меняется вживую).
struct LookSlider: View {
    let title: String
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit = "%"
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(Int(value.rounded()))\(unit)")
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText(value: value))
                    .animation(Motion.quick, value: value)
            }
            Slider(value: $value, in: range, step: step)
                .tint(Theme.accent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }
}

/// Плитка выбора со значком (Тема, Стиль вкладок): выбранная — светлее, значок залит.
struct LookTile: View {
    let icon: IconName
    let title: String
    var subtitle: String?
    let selected: Bool
    var width: CGFloat?
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                SonarIcon(icon, filled: selected, size: 28)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
            .padding(.horizontal, 8)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: subtitle == nil ? 96 : 118)
            .background(selected ? Theme.raisedHigh : Theme.raised.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selected ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(Motion.spring, value: selected)
    }
}

/// Вариант в листе выбора.
struct LookChoice: Identifiable {
    let id: String
    let title: String
    var subtitle: String?
    let icon: IconName
}

/// Нижний лист выбора (как `OptionSheet` мини-плеера): галочка цветом темы у выбранного. Лист не
/// закрывается сам — видно, как меняется вид; закрывается смахиванием.
struct LookChoiceSheet: View {
    let options: [LookChoice]
    let selected: String
    let pick: @MainActor (String) -> Void

    /// Высота листа под число вариантов.
    static func height(_ count: Int, subtitles: Bool = false) -> CGFloat {
        CGFloat(count) * (subtitles ? 84 : 74) + 70
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(options) { item in
                let on = item.id == selected
                Button {
                    pick(item.id)
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 22) {
                        SonarIcon(item.icon, size: 26).foregroundStyle(Theme.text)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Theme.text)
                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        SonarIcon(.check, size: 26)
                            .foregroundStyle(Theme.accent)
                            .opacity(on ? 1 : 0)
                            .scaleEffect(on ? 1 : 0.5)
                    }
                    .padding(.horizontal, 26)
                    .frame(height: item.subtitle == nil ? 74 : 84)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 34)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(Motion.spring, value: selected)
    }
}

extension View {
    /// Оформление нижнего листа, как у остальных листов Sonar.
    func lookSheet(height: CGFloat) -> some View {
        presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
            .presentationBackground(Theme.background)
    }
}

// MARK: - Стекло

/// Заливка панели по настройкам Вида: «Прозрачность» выключена — плотная поверхность темы; включена —
/// размытие по типу стекла (Ультра — тонкое, Баланс — плотнее, Без размытия — нет) и поверхность с
/// альфой по непрозрачности (`appearance.opacity`, 15–100 %).
struct GlassFill<S: Shape>: View {
    let shape: S
    var tint: Color?
    @Environment(SettingsStore.self) private var settings

    /// Непрозрачность заливки поверх стекла: без «Прозрачности» — 1, иначе по `appearance.opacity`
    /// (с размытием — чуть меньше, его и так видно). Ею же гаснет фон-обложка мини-плеера.
    @MainActor
    static func alpha(_ settings: SettingsStore) -> Double {
        guard settings.bool(LookKey.glass) else { return 1 }
        let type = GlassType(rawValue: settings.string(LookKey.glassType)) ?? .ultra
        let opacity = min(1, max(0.15, settings.number(LookKey.opacity, fallback: 80) / 100))
        return type == .noBlur ? opacity : opacity * 0.78
    }

    var body: some View {
        let glass = settings.bool(LookKey.glass)
        let type = GlassType(rawValue: settings.string(LookKey.glassType)) ?? .ultra
        let color = tint ?? Theme.surface
        ZStack {
            if glass {
                switch type {
                case .ultra: shape.fill(.ultraThinMaterial)
                case .balance: shape.fill(.regularMaterial)
                case .noBlur: EmptyView()
                }
            }
            shape.fill(color.opacity(Self.alpha(settings)))
        }
        .animation(Motion.spring, value: glass)
        .animation(Motion.spring, value: type)
    }
}

// MARK: - Фон приложения

/// Свой фон (`appearance.background = custom`): картинка из галереи, хранится на телефоне
/// (Application Support/Look/backdrop.jpg, сторона до 1600 px). С сервером — `appearance.bg_custom`.
@MainActor
@Observable
final class BackdropStore {
    static let shared = BackdropStore()

    private(set) var image: UIImage?

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Look", directoryHint: .isDirectory).appending(path: "backdrop.jpg")
    }

    init() {
        image = UIImage(contentsOfFile: Self.fileURL.path(percentEncoded: false))
    }

    /// Сохранить картинку (данные из PhotosPicker). false — не картинка или не записалось.
    @discardableResult
    func save(_ data: Data) -> Bool {
        guard let source = UIImage(data: data),
              let jpeg = Self.downscaled(source, maxSide: 1600).jpegData(compressionQuality: 0.82) else { return false }
        do {
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jpeg.write(to: Self.fileURL, options: .atomic)
        } catch {
            return false
        }
        withAnimation(.easeInOut(duration: 0.45)) { image = UIImage(data: jpeg) }
        return true
    }

    func remove() {
        try? FileManager.default.removeItem(at: Self.fileURL)
        withAnimation(.easeInOut(duration: 0.45)) { image = nil }
    }

    static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let k = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * k).rounded(), height: (size.height * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

extension View {
    /// Фон экрана — фон приложения по Виду (`AppBackdrop`), непрозрачный: у каждой страницы стека свой,
    /// поэтому переходы «вперёд / назад» чистые, без просвечивания соседней страницы.
    func pageBackground() -> some View {
        background { AppBackdrop().ignoresSafeArea() }
    }
}

/// Фон под экранами (`appearance.background`): цвет темы; мягкое свечение цвета обложки сверху;
/// сама обложка, размытая и затемнённая; или своя картинка с затемнением. Затемнение и размытие —
/// `appearance.bg_dim` / `appearance.bg_blur`. Смена — плавно.
struct AppBackdrop: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        let mode = BackdropMode(rawValue: settings.string(LookKey.background)) ?? .coverColor
        let dim = min(0.9, max(0, settings.number(LookKey.bgDim, fallback: 0) / 100))
        let blur = min(40, max(0, settings.number(LookKey.bgBlur, fallback: 0)))
        let cover = engine.current?.coverURL
        ZStack {
            Theme.background
            switch mode {
            case .standard:
                EmptyView()
            case .coverColor:
                LinearGradient(colors: [Theme.glow.opacity(ThemeStore.shared.isMono ? 0.1 : 0.24),
                                        Theme.glow.opacity(0.05), .clear],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
                    .transition(.opacity)
            case .cover:
                if let cover {
                    picture(CoverImage(url: cover, cornerRadius: 0), blur: 34 + blur, scrim: 0.5, dim: dim)
                        .id(cover)
                        .transition(.opacity)
                }
            case .custom:
                if let image = BackdropStore.shared.image {
                    picture(Image(uiImage: image).resizable().scaledToFill(), blur: blur, scrim: 0.32, dim: dim)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.45), value: mode)
        .animation(.easeInOut(duration: 0.6), value: cover)
        .accessibilityHidden(true)
    }

    /// Картинка во весь экран: размытие без прозрачных краёв, затемнение (в светлой теме — осветление)
    /// базовое + своё, снизу гуще — под мини-плеер и панель.
    private func picture(_ content: some View, blur: Double, scrim: Double, dim: Double) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .blur(radius: blur, opaque: true)
                .overlay(Theme.scrim.opacity(scrim + (1 - scrim) * dim))
                .overlay(LinearGradient(colors: [.clear, Theme.background.opacity(0.55)],
                                        startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom))
        }
    }
}
