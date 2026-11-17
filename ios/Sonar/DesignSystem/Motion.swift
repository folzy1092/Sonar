import SwiftUI

/// Общие приёмы анимации (PLATFORMS.md «Анимации»): 140–450 мс, пружина; появляется снизу и из 0.98 с
/// прозрачностью. «Уменьшение движения» или `appearance.animations = false` — только прозрачность.
enum Motion {
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let quick = Animation.easeOut(duration: 0.18)
    static let progress = Animation.easeInOut(duration: 0.35)
}

/// Каскад: элементы списка проявляются по очереди с небольшим подъёмом.
struct Cascade: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .scaleEffect(shown || reduceMotion ? 1 : 0.98, anchor: .top)
            .onAppear {
                withAnimation(Motion.spring.delay(Double(min(index, 12)) * 0.035)) { shown = true }
            }
    }
}

extension View {
    func cascade(_ index: Int) -> some View {
        modifier(Cascade(index: index))
    }
}

/// Нажатие — лёгкое сжатие и подсветка.
/// Нажатие + лёгкий тактильный отклик (`Haptics`, выключается в Общем). Строки треков — без отклика
/// (`haptic: false`): их много, тык на каждую прокрутку раздражает.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var haptic = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed, haptic { Haptics.tap() }
            }
    }
}
