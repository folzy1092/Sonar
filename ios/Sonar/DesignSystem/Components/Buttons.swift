import SwiftUI

/// Круглая кнопка верхней панели экранов (назад, поиск, фильтр, ⋮, ✕, ✓) — поверхность 2, как на
/// скринах `IMG_6770..6774`.
struct CircleButton: View {
    let icon: IconName
    var size: CGFloat = 52
    var iconSize: CGFloat = 22
    var filled = false
    var label: String = ""
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            SonarIcon(icon, filled: filled, size: iconSize)
                .foregroundStyle(Theme.text)
                .frame(width: size, height: size)
                .background(Theme.raised.opacity(0.92), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

/// Главная кнопка экрана: широкая капсула цвета темы («▶ Слушать» / «⏸ Пауза»).
struct AccentCapsuleButton: View {
    let icon: IconName
    let title: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SonarIcon(icon, filled: true, size: 24)
                    .contentTransition(.opacity)
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Theme.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.accent, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }
}

/// «Слушать» ⇄ «Пауза» на экране подборки (`Playback/ListenAction.swift`): значки перетекают
/// (прозрачность + масштаб + поворот, как `PlayPause` на ПК), подпись сменяется прозрачностью.
/// «Уменьшение движения» — только прозрачность.
struct ListenCapsuleButton: View {
    let playing: Bool
    let action: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    morphIcon(.play, shown: !playing, angle: 30)
                    morphIcon(.pause, shown: playing, angle: -30)
                }
                .frame(width: 24, height: 24)
                Text(playing ? t("Пауза") : t("Слушать"))
                    .font(.system(size: 18, weight: .semibold))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Theme.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.accent, in: Capsule())
            .contentShape(Capsule())
            .animation(reduceMotion ? Motion.quick : Motion.spring, value: playing)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }

    private func morphIcon(_ icon: IconName, shown: Bool, angle: Double) -> some View {
        SonarIcon(icon, filled: true, size: 24)
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.6)
            .rotationEffect(.degrees(shown || reduceMotion ? 0 : angle))
    }
}

/// Ряд значков в капсуле (листы плейлиста и трека: ♥ + ≡▶ ⤴ / ▶ ⤮ ⤓).
struct IconCapsuleRow: View {
    struct Item: Identifiable {
        let id = UUID()
        let icon: IconName
        var filled = false
        var tint: Color?
        var enabled = true
        let label: String
        let action: @MainActor () -> Void
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button(action: item.action) {
                    SonarIcon(item.icon, filled: item.filled, size: 24)
                        .foregroundStyle(item.tint ?? Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.86))
                .disabled(!item.enabled)
                .opacity(item.enabled ? 1 : 0.35)
                .accessibilityLabel(item.label)
            }
        }
        .background(Theme.raised.opacity(0.7), in: Capsule())
    }
}

/// Пункт меню листа: значок, заголовок, подпись (как `IMG_6773`, `IMG_6774`).
struct SheetMenuRow: View {
    let icon: IconName
    let title: String
    var subtitle: String?
    var tint: Color?
    var enabled = true
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                SonarIcon(icon, size: 22)
                    .foregroundStyle(tint ?? Theme.textSecondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tint ?? Theme.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Плашка-подсказка сверху экрана (ошибка, «Скачано»…), закрывается тапом.
struct Toast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line))
    }
}
