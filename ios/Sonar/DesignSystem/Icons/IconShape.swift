import SwiftUI

// Фигуры значков без анимаций и темы — файл общий с виджетом (ios/project.yml, цель SonarWidget).

/// Иконки интерфейса — MingCute, как в Windows-клиенте (решение владельца: не SF Symbols). Пути —
/// `IconPaths.swift` из `ios/scripts/gen-icons.mjs`: абсолютные M/L/C/Q/Z, разбираются один раз.
enum IconPaths {
    private static let parsed: [IconName: (line: Path, fill: Path)] = {
        var out: [IconName: (line: Path, fill: Path)] = [:]
        for name in IconName.allCases {
            let source = name.source
            let line = parse(source.line)
            out[name] = (line, source.fill == source.line ? line : parse(source.fill))
        }
        return out
    }()

    static func path(_ name: IconName, filled: Bool) -> Path {
        guard let pair = parsed[name] else { return Path() }
        return filled ? pair.fill : pair.line
    }

    /// Строка вида `M x y L x y C x1 y1 x2 y2 x y Q x1 y1 x y Z` — у каждой команды свои числа.
    static func parse(_ text: String) -> Path {
        let tokens = text.split(separator: " ")
        var path = Path()
        var i = 0
        func number(_ k: Int) -> CGFloat {
            k < tokens.count ? CGFloat(Double(tokens[k]) ?? 0) : 0
        }
        func point(_ k: Int) -> CGPoint { CGPoint(x: number(k), y: number(k + 1)) }
        while i < tokens.count {
            switch tokens[i] {
            case "M":
                path.move(to: point(i + 1)); i += 3
            case "L":
                path.addLine(to: point(i + 1)); i += 3
            case "C":
                path.addCurve(to: point(i + 5), control1: point(i + 1), control2: point(i + 3)); i += 7
            case "Q":
                path.addQuadCurve(to: point(i + 3), control: point(i + 1)); i += 5
            case "Z":
                path.closeSubpath(); i += 1
            default:
                i += 1
            }
        }
        return path
    }
}

/// Иконка как фигура: вписывается по центру в любой прямоугольник.
struct IconShape: Shape {
    let name: IconName
    var filled = false

    func path(in rect: CGRect) -> Path {
        let side = name.source.size
        let scale = min(rect.width, rect.height) / side
        let transform = CGAffineTransform(translationX: rect.midX - side * scale / 2, y: rect.midY - side * scale / 2)
            .scaledBy(x: scale, y: scale)
        return IconPaths.path(name, filled: filled).applying(transform)
    }
}

/// Знак Sonar (brand/logo.svg) цветом переднего плана.
struct LogoMark: View {
    var size: CGFloat = 32

    var body: some View {
        IconShape(name: .logo)
            .fill(style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
            .accessibilityLabel("Sonar")
    }
}
