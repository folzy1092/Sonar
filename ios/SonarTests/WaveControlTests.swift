import XCTest
@testable import Sonar

/// «Моя волна» в Пункте управления и на экране блокировки: интент кнопки (`Core/Shortcuts/OpenWaveIntent.swift`)
/// и свой символ знака Sonar (`SonarWidget/Assets.xcassets/sonar.mark.symbolset`, `ios/scripts/gen-symbol.mjs`).
final class WaveControlTests: XCTestCase {
    func testControlOpensWaveLink() {
        XCTAssertEqual(OpenWaveIntent.target, .wave)
        XCTAssertEqual(OpenWaveIntent.target.url.absoluteString, "sonar://play/wave")
        // ссылку разбирает тот же DeepLink, что и у виджета «Домой»
        XCTAssertEqual(DeepLink(OpenWaveIntent.target.url), .play(.wave))
    }

    func testControlOpensAppAndStaysOutOfShortcuts() {
        XCTAssertTrue(OpenWaveIntent.openAppWhenRun)
        XCTAssertFalse(OpenWaveIntent.isDiscoverable)
    }

    func testSonarMarkSymbolTemplate() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SonarWidget/Assets.xcassets/sonar.mark.symbolset/sonar.mark.svg")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "нет исходников рядом с тестами")
        let template = try SymbolTemplate(data: Data(contentsOf: url))

        XCTAssertEqual(template.version, "Template v.3.0")
        for id in ["Capline-S", "Baseline-S", "Capline-M", "Baseline-M", "Capline-L", "Baseline-L", "H-reference"] {
            XCTAssertNotNil(template.guides[id], id)
        }
        let commands = try XCTUnwrap(template.symbols["Regular-S"]).map(\.command)
        XCTAssertFalse(commands.isEmpty)
        for weight in ["Ultralight", "Regular", "Black"] {
            let path = try XCTUnwrap(template.symbols["\(weight)-S"], weight)
            // Xcode выводит остальные начертания из трёх: пути должны совпадать по командам
            XCTAssertEqual(path.map(\.command), commands, weight)
            let left = try XCTUnwrap(template.guides["left-margin-\(weight)-S"]?.first?.numbers.first, weight)
            let right = try XCTUnwrap(template.guides["right-margin-\(weight)-S"]?.first?.numbers.first, weight)
            XCTAssertLessThan(left, right, weight)
            // концы отрезков лежат на самом знаке (контрольные точки кривых могут выходить за поля)
            let points = path.compactMap { segment in
                segment.numbers.count >= 2 ? (segment.numbers[segment.numbers.count - 2], segment.numbers[segment.numbers.count - 1]) : nil
            }
            XCTAssertFalse(points.isEmpty, weight)
            // знак — между полями и около линий прописных (76) и базовой (146) мелкого размера
            for (x, y) in points {
                XCTAssertTrue((left - 1)...(right + 1) ~= x, "\(weight): x \(x) вне полей \(left)…\(right)")
                XCTAssertTrue(56...166 ~= y, "\(weight): y \(y) вне строки")
            }
        }
    }

    /// Подписи виджетов переводятся по языку системы: en и uk с одинаковыми ключами, среди них — названия
    /// целей (`PlayTarget.title`) и интента кнопки.
    func testWidgetStringsTranslated() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SonarWidget")
        let en = root.appendingPathComponent("en.lproj/Localizable.strings")
        let uk = root.appendingPathComponent("uk.lproj/Localizable.strings")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: en.path), "нет исходников рядом с тестами")
        let english = try Self.strings(at: en)
        let ukrainian = try Self.strings(at: uk)

        XCTAssertEqual(Set(english.keys), Set(ukrainian.keys))
        var required = PlayTarget.allCases.map(\.title)
        required += ["Открыть «Мою волну»", "Открывает Sonar и включает «Мою волну»."]
        for key in required {
            XCTAssertFalse(english[key, default: ""].isEmpty, key)
            XCTAssertFalse(ukrainian[key, default: ""].isEmpty, key)
        }
    }

    private static func strings(at url: URL) throws -> [String: String] {
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try XCTUnwrap(plist as? [String: String], url.lastPathComponent)
    }
}

/// Шаблон своего символа (SF Symbols v3.0) — то, что проверяет Xcode: направляющие и пути начертаний.
private struct SymbolTemplate {
    struct Segment: Equatable {
        let command: Character
        let numbers: [Double]
    }

    var version = ""
    var guides: [String: [Segment]] = [:]
    var symbols: [String: [Segment]] = [:]

    init(data: Data) throws {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else {
            throw parser.parserError ?? CocoaError(.fileReadCorruptFile)
        }
        version = reader.version.trimmingCharacters(in: .whitespacesAndNewlines)
        guides = reader.guides.mapValues(Self.segments)
        symbols = reader.symbols.mapValues(Self.segments)
    }

    /// `M x y C … Z` — команды и числа через пробел (так пишет gen-symbol.mjs).
    static func segments(_ d: String) -> [Segment] {
        var out: [Segment] = []
        var command: Character?
        var numbers: [Double] = []
        for token in d.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }) {
            if let value = Double(token) {
                numbers.append(value)
            } else if let first = token.first, token.count == 1 {
                if let command { out.append(Segment(command: command, numbers: numbers)) }
                command = first
                numbers = []
            }
        }
        if let command { out.append(Segment(command: command, numbers: numbers)) }
        return out
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var version = ""
        var guides: [String: String] = [:]
        var symbols: [String: String] = [:]
        private var groups: [String] = []
        private var readingVersion = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let id = attributes["id"] ?? ""
            switch name {
            case "g":
                groups.append(id)
            case "text":
                readingVersion = id == "template-version"
            case "path":
                let d = attributes["d"] ?? ""
                if groups.last == "Guides" {
                    guides[id] = d
                } else if groups.dropLast().last == "Symbols", let variant = groups.last {
                    symbols[variant, default: ""] += " " + d
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "g" { groups.removeLast() }
            if name == "text" { readingVersion = false }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if readingVersion { version += string }
        }
    }
}
