import SwiftUI
import UIKit

/// Как мини-плеер показывает прогресс (`appearance.progress_indicator`, SETTINGS.md): линия внизу,
/// заливка фона, кольцо на обложке — можно несколько сразу; «Нет» снимает всё. Хранится строкой через
/// запятую (`ring`, `line,ring`, `none`), пусто — умолчание `ring`.
enum ProgressIndicator: String, CaseIterable, Identifiable {
    case line, fill, ring

    static let key = "appearance.progress_indicator"
    static let fallback: Set<ProgressIndicator> = [.ring]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: "Линия внизу"
        case .fill: "Заливка фона"
        case .ring: "Кольцо на обложке"
        }
    }

    var icon: IconName {
        switch self {
        case .line: .dash
        case .fill: .square
        case .ring: .refresh
        }
    }

    static func parse(_ raw: String) -> Set<ProgressIndicator> {
        if raw.isEmpty { return fallback }
        if raw == "none" { return [] }
        return Set(raw.split(separator: ",").compactMap { ProgressIndicator(rawValue: String($0)) })
    }

    static func encode(_ set: Set<ProgressIndicator>) -> String {
        set.isEmpty ? "none" : allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
    }
}

/// Профиль → Мини-плеер (`IMG_6780..6784`): живой мини-плеер, заготовки Капсула / Обложка / Тихий /
/// Лента и пункты Фон, Индикаторы прогресса, Форма обложки, Скругление границ — у каждого лист
/// выбора. Поменял пункт — вид становится «своим», плитки заготовок гаснут.
struct MiniPlayerSettingsView: View {
    enum Option: String, Identifiable {
        case background, progress, cover, corners
        var id: String { rawValue }
    }

    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var picker: Option?

    private var style: MiniStyle { MiniStyle.current(settings) }

    private var progressSummary: String {
        let list = ProgressIndicator.allCases.filter(style.progress.contains).map(\.title)
        return list.isEmpty ? "Нет" : list.joined(separator: ", ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    CircleButton(icon: .back, label: "Назад") { dismiss() }
                    Text("Мини-плеер")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.raised.opacity(0.92), in: Capsule())
                }
                .padding(.top, 8)

                if engine.current != nil {
                    MiniPlayer { }
                        .frame(height: BottomChrome.miniHeight)
                        .background(MiniPlayerSurface(height: BottomChrome.miniHeight))
                        .padding(.top, 6)
                } else {
                    HintCard(icon: .play, text: "Включи любой трек — здесь появится живой мини-плеер")
                }

                presets

                VStack(spacing: 0) {
                    row("Фон", style.background.title, icon: style.background.icon) { picker = .background }
                    row("Индикаторы прогресса", progressSummary, icon: .wave) { picker = .progress }
                    row("Форма обложки", style.cover.title, icon: style.cover.icon) { picker = .cover }
                    row("Скругление границ", style.corners.title, icon: style.corners.icon) { picker = .corners }
                }
                .padding(.vertical, 6)
                .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.spring, value: style)
        .sheet(item: $picker) { kind in
            OptionSheet(kind: kind)
                .presentationDetents([.height(kind == .progress || kind == .corners ? 400 : 330)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
    }

    /// Четыре плитки заготовок — листаются вбок, выбранная подъезжает в поле зрения.
    private var presets: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                presetTiles
                    .padding(.horizontal, Theme.gutter)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Theme.gutter)
            .onAppear { proxy.scrollTo(style.preset, anchor: .center) }
            .onChange(of: style.preset) { _, preset in
                withAnimation(Motion.spring) { proxy.scrollTo(preset, anchor: .center) }
            }
        }
    }

    private var presetTiles: some View {
        HStack(spacing: 10) {
            ForEach(MiniStyle.Preset.shown) { preset in
                let on = style.preset == preset
                Button {
                    MiniStyle.presets[preset]?.save(settings)
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 10) {
                        SonarIcon(preset.icon, filled: on, size: 30)
                        Text(preset.title)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? Theme.text : Theme.textSecondary)
                    .frame(width: 124, height: 100)
                    .background(on ? Theme.raisedHigh : Theme.raised.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .accessibilityAddTraits(on ? .isSelected : [])
                .id(preset)
            }
        }
    }

    private func row(_ title: String, _ value: String, icon: IconName, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
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
            .frame(height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
    }
}

/// Лист выбора пункта: у выбранного — галочка цветом темы. Прогресс — можно несколько, «Нет» снимает всё;
/// остальное — одно значение.
struct OptionSheet: View {
    let kind: MiniPlayerSettingsView.Option
    @Environment(SettingsStore.self) private var settings

    private var style: MiniStyle { MiniStyle.current(settings) }

    var body: some View {
        VStack(spacing: 0) {
            switch kind {
            case .background:
                ForEach(MiniStyle.Background.allCases) { item in
                    row(icon: item.icon, title: item.title, on: style.background == item) { change { $0.background = item } }
                }
            case .progress:
                row(icon: .eyeClosed, title: "Нет", on: style.progress.isEmpty) { change { $0.progress = [] } }
                ForEach(ProgressIndicator.allCases) { item in
                    row(icon: item.icon, title: item.title, on: style.progress.contains(item)) {
                        change { style in
                            if style.progress.contains(item) { style.progress.remove(item) } else { style.progress.insert(item) }
                        }
                    }
                }
            case .cover:
                ForEach(MiniStyle.CoverShape.allCases) { item in
                    row(icon: item.icon, title: item.title, on: style.cover == item) { change { $0.cover = item } }
                }
            case .corners:
                ForEach(MiniStyle.Corners.allCases) { item in
                    row(icon: item.icon, title: item.title, on: style.corners == item) { change { $0.corners = item } }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 34)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(Motion.spring, value: style)
    }

    private func change(_ edit: (inout MiniStyle) -> Void) {
        var next = style
        edit(&next)
        next.save(settings)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func row(icon: IconName, title: String, on: Bool, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 26) {
                SonarIcon(icon, size: 26).foregroundStyle(Theme.text)
                    .frame(width: 34)
                Text(title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                SonarIcon(.check, size: 26)
                    .foregroundStyle(Theme.accent)
                    .opacity(on ? 1 : 0)
                    .scaleEffect(on ? 1 : 0.5)
            }
            .padding(.horizontal, 26)
            .frame(height: 74)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}
