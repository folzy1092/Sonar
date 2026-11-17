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

/// Профиль → Мини-плеер (`IMG_6780`): живой мини-плеер сверху, ниже — «Прогресс» с листом выбора.
struct MiniPlayerSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var showProgress = false

    private var chosen: Set<ProgressIndicator> { ProgressIndicator.parse(settings.string(ProgressIndicator.key)) }

    private var summary: String {
        let list = ProgressIndicator.allCases.filter(chosen.contains).map(\.title)
        return list.isEmpty ? "Нет" : list.joined(separator: ", ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("Так он выглядит")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 6)
                    if engine.current != nil {
                        MiniPlayer { }
                            .frame(height: BottomChrome.miniHeight)
                            .background(MiniPlayerSurface())
                    } else {
                        HintCard(icon: .play, text: "Включи любой трек — здесь появится живой мини-плеер")
                    }
                }

                SettingsSection(title: "Прогресс") {
                    Button { showProgress = true } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Индикатор прогресса")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Theme.text)
                                Text(summary)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.textSecondary)
                                    .contentTransition(.opacity)
                            }
                            Spacer()
                            SonarIcon(.chevronRight, size: 20).foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.spring, value: summary)
        .sheet(isPresented: $showProgress) {
            ProgressIndicatorSheet()
                .presentationDetents([.height(400)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
    }
}

/// Лист выбора: «Нет» и три вида, у выбранных — галочка цветом темы.
struct ProgressIndicatorSheet: View {
    @Environment(SettingsStore.self) private var settings

    private var chosen: Set<ProgressIndicator> { ProgressIndicator.parse(settings.string(ProgressIndicator.key)) }

    var body: some View {
        VStack(spacing: 0) {
            row(icon: .eyeClosed, title: "Нет", on: chosen.isEmpty) {
                settings.set(ProgressIndicator.key, .string("none"))
            }
            ForEach(ProgressIndicator.allCases) { item in
                row(icon: item.icon, title: item.title, on: chosen.contains(item)) {
                    var next = chosen
                    if next.contains(item) { next.remove(item) } else { next.insert(item) }
                    settings.set(ProgressIndicator.key, .string(ProgressIndicator.encode(next)))
                }
            }
        }
        .padding(.vertical, 8)
        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 34)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(Motion.spring, value: chosen)
    }

    private func row(icon: IconName, title: String, on: Bool, action: @escaping @MainActor () -> Void) -> some View {
        Button {
            action()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
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
