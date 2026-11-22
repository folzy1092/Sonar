import SwiftUI

/// Повтор и перемешивание в плеере (docs/POLISH_PROMPT.md п. 5, как ПК `player/repeat-ui.ts`):
/// выкл — значок `textSecondary`; вкл — значок акцента и точка 4 pt под ним (без кружка-подложки).
/// Подписи для VoiceOver — те же строки, что подсказки на ПК: «Повтор: выкл / всё / один трек».
enum RepeatUI {
    static func icon(_ mode: RepeatMode) -> IconName {
        mode == .one ? .repeatOne : .repeatAll
    }

    /// Русский ключ подписи — переводится через `t()`.
    static func labelKey(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: "Повтор: выкл"
        case .all: "Повтор: всё"
        case .one: "Повтор: один трек"
        }
    }

    static func shuffleKey(_ on: Bool) -> String {
        on ? "Перемешивание: вкл" : "Перемешивание: выкл"
    }

    /// «Повтор: всё» → «всё» — значение для `accessibilityValue` (имя кнопки — отдельно).
    static func value(of label: String) -> String {
        guard let range = label.range(of: ": ") else { return label }
        return String(label[range.upperBound...])
    }
}

/// Значок-переключатель: смена состояния — масштаб 0.9 → 1 и плавный цвет; «Уменьшение движения» — только цвет.
struct PlayerToggleIcon: View {
    let icon: IconName
    let active: Bool
    /// Меняется при каждой смене состояния (у повтора их три) — запускает «отскок».
    let stateKey: String
    var size: CGFloat = 26

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let dot: CGFloat = 4
    private static let pad: CGFloat = 18

    var body: some View {
        SonarIcon(icon, size: size)
            .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? "" : stateKey) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(0.9)
                    SpringKeyframe(1.0, duration: 0.22)
                }
            }
            .frame(width: size + Self.pad, height: size + Self.pad)
            // без полупрозрачного кружка под значком — только цвет и точка (просьба владельца 2026-11-22)
            .overlay(alignment: .bottom) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: Self.dot, height: Self.dot)
                    .scaleEffect(active || reduceMotion ? 1 : 0.4)
                    .opacity(active ? 1 : 0)
                    .offset(y: Self.dot + 2)
            }
            .animation(Motion.quick, value: active)
            .contentTransition(.opacity)
    }
}
