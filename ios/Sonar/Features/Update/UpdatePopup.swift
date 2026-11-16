import SwiftUI

/// Всплывашка «Доступно обновление» снизу над мини-плеером (как `windows/src/app/UpdatePopup.svelte`):
/// появляется, когда фоновая проверка нашла новую сборку; закрывается только нажатием — «Позже» или
/// «Обновить».
struct UpdatePopup: View {
    let release: UpdateRelease
    var open: @MainActor () -> Void
    @Environment(UpdateChecker.self) private var checker
    @Environment(SelfUpdater.self) private var updater
    @Environment(SigningModel.self) private var signing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Доступно обновление")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Sonar \(release.label)")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    withAnimation(Motion.spring) { checker.dismissPopup() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("Позже")
            }
            let lines = release.changelog.flatMap { $0.lines.map { $0.text } }.prefix(3)
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text("• " + line)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text.opacity(0.8))
                            .lineLimit(2)
                    }
                }
            }
            HStack(spacing: 10) {
                SecondaryButton(title: "Подробнее") { open() }
                PrimaryButton(title: "Обновить") {
                    if signing.isConfigured { updater.start(release) }
                    open()
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.line))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
    }
}
