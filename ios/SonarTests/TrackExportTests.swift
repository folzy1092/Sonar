import XCTest
@testable import Sonar

/// Имя файла для «Скачать» в меню трека (`TrackExport.fileName`).
final class TrackExportTests: XCTestCase {
    private func track(_ artist: String, _ title: String) -> Track {
        Track(ref: "sc:1", title: title, artist: artist, artists: [ArtistRef(ref: "sca:1", name: artist)],
              album: nil, durationMs: 1000, coverURL: nil, url: nil, explicit: false, available: true)
    }

    func testArtistDashTitle() {
        XCTAssertEqual(TrackExport.fileName(track("Kai Angel", "andy warhol"), ext: "mp3"), "Kai Angel — andy warhol.mp3")
    }

    func testBannedCharactersBecomeSpaces() {
        XCTAssertEqual(TrackExport.fileName(track("AC/DC", "What?: \"Live\"\n"), ext: "flac"), "AC DC — What Live.flac")
    }

    func testNoArtistLeadingDotsAndEmpty() {
        XCTAssertEqual(TrackExport.fileName(track("", "..hidden"), ext: "m4a"), "hidden.m4a")
        XCTAssertEqual(TrackExport.fileName(track("", "///"), ext: "mp3"), "Sonar.mp3")
    }

    func testLongNameIsCut() {
        let name = TrackExport.fileName(track("A", String(repeating: "x", count: 300)), ext: "mp3")
        XCTAssertEqual(name.count, 124)
        XCTAssertTrue(name.hasSuffix(".mp3"))
    }

    func testMenuStringsAreTranslated() {
        for key in ["Кешировать", "Кешируется…", "Убрать из кеша", "Убрано из кеша", "Кеширую «{title}»", "Скачать",
                    "В файл на телефон", "Готовлю файл…", "Выбрать, где играет музыка",
                    "Остановить музыку через заданное время", "Включён — нажми, чтобы изменить",
                    "В меню трека и в листе скорости: выключить музыку через время", "Меню текста"] {
            for lang in Lang.allCases where lang != .ru {
                XCTAssertNotEqual(I18n.translate(key, lang: lang), key, "\(key) — \(lang)")
            }
        }
    }
}
