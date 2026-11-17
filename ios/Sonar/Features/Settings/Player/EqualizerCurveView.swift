import SwiftUI

/// Кривая эквалайзера над полосами (как на ПК — видно, как звучит вся кривая сразу): настоящая АЧХ
/// фильтров (`EqualizerCurve`), линия 0 дБ, точки полос; тянутая полоса подсвечена. Смена пресета —
/// кривая плавно перетекает.
struct EqualizerCurveView: View {
    let gains: [Double]
    var active: Int?
    var enabled = true

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let points = EqualizerCurve.points(gains)
            let y: (Double) -> CGFloat = { db in size.height * CGFloat(0.5 - db / (2 * Equalizer.maxDb)) * 0.86 + size.height * 0.07 }
            ZStack {
                // сетка: 0 дБ и ±6
                ForEach([-6.0, 0, 6], id: \.self) { db in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y(db)))
                        path.addLine(to: CGPoint(x: size.width, y: y(db)))
                    }
                    .stroke(Theme.line.opacity(db == 0 ? 1 : 0.5), style: StrokeStyle(lineWidth: 1, dash: db == 0 ? [] : [3, 5]))
                }
                // заливка под кривой до нуля
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y(0)))
                    for point in points {
                        path.addLine(to: CGPoint(x: size.width * CGFloat(point.x), y: y(point.db)))
                    }
                    path.addLine(to: CGPoint(x: size.width, y: y(0)))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Theme.accent.opacity(0.32), Theme.accent.opacity(0.04)],
                                     startPoint: .top, endPoint: .bottom))
                Path { path in
                    for (i, point) in points.enumerated() {
                        let p = CGPoint(x: size.width * CGFloat(point.x), y: y(point.db))
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                // точки полос
                ForEach(Equalizer.frequencies.indices, id: \.self) { i in
                    let gain = i < gains.count ? gains[i] : 0
                    let on = active == i
                    Circle()
                        .fill(on ? Theme.accent : Theme.text)
                        .frame(width: on ? 11 : 6, height: on ? 11 : 6)
                        .position(x: size.width * CGFloat(EqualizerCurve.position(of: Equalizer.frequencies[i])), y: y(gain))
                }
            }
        }
        .frame(height: 120)
        .padding(.horizontal, 6)
        .opacity(enabled ? 1 : 0.4)
        .animation(Motion.spring, value: gains)
        .animation(Motion.quick, value: active)
        .accessibilityHidden(true)
    }
}
