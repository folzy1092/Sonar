import SwiftUI

/// Значок «Dev» у ника разработчика Sonar (как ПК `components/profile/DevBadge.svelte`): капсула цвета
/// акцента с точкой. Появляется из масштаба, точка один раз «пингует» кольцом, как сонар. «Уменьшение
/// движения» — только прозрачность, без пинга. Кто разработчик — `SonarDeep.subscriptionOf`.
struct DevBadge: View {
    /// Кегль, pt.
    var size: CGFloat = 11

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var pinged = false

    private static let pingDelay = 0.25
    private static let pingDuration = 1.1
    private static let pingScale: CGFloat = 3.2

    var body: some View {
        HStack(spacing: size * 0.45) {
            Circle()
                .fill(Theme.accent)
                .frame(width: size * 0.5, height: size * 0.5)
                .overlay {
                    Circle()
                        .strokeBorder(Theme.accent, lineWidth: 1)
                        .scaleEffect(pinged ? Self.pingScale : 1)
                        .opacity(pinged || reduceMotion ? 0 : 0.9)
                }
            Text(verbatim: "Dev")
                .font(.system(size: size, weight: .bold))
                .tracking(size * 0.04)
        }
        .foregroundStyle(Theme.accent)
        .padding(.leading, size * 0.6)
        .padding(.trailing, size * 0.75)
        .frame(height: size * 1.85)
        .background(Theme.accent.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1))
        .fixedSize()
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown || reduceMotion ? 1 : 0.6)
        .onAppear(perform: appear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Разработчик Sonar: открыто всё Sonar Deep"))
    }

    private func appear() {
        withAnimation(Motion.spring) { shown = true }
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: Self.pingDuration).delay(Self.pingDelay)) { pinged = true }
    }
}
