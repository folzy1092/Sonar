import SwiftUI

/// Ползунок прогресса полного плеера в стиле `player.slider` (Профиль → Вид плеера): обычный, тонкий,
/// плавный (с ручкой), волнистый (пройденное — волной, пока играет), волновой (столбики). Перемотка —
/// пальцем по всей высоте; пока тянешь, ползунок толще.
struct PlayerSlider: View {
    let style: SliderStyle
    /// 0…1 — сколько пройдено.
    let fraction: Double
    let playing: Bool
    /// Для «Волнового»: столбики свои у каждого трека.
    var seed = ""
    var scrubbing = false
    let onScrub: @MainActor (Double) -> Void
    let onCommit: @MainActor () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                track(width: width)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in onScrub(max(0, min(1, drag.location.x / max(1, width)))) }
                    .onEnded { _ in onCommit() }
            )
        }
        .frame(height: style == .wave_bars ? 34 : 24)
        .animation(Motion.quick, value: scrubbing)
        .accessibilityElement()
        .accessibilityLabel("Перемотка")
        .accessibilityValue("\(Int(fraction * 100)) %")
    }

    @ViewBuilder
    private func track(width: CGFloat) -> some View {
        let done = width * min(1, max(0, fraction))
        switch style {
        case .normal:
            line(width: width, done: done, height: scrubbing ? 8 : 4)
        case .thin:
            ZStack(alignment: .leading) {
                line(width: width, done: done, height: scrubbing ? 4 : 2)
                knob(size: scrubbing ? 14 : 0, at: done)
            }
        case .smooth:
            ZStack(alignment: .leading) {
                line(width: width, done: done, height: scrubbing ? 8 : 6)
                    .animation(.linear(duration: 0.25), value: fraction)
                knob(size: scrubbing ? 20 : 14, at: done)
                    .animation(.linear(duration: 0.25), value: fraction)
            }
        case .wavy:
            WavyLine(done: done, width: width, playing: playing, thick: scrubbing)
        case .wave_bars:
            bars(width: width)
        }
    }

    private func line(width: CGFloat, done: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.22))
            Capsule().fill(Color.white).frame(width: done)
        }
        .frame(width: width, height: height)
    }

    private func knob(size: CGFloat, at x: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .offset(x: x - size / 2)
    }

    private func bars(width: CGFloat) -> some View {
        let count = 48
        let heights = SliderStyle.bars(count: count, seed: seed)
        return HStack(alignment: .center, spacing: 2) {
            ForEach(0 ..< count, id: \.self) { i in
                let past = (Double(i) + 0.5) / Double(count) <= fraction
                Capsule()
                    .fill(past ? Color.white : Color.white.opacity(0.22))
                    .frame(height: max(4, (scrubbing ? 34 : 28) * heights[i]))
                    .animation(Motion.quick, value: past)
            }
        }
        .frame(width: width)
    }
}

/// «Волнистый»: пройденная часть — синусоида, которая бежит, пока играет; остальное — прямая.
private struct WavyLine: View {
    let done: CGFloat
    let width: CGFloat
    let playing: Bool
    var thick = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing || reduceMotion)) { context in
            let phase = playing && !reduceMotion ? context.date.timeIntervalSinceReferenceDate * 4 : 0
            Canvas { canvas, size in
                let mid = size.height / 2
                let lineWidth: CGFloat = thick ? 4 : 3
                var rest = Path()
                rest.move(to: CGPoint(x: done, y: mid))
                rest.addLine(to: CGPoint(x: size.width, y: mid))
                canvas.stroke(rest, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                guard done > 1 else { return }
                var wave = Path()
                let amplitude: CGFloat = thick ? 4 : 3
                let step: CGFloat = 2
                var x: CGFloat = 0
                wave.move(to: CGPoint(x: 0, y: mid + amplitude * CGFloat(sin(-phase))))
                while x < done {
                    x = min(done, x + step)
                    wave.addLine(to: CGPoint(x: x, y: mid + amplitude * CGFloat(sin(Double(x) / 7 - phase))))
                }
                canvas.stroke(wave, with: .color(.white), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: width)
    }
}
