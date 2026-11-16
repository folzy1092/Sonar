import SwiftUI

/// Шапка вложенного экрана настроек (`photo_11`): круглая «Назад» слева, название в капсуле.
struct ScreenHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.line))
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .accessibilityLabel("Назад")
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.line))
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 4)
    }
}

/// Экран настроек: своя шапка, прокрутка, отступ снизу под таб-бар и мини-плеер.
struct SettingsScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(ChromeState.self) private var chrome

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: title)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 14)
                .padding(.bottom, 120)
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

/// Раздел: серый заголовок над стеклянной карточкой.
struct SettingsSection<Content: View>: View {
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

/// Строка меню: значок, название, справа значение / бейдж / шеврон.
struct SettingsRowLabel: View {
    var icon: String?
    let title: String
    var value: String?
    var badge = false
    var chevron = true
    var locked = false
    var dimmed = false

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 26)
            }
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            if badge {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 9, height: 9)
                    .transition(.scale.combined(with: .opacity))
            }
            if let value {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            } else if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .opacity(dimmed ? 0.5 : 1)
    }
}

/// Тумблер с подписью (`photo_11`, «Похожие треки»).
struct SettingsToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn.animation(Motion.spring)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Карточка-вариант (`photo_11`, «Трек / Очередь»): значок, название, пояснение. Выбранная — с рамкой
/// акцента; «Скоро» — приглушена.
struct OptionTile: View {
    let icon: String
    let title: String
    var subtitle: String?
    var selected = false
    var soon = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(selected ? Theme.accent : Theme.text)
                    .symbolEffect(.bounce, value: selected)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104)
            .padding(.horizontal, 10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 1.5 : 1)
            )
            .opacity(soon ? 0.45 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(soon)
        .animation(Motion.spring, value: selected)
    }
}

/// Тонкий разделитель внутри карточки.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 16)
    }
}

/// Главная кнопка — капсула цвета темы.
struct PrimaryButton: View {
    let title: String
    var icon: String?
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title).contentTransition(.opacity)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.accentInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.accent, in: Capsule())
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

/// Вторичная кнопка — стеклянная капсула.
struct SecondaryButton: View {
    let title: String
    var icon: String?
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(role == .destructive ? Theme.danger : Theme.text)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Полоса прогресса: доля едет плавно, без доли — бегущий блик.
struct ProgressLine: View {
    let fraction: Double?
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                if let fraction {
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(6, proxy.size.width * min(max(fraction, 0), 1)))
                        .animation(Motion.progress, value: fraction)
                } else {
                    Capsule()
                        .fill(Theme.accent.opacity(0.8))
                        .frame(width: proxy.size.width * 0.3)
                        .offset(x: sweep ? proxy.size.width * 0.7 : 0)
                        .opacity(reduceMotion ? 0.6 : 1)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { sweep = true }
                        }
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }
}
