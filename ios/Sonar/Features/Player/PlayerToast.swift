import SwiftUI

/// Сообщение плеера (`engine.message`) капсулой сверху — в полном плеере и в плеере пульта (вне плеера его
/// показывает `Router.say`). Само гаснет: всплывашка резерва — через 4 с, остальное — через 2.6 с
/// (`FallbackNotice.seconds`); тап — сразу. «Меньше движения» — только прозрачность.
struct PlayerToast: ViewModifier {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message = engine.message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.horizontal, 24)
                        .padding(.top, 60)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .onTapGesture { withAnimation(Motion.exit) { engine.message = nil } }
                }
            }
            .animation(Motion.spring, value: engine.message)
            .task(id: engine.message) {
                guard let message = engine.message else { return }
                try? await Task.sleep(for: .seconds(FallbackNotice.seconds(for: message, note: engine.fallbackNote)))
                guard !Task.isCancelled, engine.message == message else { return }
                withAnimation(Motion.exit) { engine.message = nil }
            }
    }
}

extension View {
    func playerToast() -> some View {
        modifier(PlayerToast())
    }
}
