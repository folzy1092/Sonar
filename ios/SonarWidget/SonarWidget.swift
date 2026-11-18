import AppIntents
import SwiftUI
import WidgetKit

// Виджеты Sonar на экране «Домой». Без App Groups (их не даёт сторонняя подпись) виджет не видит данных
// приложения — поэтому он статичный: знак Sonar и кнопки, которые открывают приложение ссылкой
// `sonar://play/liked|wave|quick` (`App/DeepLink.swift`). Строго чёрно-белый, как знак (brand/README.md).
// Значки — те же MingCute-пути, что в приложении (`IconShape.swift`, `IconPaths.swift` — общие файлы).
// Пункт управления и экран блокировки (iOS 18): кнопка и значки «Моя волна» — внизу файла. Всё живёт в
// одном расширении SonarWidget.appex — его подписывает та же пара, что и приложение (ios.yml, BundlePreparer).

@main
struct SonarWidgets: WidgetBundle {
    var body: some Widget {
        SonarButtonsWidget()
        SonarQuickWidget()
        SonarLockWidget()
        SonarWaveControl()
    }
}

extension PlayTarget {
    var icon: IconName {
        switch self {
        case .liked: .heart
        case .wave: .wave
        case .quick: .bolt
        }
    }

    /// Подпись по языку системы: ключ — русский `title`, перевод — `en.lproj` / `uk.lproj` этого расширения
    /// (словари `t()` приложения виджету недоступны).
    var label: LocalizedStringKey {
        LocalizedStringKey(title)
    }
}

/// Значок MingCute цветом переднего плана.
private struct WidgetIcon: View {
    let name: IconName
    var size: CGFloat = 22

    var body: some View {
        IconShape(name: name, filled: true)
            .fill(style: FillStyle(eoFill: name.source.evenOdd))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Шапка: знак и название.
private struct WidgetHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            LogoMark(size: 18)
            Text("Sonar")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
    }
}

private extension View {
    func sonarBackground() -> some View {
        containerBackground(for: .widget) {
            LinearGradient(colors: [Color(white: 0.09), .black], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Средний: три кнопки

struct StaticEntry: TimelineEntry {
    let date: Date
}

struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticEntry {
        StaticEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (StaticEntry) -> Void) {
        completion(StaticEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StaticEntry>) -> Void) {
        // данных нет — перерисовывать незачем
        completion(Timeline(entries: [StaticEntry(date: .now)], policy: .never))
    }
}

private struct ButtonsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader()
            HStack(spacing: 8) {
                ForEach([PlayTarget.liked, .wave, .quick], id: \.self) { target in
                    Link(destination: target.url) {
                        VStack(alignment: .leading, spacing: 0) {
                            WidgetIcon(name: target.icon, size: 24)
                            Spacer(minLength: 6)
                            Text(target.label)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundStyle(.white)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color.white.opacity(target == .wave ? 0.16 : 0.09),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .sonarBackground()
    }
}

struct SonarButtonsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.folzy.sonar.widget.buttons", provider: StaticProvider()) { _ in
            ButtonsView()
        }
        .configurationDisplayName("Sonar")
        .description("Любимые, «Моя волна» и быстрый плейлист — в одно касание.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Маленький: одна кнопка на выбор

/// Что включает маленький виджет (выбирается в «Изменить виджет»).
enum WidgetTarget: String, AppEnum {
    case wave
    case liked
    case quick

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Что включать" }

    static var caseDisplayRepresentations: [WidgetTarget: DisplayRepresentation] {
        [
            .wave: "Моя волна",
            .liked: "Любимые",
            .quick: "Быстрый плейлист",
        ]
    }

    var play: PlayTarget {
        switch self {
        case .wave: .wave
        case .liked: .liked
        case .quick: .quick
        }
    }
}

struct QuickWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Кнопка Sonar" }

    @Parameter(title: "Что включать", default: .wave)
    var target: WidgetTarget
}

struct QuickEntry: TimelineEntry {
    let date: Date
    let target: PlayTarget
}

struct QuickProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickEntry {
        QuickEntry(date: .now, target: .wave)
    }

    func snapshot(for configuration: QuickWidgetIntent, in context: Context) async -> QuickEntry {
        QuickEntry(date: .now, target: configuration.target.play)
    }

    func timeline(for configuration: QuickWidgetIntent, in context: Context) async -> Timeline<QuickEntry> {
        Timeline(entries: [QuickEntry(date: .now, target: configuration.target.play)], policy: .never)
    }
}

private struct QuickView: View {
    let target: PlayTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader()
            Spacer(minLength: 8)
            ZStack {
                Circle().fill(Color.white)
                WidgetIcon(name: target.icon, size: 26)
                    .foregroundStyle(.black)
            }
            .frame(width: 48, height: 48)
            Spacer(minLength: 8)
            Text(target.label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(target.url)
        .sonarBackground()
    }
}

struct SonarQuickWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.folzy.sonar.widget.quick", intent: QuickWidgetIntent.self, provider: QuickProvider()) { entry in
            QuickView(target: entry.target)
        }
        .configurationDisplayName("Sonar — кнопка")
        .description("Одно касание — и играет «Моя волна», Любимые или быстрый плейлист.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Экран блокировки: «Моя волна»

/// Значки экрана блокировки: круглый — знак Sonar, прямоугольный — знак и «Моя волна». Касание — та же
/// ссылка, что у кнопки виджета «Домой» (`sonar://play/wave`). Цвет и прозрачность красит система.
private struct LockView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(OpenWaveIntent.target.url)
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                LogoMark(size: 30)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text(OpenWaveIntent.target.label)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .widgetAccentable()
                    Text("Sonar")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        default:
            ZStack {
                AccessoryWidgetBackground()
                LogoMark(size: 30)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(OpenWaveIntent.target.label))
        }
    }
}

struct SonarLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.folzy.sonar.widget.lock-wave", provider: StaticProvider()) { _ in
            LockView()
        }
        .configurationDisplayName("Моя волна")
        .description("Знак Sonar на экране блокировки: касание — и играет «Моя волна».")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Пункт управления: «Моя волна»

/// Кнопка в Пункте управления, на экране блокировки (вместо фонарика и камеры) и на кнопке действия.
/// Значок — знак Sonar своим символом `sonar.mark` (`Assets.xcassets`, `ios/scripts/gen-symbol.mjs`):
/// кнопки Пункта управления показывают только символы, SwiftUI-фигуру туда не поставить.
struct SonarWaveControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.folzy.sonar.widget.wave-control") {
            ControlWidgetButton(action: OpenWaveIntent()) {
                Label("Моя волна", image: "sonar.mark")
            }
        }
        .displayName("Моя волна")
        .description("Открывает Sonar и включает «Мою волну».")
    }
}
