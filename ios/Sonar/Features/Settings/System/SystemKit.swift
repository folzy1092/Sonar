import SwiftUI
import UIKit

// Общие куски экранов Аккаунта, Интеграций и Системы (Статистика, Общее, Хранилище, «с сервером»):
// шапка и строки на значках Sonar (MingCute), без SF Symbols. Вид — как
// `MiniPlayerSettingsView` и `SettingsKit`: круглая «Назад», название в капсуле, стеклянные карточки.

/// Экран: шапка, прокрутка (таб-бар сворачивается), отступ снизу под мини-плеер.
struct SystemScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(ChromeState.self) private var chrome
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CircleButton(icon: .back, label: t("навигация::Назад")) { dismiss() }
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.raised.opacity(0.92), in: Capsule())
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
                .padding(.bottom, 170)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                chrome.scrolled(to: offset)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Раздел: серый заголовок, карточка, подпись снизу.
struct SystemSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.line))
            if let footer {
                Text(footer)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// Строка: значок, название и пояснение, справа значение и шеврон.
struct SystemRow: View {
    var icon: IconName?
    let title: String
    var subtitle: String?
    var value: String?
    var chevron = false
    var tint: Color?

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                SonarIcon(icon, size: 22)
                    .foregroundStyle(tint ?? Theme.textSecondary)
                    .frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint ?? Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            if chevron {
                SonarIcon(.chevronRight, size: 16)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

/// Строка-кнопка («Очистить», ссылка).
struct SystemButtonRow: View {
    var icon: IconName?
    let title: String
    var subtitle: String?
    var value: String?
    var tint: Color?
    var enabled = true
    var chevron = false
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            SystemRow(icon: icon, title: title, subtitle: subtitle, value: value, chevron: chevron, tint: tint)
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Тумблер со значком.
struct SystemToggle: View {
    var icon: IconName?
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { isOn = $0; Haptics.tap() }).animation(Motion.spring)) {
            HStack(spacing: 14) {
                if let icon {
                    SonarIcon(icon, filled: isOn, size: 22)
                        .foregroundStyle(isOn ? Theme.accent : Theme.textSecondary)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// Выбор из нескольких — капсула с переезжающей подсветкой.
struct SystemSegments<ID: Hashable>: View {
    struct Option: Identifiable {
        let id: ID
        let title: String
    }

    let options: [Option]
    @Binding var selection: ID
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let on = option.id == selection
                Button {
                    guard !on else { return }
                    withAnimation(Motion.spring) { selection = option.id }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(option.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(on ? Theme.accentInk : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if on {
                                Capsule()
                                    .fill(Theme.accent)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.raised.opacity(0.6), in: Capsule())
    }
}

/// Пункт со значением и выбором под ним (Платформа, Добавление).
struct SystemChoiceRow<ID: Hashable>: View {
    var icon: IconName?
    let title: String
    var subtitle: String?
    let options: [SystemSegments<ID>.Option]
    @Binding var selection: ID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SystemRow(icon: icon, title: title, subtitle: subtitle)
                .padding(.bottom, -12)
            SystemSegments(options: options, selection: $selection)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }
}

/// Число со счётом: при появлении бежит от нуля, при смене — перелистывается.
struct CountUpText: View {
    let value: Int
    var size: CGFloat = 30
    var weight: Font.Weight = .bold
    var prefix = ""
    var suffix = ""
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(verbatim: "\(prefix)\(shown.formatted())\(suffix)")
            .font(.system(size: size, weight: weight, design: .rounded).monospacedDigit())
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear {
                if reduceMotion { shown = value } else { withAnimation(.spring(response: 0.9, dampingFraction: 0.9)) { shown = value } }
            }
            .onChange(of: value) { _, next in
                withAnimation(Motion.spring) { shown = next }
            }
    }
}

/// Значок в цветной плашке — шапки экранов и пустые состояния.
struct SystemBadgeIcon: View {
    let icon: IconName
    var size: CGFloat = 52
    var tint: Color?

    var body: some View {
        SonarIcon(icon, filled: true, size: size * 0.48)
            .foregroundStyle(tint == nil ? Theme.accentInk : Color.white)
            .frame(width: size, height: size)
            .background(tint ?? Theme.accent, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Размер в байтах для людей: «512 КБ», «3.4 МБ», «1.2 ГБ».
@MainActor
func bytesText(_ bytes: Int64) -> String {
    let kb = Double(bytes) / 1024
    if kb < 1024 { return t("{n} КБ", ["n": String(max(bytes > 0 ? 1 : 0, Int(kb.rounded())))]) }
    let mb = kb / 1024
    if mb < 1024 { return t("{n} МБ", ["n": mb < 10 ? String(format: "%.1f", mb) : String(Int(mb.rounded()))]) }
    return t("{n} ГБ", ["n": String(format: "%.1f", mb / 1024)])
}
