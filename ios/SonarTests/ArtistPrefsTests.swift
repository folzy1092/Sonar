import XCTest
@testable import Sonar

/// Вкус по артистам «Чаще · Реже · Никогда» (`ArtistPrefs`): разбор как на ПК, волна, «Авто похожие», синк.
@MainActor
final class ArtistPrefsTests: XCTestCase {
    private let zero: () -> Double = { 0 }

    private func joint(_ ref: String, _ names: [String]) -> Track {
        var track = makeTrack(ref, names.joined(separator: ", "), plays: 5000)
        track.artists = names.map { ArtistRef(ref: "sca:\($0.lowercased())", name: $0, avatarURL: nil) }
        return track
    }

    func testParseLikePcAndSkipJunk() {
        let raw = #"{" Markul ":{"name":"Markul","level":"more"},"oxxxy":{"name":"Oxxxymiron","level":"never"},"x":{"level":"meh"},"y":5}"#
        let prefs = ArtistPrefs.decode(raw)
        XCTAssertEqual(prefs.count, 2)
        XCTAssertEqual(prefs["markul"], ArtistPref(name: "Markul", level: .more))
        XCTAssertEqual(prefs["oxxxy"]?.level, .never)
        XCTAssertTrue(ArtistPrefs.decode("").isEmpty)
        XCTAssertTrue(ArtistPrefs.decode("не json").isEmpty)
        // обратно — тот же объект
        XCTAssertEqual(ArtistPrefs.decode(ArtistPrefs.encode(prefs)), prefs)
    }

    func testLevelNeverWinsThenMoreBeatsLess() {
        let prefs: [String: ArtistPref] = [
            "a": ArtistPref(name: "A", level: .more),
            "b": ArtistPref(name: "B", level: .less),
            "n": ArtistPref(name: "N", level: .never),
        ]
        XCTAssertEqual(ArtistPrefs.level(prefs, track: joint("sc:1", ["A", "N"])), .never)
        XCTAssertEqual(ArtistPrefs.level(prefs, track: joint("sc:2", ["B", "A"])), .more)
        XCTAssertEqual(ArtistPrefs.level(prefs, track: joint("sc:3", ["B"])), .less)
        XCTAssertNil(ArtistPrefs.level(prefs, track: joint("sc:4", ["Z"])))
    }

    func testWithSetsAndClears() {
        let set = ArtistPrefs.with([:], name: " Markul ", level: .less)
        XCTAssertEqual(set, ["markul": ArtistPref(name: "Markul", level: .less)])
        XCTAssertEqual(ArtistPrefs.level(set, name: "MARKUL"), .less)
        XCTAssertTrue(ArtistPrefs.with(set, name: "markul", level: nil).isEmpty)
        XCTAssertEqual(ArtistPrefs.with(set, name: "  ", level: .more), set)
        XCTAssertEqual(ArtistPrefs.list(ArtistPrefs.with(set, name: "Alpha", level: .never)).map(\.id), ["alpha", "markul"])
        XCTAssertEqual(ArtistPrefs.list(set, query: "ark").map(\.id), ["markul"])
    }

    func testWaveNeverSkipsCoAuthorsEvenRelaxed() {
        var filter = WaveFilter()
        filter.neverArtists = ["bad"]
        let cands = [makeTrack("sc:1", "Bad", plays: 5000), joint("sc:2", ["Good", "Bad"]), makeTrack("sc:3", "Ok", plays: 5000)]
        for relaxed in [false, true] {
            let out = WaveMath.pick(cands, taste: Taste(), origin: WaveOrigin(), session: WaveSession(), filter: filter,
                                    relaxed: relaxed, noise: zero)
            XCTAssertEqual(out.map(\.ref), ["sc:3"])
        }
        // пул из одних «Никогда» — пустая порция, а не зависание
        let empty = WaveMath.portion([makeTrack("sc:1", "Bad", plays: 5000)], taste: Taste(), origin: WaveOrigin(),
                                     session: WaveSession(), filter: filter, noise: zero)
        XCTAssertTrue(empty.isEmpty)
        let liked = WaveMath.pickLiked(cands, taste: Taste(), session: WaveSession(), filter: filter, playedMonth: [], k: 3, noise: zero)
        XCTAssertEqual(liked.map(\.ref), ["sc:3"])
    }

    func testMoreAndLessMoveTheScore() {
        var taste = Taste()
        taste.artistPref = ["loved": 1, "tired": -1]
        let score = { (name: String) in
            WaveMath.score(makeTrack("sc:1", name), taste: taste, origin: WaveOrigin(), session: WaveSession())
        }
        XCTAssertEqual(score("loved") - score("other"), ArtistPrefs.weight, accuracy: 1e-9)
        XCTAssertEqual(score("other") - score("tired"), ArtistPrefs.weight, accuracy: 1e-9)
        // соавтор «Чаще» перебивает «Реже» главного
        XCTAssertEqual(taste.pref(joint("sc:2", ["Tired", "Loved"])), 1)
    }

    func testAutoplaySkipsNever() {
        let list = [makeTrack("sc:1", "A"), makeTrack("sc:2", "Bad"), makeTrack("sc:3", "B")]
        let out = Autoplay.freshSimilar([list], inQueue: [], disliked: { _ in false }, limit: 5, never: { $0.artistKey == "bad" })
        XCTAssertEqual(out.map(\.ref), ["sc:1", "sc:3"])
    }

    func testSyncCarriesObjectBothWays() {
        let settings = SettingsStore(storage: UserDefaults(suiteName: "artist-prefs-\(UUID().uuidString)")!)
        let adapter = SettingsSyncAdapter(settings: settings)
        let journal = SyncJournal()
        // с ПК пришёл объект — телефон хранит его строкой
        let fromPc = JSONValue.object(["markul": .object(["name": .string("Markul"), "level": .string("never")])])
        XCTAssertTrue(adapter.apply(SyncChange(type: "setting", key: ArtistPrefs.key, value: fromPc, rev: 1), journal: journal))
        XCTAssertEqual(settings.artistPrefs["markul"]?.level, .never)
        // обратно уходит объект, а не строка
        settings.setArtistPrefs(ArtistPrefs.with(settings.artistPrefs, name: "Markul", level: .more))
        let snap = adapter.snapshot(journal: journal)
        XCTAssertEqual(snap[SyncKey("setting", ArtistPrefs.key)],
                       .object(["markul": .object(["name": .string("Markul"), "level": .string("more")])]))
    }
}
