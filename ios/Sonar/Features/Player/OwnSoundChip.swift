import SwiftUI

/// Плашка «Свой звук · x0.85 · Reverb» у названия играющего трека со своим звуком («Для этого трека»,
/// решение владельца 2026-11-22: точку на кнопке скорости не замечали). Как ПК `player/OwnSoundChip.svelte`:
/// цвет темы, мелко, в стиле плашки качества. Тап — лист скорости. Появление и уход — пружиной, при
/// «Уменьшении движения» — только прозрачность.
struct OwnSoundChip: View {
    /// Что отличается от обычного звука (`TrackSound.ownParts`).
    let parts: [String]
    /// Мини-плеер: без слов «Свой звук», только отличия (или один значок).
    var short = false
    let action: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var label: String {
        (short ? parts : [t("Свой звук")] + parts).joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                SonarIcon(.sliders, size: 11)
                if !label.isEmpty {
                    Text(label)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.accent.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1))
            .fixedSize()
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
        .accessibilityLabel(([t("Свой звук трека")] + parts).joined(separator: ", "))
    }
}
