import SwiftUI
import UIKit

// Общие детали экранов Профиль → Плеер (Аудио, Вид плеера, Очередь, Жесты) — в том же виде, что
// «Мини-плеер» (`MiniPlayerSettingsView`): круглая «Назад» и название в капсуле, карточки поверхности 2,
// строки с подписью значения, выбор — нижним листом с галочкой цветом темы. Значки — MingCute.

/// Страница настроек: шапка, прокрутка, карточки проявляются каскадом.
struct PlayerSettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
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
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Карточка с заголовком сверху и пояснением снизу.
struct PlayerCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 6)
            }
            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, 6)
            .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }
}

/// Тумблер: значок, название, пояснение.
struct PlayerToggleRow: View {
    let icon: IconName
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { value in
            withAnimation(Motion.spring) { isOn = value }
            Haptics.select()
        })) {
            HStack(spacing: 16) {
                SonarIcon(icon, filled: isOn, size: 24)
                    .foregroundStyle(isOn ? Theme.accent : Theme.textSecondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// Строка-выбор: название и текущее значение, справа значок значения; тап — лист выбора.
struct PlayerPickRow: View {
    let title: String
    let value: String
    let icon: IconName
    var enabled = true
    let action: @MainActor () -> Void

    var body: some View {
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
                SonarIcon(icon, size: 26)
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 22)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Вариант для листа и плиток.
struct ChoiceItem: Identifiable, Equatable {
    let id: String
    let icon: IconName
    let title: String
    var subtitle: String?
}

extension PlayerChoice {
    var item: ChoiceItem { ChoiceItem(id: rawValue, icon: icon, title: title) }
}

/// Нижний лист выбора одного значения (как `OptionSheet` мини-плеера): у выбранного — галочка.
struct ChoiceSheet: View {
    var title: String?
    let items: [ChoiceItem]
    let selected: String
    let pick: @MainActor (String) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Высота листа под число пунктов.
    static func height(_ count: Int, title: Bool = true, subtitles: Bool = false) -> CGFloat {
        CGFloat(count) * (subtitles ? 84 : 74) + (title ? 110 : 70)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 8)
            }
            VStack(spacing: 0) {
                ForEach(items) { item in
                    row(item)
                }
            }
            .padding(.vertical, 8)
            .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 30)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(Motion.spring, value: selected)
    }

    private func row(_ item: ChoiceItem) -> some View {
        let on = item.id == selected
        return Button {
            pick(item.id)
            Haptics.select()
            // выбор видно (галочка) — и лист уходит сам
            Task {
                try? await Task.sleep(for: .milliseconds(220))
                dismiss()
            }
        } label: {
            HStack(spacing: 22) {
                SonarIcon(item.icon, filled: on, size: 26)
                    .foregroundStyle(on ? Theme.accent : Theme.text)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.text)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                SonarIcon(.check, size: 26)
                    .foregroundStyle(Theme.accent)
                    .opacity(on ? 1 : 0)
                    .scaleEffect(on ? 1 : 0.5)
            }
            .padding(.horizontal, 24)
            .frame(minHeight: item.subtitle == nil ? 74 : 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

extension View {
    /// Лист выбора в общем виде.
    func choiceSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, height: @escaping (Item) -> CGFloat,
                                                      @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        sheet(item: item) { value in
            content(value)
                .presentationDetents([.height(height(value))])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
    }
}

/// Плитки вариантов в ряд (стиль плеера, качество): выбранная — светлее, значок заполнен.
struct ChoiceTiles: View {
    let items: [ChoiceItem]
    let selected: String
    var height: CGFloat = 100
    let pick: @MainActor (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                let on = item.id == selected
                Button {
                    pick(item.id)
                    Haptics.select()
                } label: {
                    VStack(spacing: 8) {
                        SonarIcon(item.icon, filled: on, size: 28)
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .foregroundStyle(on ? Theme.text : Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(on ? Theme.raisedHigh : Theme.raised.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(on ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1.5))
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(Motion.spring, value: selected)
    }
}

/// Тонкий разделитель внутри карточки.
struct PlayerRowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 22)
    }
}
