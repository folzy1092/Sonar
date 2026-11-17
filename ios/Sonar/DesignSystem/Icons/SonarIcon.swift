import SwiftUI

/// Иконка цветом переднего плана. `filled` — заливка (выбранная вкладка, лайк); смена — плавная.
struct SonarIcon: View {
    let name: IconName
    var filled = false
    var size: CGFloat = 24

    init(_ name: IconName, filled: Bool = false, size: CGFloat = 24) {
        self.name = name
        self.filled = filled
        self.size = size
    }

    var body: some View {
        ZStack {
            IconShape(name: name, filled: false)
                .fill(style: FillStyle(eoFill: name.source.evenOdd))
                .opacity(filled ? 0 : 1)
                .scaleEffect(filled ? 1.12 : 1)
            IconShape(name: name, filled: true)
                .fill(style: FillStyle(eoFill: name.source.evenOdd))
                .opacity(filled ? 1 : 0)
                .scaleEffect(filled ? 1 : 0.82)
        }
        .frame(width: size, height: size)
        .animation(Motion.spring, value: filled)
        .accessibilityHidden(true)
    }
}
