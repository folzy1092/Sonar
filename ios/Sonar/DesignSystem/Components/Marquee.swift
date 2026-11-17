import SwiftUI

/// Бегущая строка: не влезает — после паузы плавно едет влево и заходит по кругу (свёрнутый мини-плеер,
/// `IMG_6769`). Влезает — обычный текст. Края растворяются. «Уменьшение движения» — без прокрутки.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 16, weight: .semibold)
    var color: Color = .primary
    /// Скорость, pt/с.
    var speed: Double = 28
    var gap: CGFloat = 36

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var start = Date()

    private var overflows: Bool { textWidth > boxWidth + 1 && boxWidth > 0 }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .overlay(alignment: .leading) {
                if overflows, !reduceMotion {
                    TimelineView(.animation) { context in
                        let cycle = Double(textWidth + gap) / speed
                        let pause = 1.6
                        let t = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle + pause)
                        let shift = t < pause ? 0 : CGFloat((t - pause) / cycle) * (textWidth + gap)
                        HStack(spacing: gap) {
                            label
                            label
                        }
                        .offset(x: -shift)
                    }
                    .frame(width: boxWidth, alignment: .leading)
                    .clipped()
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.06),
                            .init(color: .black, location: 0.9),
                            .init(color: .clear, location: 1),
                        ], startPoint: .leading, endPoint: .trailing)
                    )
                } else {
                    label.frame(width: max(boxWidth, 1), alignment: .leading).clipped()
                }
            }
            .background(alignment: .leading) {
                // ширина текста целиком, без обрезки
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .onChange(of: text) { start = Date() }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}
