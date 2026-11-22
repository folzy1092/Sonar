import SwiftUI
import UIKit

/// «Барабан», как на ПК (`windows/src/components/Ruler.svelte`): лента делений едет под неподвижной меткой по
/// центру. Тянешь вбок — значение меняется шагом `step` (лента едет за пальцем), двойной тап — к `reset`.
/// Мелкое деление — каждый шаг, среднее — каждые `medium` шагов (на нём лёгкая вибрация), длинное с подписью —
/// каждые `major`. Края ленты растворяются. Сдвиг ленты анимируется вместе со значением, поэтому смена извне
/// (кнопки ±, связанный тон) доезжает плавно.
struct DrumRuler: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    var medium = 10
    var major = 100
    /// Подпись длинного деления (значение на нём).
    var label: (Double) -> String = { _ in "" }
    var reset: Double = 0
    /// Точек ленты на шаг.
    var spacing: CGFloat = 7
    var height: CGFloat = 56
    let onChange: (Double) -> Void

    @State private var dragStart: Double?

    private var lower: Int { Int((range.lowerBound / step).rounded()) }
    private var upper: Int { Int((range.upperBound / step).rounded()) }

    private func snapped(_ v: Double) -> Double {
        let k = (min(range.upperBound, max(range.lowerBound, v)) / step).rounded()
        return k * step
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack {
                DrumTape(position: value / step, lower: lower, upper: upper, resetIndex: Int((reset / step).rounded()),
                         medium: medium, major: major, spacing: spacing, label: { label(Double($0) * step) })
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                                 .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                Capsule()
                    .fill(abs(value - reset) < step / 2 ? Theme.text : Theme.accent)
                    .frame(width: 3, height: height * 0.6)
                    .offset(y: -height * 0.1)
                    .shadow(color: Theme.accent.opacity(abs(value - reset) < step / 2 ? 0 : 0.5), radius: 6)
            }
            .frame(width: w, height: proxy.size.height)
            .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = value }
                        let next = snapped(start - Double(drag.translation.width / spacing) * step)
                        guard abs(next - value) >= step / 2 else { return }
                        let mediumStep = step * Double(medium)
                        if Int((next / mediumStep).rounded(.down)) != Int((value / mediumStep).rounded(.down)) {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        onChange(next)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) {
                withAnimation(Motion.spring) { onChange(reset) }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .frame(height: height)
        .animation(dragStart == nil ? Motion.spring : nil, value: value)
        .accessibilityElement()
        .accessibilityValue(label(value).isEmpty ? String(format: "%g", value) : label(value))
        .accessibilityAdjustableAction { direction in
            onChange(snapped(value + (direction == .increment ? 1 : -1) * step * Double(medium)))
        }
    }
}

/// Сама лента: позиция (в шагах) анимируется — Canvas перерисовывается на каждом кадре пружины.
private struct DrumTape: View, Animatable {
    var position: Double
    let lower: Int
    let upper: Int
    let resetIndex: Int
    let medium: Int
    let major: Int
    let spacing: CGFloat
    let label: (Int) -> String

    nonisolated var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let center = size.width / 2
            let half = Int(center / spacing) + 2
            let middle = Int(position.rounded())
            for k in max(lower, middle - half) ... min(upper, max(lower, middle + half)) {
                let x = center + CGFloat(Double(k) - position) * spacing
                let isMajor = k % major == 0
                let isMedium = k % medium == 0
                let length: CGFloat = isMajor ? 24 : isMedium ? 15 : 8
                let color: Color = k == resetIndex ? Theme.accent : (isMajor || isMedium ? Theme.textSecondary : Theme.textTertiary)
                let rect = CGRect(x: x - (isMajor ? 1 : 0.5), y: size.height / 2 - length / 2 - 6,
                                  width: isMajor ? 2 : 1, height: length)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(isMedium ? 1 : 0.7)))
                if isMajor {
                    let text = label(k)
                    if !text.isEmpty {
                        context.draw(Text(text).font(.system(size: 11, weight: .medium).monospacedDigit())
                                        .foregroundStyle(k == resetIndex ? Theme.accent : Theme.textTertiary),
                                     at: CGPoint(x: x, y: size.height - 8))
                    }
                }
            }
        }
    }
}
