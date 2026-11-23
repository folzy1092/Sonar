import XCTest
@testable import Sonar

/// Офлайн-режим на iPhone (`docs/OFFLINE.md`): флаг из настроек, сторож сети, фильтры, очередь, плашка, поиск.
@MainActor
final class OfflineTests: XCTestCase {
    override func tearDown() {
        OfflineFlag.set(false)
        super.tearDown()
    }

    private func track(_ ref: String, title: String = "t", artist: String = "a", album: String? = nil) -> Track {
        Track(ref: ref, title: title, artist: artist, artists: [], album: album.map { AlbumRef(ref: "yml:1", title: $0) },
              durationMs: 1, coverURL: nil, url: nil, explicit: false, available: true, plays: nil, tags: nil)
    }

    // MARK: флаг до первого запроса

    func testFlagReadFromSavedSettings() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "offline-tests-\(UUID().uuidString)"))
        XCTAssertFalse(OfflineFlag.read(from: defaults), "первый запуск — выключен")

        defaults.set(try JSONEncoder().encode([OfflineFlag.key: SettingValue.bool(true)]), forKey: "sonar.settings")
        XCTAssertTrue(OfflineFlag.read(from: defaults))

        defaults.set(try JSONEncoder().encode([OfflineFlag.key: SettingValue.bool(false)]), forKey: "sonar.settings")
        XCTAssertFalse(OfflineFlag.read(from: defaults))

        defaults.set(Data("мусор".utf8), forKey: "sonar.settings")
        XCTAssertTrue(OfflineFlag.read(from: defaults), "настройки не читаются — лучше не пустить в сеть")
    }

    func testBlockedCounterResetsOnTurnOff() {
        OfflineFlag.set(true)
        OfflineFlag.noteBlocked()
        OfflineFlag.noteBlocked()
        XCTAssertEqual(OfflineFlag.blocked, 2)
        OfflineFlag.set(false)
        XCTAssertEqual(OfflineFlag.blocked, 0)
    }

    // MARK: сторож

    func testGuardTakesOnlyWebRequestsWhenOn() throws {
        let web = URLRequest(url: try XCTUnwrap(URL(string: "https://api.soundcloud.com/tracks")))
        let file = URLRequest(url: URL(fileURLWithPath: "/tmp/a.mp3"))
        XCTAssertFalse(OfflineGuard.canInit(with: web))
        OfflineFlag.set(true)
        XCTAssertTrue(OfflineGuard.canInit(with: web))
        XCTAssertFalse(OfflineGuard.canInit(with: file))
    }

    func testNetConfigurationPutsGuardFirst() {
        let classes = Net.configuration(.ephemeral).protocolClasses ?? []
        XCTAssertTrue(classes.first == OfflineGuard.self)
    }

    /// Своя `URLSession` мимо `Net.configuration` — дыра в «ни байта в сеть».
    func testEverySessionUsesNetConfiguration() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sonar")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.path), "нет исходников рядом с тестами")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.contains("URLSession(configuration:") {
                // конфигурация — из Net.configuration в этой же строке или чуть выше
                let window = lines[max(0, index - 6)...index].joined(separator: "\n")
                if !window.contains("Net.configuration") {
                    offenders.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        XCTAssertEqual(offenders, [], "своя URLSession без Net.configuration")
    }

    // MARK: фильтры и подписи

    func testFilterKeepsOnlyAvailable() {
        let filter = OfflineFilter { $0 != "ym:2" }
        let list = [track("ym:1"), track("ym:2"), track("ym:3")]
        XCTAssertEqual(filter.tracks(list).map(\.ref), ["ym:1", "ym:3"])
        XCTAssertEqual(filter.count(list), 2)
    }

    func testCountText() {
        XCTAssertEqual(OfflineFilter.countText(available: 3, total: 3), tracksCount(3))
        let partial = OfflineFilter.countText(available: 12, total: 40)
        XCTAssertTrue(partial.contains("12") && partial.contains("40"), partial)
    }

    // MARK: очередь

    func testPruneKeepsCurrentInPlace() {
        // доступны чётные; текущий (5) недоступен, но остаётся
        let result = OfflineQueue.prune(order: [0, 1, 2, 5, 3, 4], pos: 3) { $0 % 2 == 0 }
        XCTAssertEqual(result.order, [0, 2, 5, 4])
        XCTAssertEqual(result.pos, 2)
    }

    func testPruneWithBrokenPositionDropsAllUnavailable() {
        let result = OfflineQueue.prune(order: [1, 2, 3], pos: 7) { $0 != 2 }
        XCTAssertEqual(result.order, [1, 3])
        XCTAssertEqual(result.pos, 0)
    }

    // MARK: плашка «Пропала сеть»

    func testSuggestOncePerOutage() {
        var state = OfflineSuggest.next(shown: false, online: false, modeOn: false, enabled: true)
        XCTAssertTrue(state.show)
        state = OfflineSuggest.next(shown: state.shown, online: false, modeOn: false, enabled: true)
        XCTAssertFalse(state.show, "та же пропажа — без новой плашки")
        state = OfflineSuggest.next(shown: state.shown, online: true, modeOn: false, enabled: true)
        XCTAssertFalse(state.shown, "сеть вернулась — счёт сначала")
        XCTAssertTrue(OfflineSuggest.next(shown: state.shown, online: false, modeOn: false, enabled: true).show)
    }

    func testSuggestSilentWhenModeOnOrDisabled() {
        XCTAssertFalse(OfflineSuggest.next(shown: false, online: false, modeOn: true, enabled: true).show)
        XCTAssertFalse(OfflineSuggest.next(shown: false, online: false, modeOn: false, enabled: false).show)
    }

    // MARK: поиск

    func testSearchMatchesEveryWordAcrossFields() {
        let list = [
            track("ym:1", title: "Blinding Lights", artist: "The Weeknd", album: "After Hours"),
            track("ym:2", title: "Lights Up", artist: "Harry Styles"),
        ]
        XCTAssertEqual(OfflineSearch.match(list, query: "lights weeknd").map(\.ref), ["ym:1"])
        XCTAssertEqual(OfflineSearch.match(list, query: "after").map(\.ref), ["ym:1"])
        XCTAssertEqual(OfflineSearch.match(list, query: "LIGHTS").map(\.ref), ["ym:1", "ym:2"])
        XCTAssertEqual(OfflineSearch.match(list, query: "  "), [])
    }

    // MARK: строки

    func testOfflineStringsTranslated() {
        let keys = [
            "Сервисы подключаются только с сетью.",
            "Sonar не выходит в интернет и показывает только скачанные треки и кэш волны. Для роуминга и слабой сети",
            "Офлайн-режим", "Предлагать офлайн-режим", "Всё доступное",
            "Играет только то, что есть на этом телефоне",
        ]
        for key in keys {
            for lang in [Lang.en, .uk, .es, .de, .pl] {
                XCTAssertNotEqual(I18n.translate(key, lang: lang), key, "\(lang): \(key)")
            }
        }
    }
}
