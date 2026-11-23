import SwiftUI

/// Капсула «Офлайн» над нижней панелью, пока режим включён (`docs/OFFLINE.md` §6): видно, почему
/// половины медиатеки нет. Тап — выключить режим.
struct OfflinePill: View {
    let offline: OfflineMode

    var body: some View {
        Button { withAnimation(Motion.spring) { offline.set(false) } } label: {
            HStack(spacing: 6) {
                SonarIcon(.cloudOff, size: 14)
                Text(t("Офлайн"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(t("Выключить офлайн-режим"))
    }
}

/// «Сеть пропала» с кнопкой включить офлайн-режим (`general.offline_suggest`); закрывается только кликом.
struct OfflineSuggestBanner: View {
    let offline: OfflineMode

    var body: some View {
        HStack(spacing: 12) {
            Text(t("Сеть пропала"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(t("Включить офлайн-режим")) { withAnimation(Motion.spring) { offline.set(true) } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(PressableStyle(scale: 0.95))
            Button { withAnimation(Motion.spring) { offline.dismissSuggestion() } } label: {
                SonarIcon(.close, size: 16)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(t("Закрыть"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line))
    }
}
