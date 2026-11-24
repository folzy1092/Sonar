import SwiftUI
import UIKit

/// Интерфейс → Вид → «Значок приложения» (ПК — `pages/settings/AppIconPicker.svelte`): сетка образцов,
/// тап меняет значок на экране «Домой». iOS при этом сама показывает уведомление «Вы сменили значок» —
/// убрать его нельзя. Что выбрано, помнит система (`alternateIconName`); список — `Core/Settings/AppIcon.swift`.
struct AppIconSettingsView: View {
    @State private var current = AppIcon.current(alternateName: UIApplication.shared.alternateIconName)
    @State private var busy = false
    @State private var failed = false

    private var supported: Bool { UIApplication.shared.supportsAlternateIcons }

    var body: some View {
        LookScreen(title: t("Значок приложения")) {
            Text(supported ? t("Меняет значок на экране «Домой». iOS сама покажет уведомление о смене — это нормально")
                : t("На этом устройстве значок сменить нельзя"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 6)
                .cascade(0)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(AppIcon.allCases) { icon in
                    tile(icon)
                }
            }
            .opacity(supported ? 1 : 0.5)
            .disabled(!supported)
            .cascade(1)
        }
        .alert(t("Не получилось сменить значок"), isPresented: $failed) {
            Button(t("Закрыть"), role: .cancel) {}
        }
    }

    private func tile(_ icon: AppIcon) -> some View {
        let on = icon == current
        return Button {
            Task { await select(icon) }
        } label: {
            VStack(spacing: 8) {
                Image(icon.preview)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16.1, style: .continuous))
                    .scaleEffect(on ? 1.04 : 1)
                Text(t(icon.title))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? Theme.text : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 118)
            .background(on ? Theme.raisedHigh : Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(on ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(t(icon.title))
        .accessibilityAddTraits(on ? .isSelected : [])
        .animation(Motion.spring, value: on)
    }

    @MainActor
    private func select(_ icon: AppIcon) async {
        guard icon != current, !busy else { return }
        Haptics.select()
        busy = true
        defer { busy = false }
        do {
            try await UIApplication.shared.setAlternateIconName(icon.alternateName)
            current = icon
        } catch {
            failed = true
        }
    }
}
