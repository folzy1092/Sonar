import XCTest
@testable import Sonar

/// Свои плейлисты, сохранённые альбомы и подписки (`PlaylistStore`), длительность списка.
@MainActor
final class PlaylistStoreTests: XCTestCase {
    private func store(_ dir: URL) -> PlaylistStore {
        PlaylistStore(file: dir.appendingPathComponent("collections.json"))
    }

    func testCreateAddRemoveAndPersist() {
        let dir = tempDirectory()
        let s = store(dir)
        let id = s.create(name: "  Микс  ", tracks: [makeTrack("sc:1", "A"), makeTrack("ym:2", "B"), makeTrack("sc:1", "A")], sourceRef: "scpl:5")
        XCTAssertNotNil(id)
        let pid = id ?? ""
        XCTAssertEqual(s.playlist(pid)?.name, "Микс")
        XCTAssertEqual(s.playlist(pid)?.tracks.map(\.ref), ["sc:1", "ym:2"], "повтор внутри добавляемых пропущен")
        XCTAssertEqual(s.playlist(source: "scpl:5")?.id, pid)

        XCTAssertEqual(s.add([makeTrack("sc:3", "C")], to: pid, atStart: true), 1)
        XCTAssertEqual(s.add([makeTrack("ym:2", "B")], to: pid, atStart: false), 0, "уже лежит — не добавляется")
        XCTAssertEqual(s.add([makeTrack("ym:4", "D")], to: pid, atStart: false), 1)
        XCTAssertEqual(s.playlist(pid)?.tracks.map(\.ref), ["sc:3", "sc:1", "ym:2", "ym:4"])
        XCTAssertTrue(s.contains("ym:2", in: pid))

        s.remove(["sc:1"], from: pid)
        s.setOrder(["ym:4", "sc:3", "nope"], in: pid)
        XCTAssertEqual(s.playlist(pid)?.tracks.map(\.ref), ["ym:4", "sc:3"], "чего нет в порядке — убрано")

        s.rename(pid, to: "   ")
        XCTAssertEqual(s.playlist(pid)?.name, "Микс", "пустое имя не ставится")
        s.rename(pid, to: "Новое")
        s.setHidden(pid, true)

        let again = store(dir)
        XCTAssertEqual(again.playlist(pid)?.name, "Новое")
        XCTAssertEqual(again.playlist(pid)?.hidden, true)
        XCTAssertEqual(again.playlist(pid)?.tracks.map(\.ref), ["ym:4", "sc:3"])

        again.delete(pid)
        XCTAssertNil(again.playlist(pid))
        XCTAssertTrue(store(dir).playlists.isEmpty)
    }

    func testEmptyNameIsRejectedAndNewestFirst() {
        let s = store(tempDirectory())
        XCTAssertNil(s.create(name: " \n "))
        let a = s.create(name: "A")
        let b = s.create(name: "B")
        XCTAssertEqual(s.playlists.map(\.id), [b, a].compactMap { $0 })
    }

    func testUpdatedAtMovesOnEdit() {
        let s = store(tempDirectory())
        var clock = 1000
        s.now = { clock }
        let id = s.create(name: "A") ?? ""
        XCTAssertEqual(s.playlist(id)?.createdAt, 1000)
        clock = 2000
        s.add([makeTrack("sc:1", "A")], to: id, atStart: true)
        XCTAssertEqual(s.playlist(id)?.updatedAt, 2000)
        XCTAssertEqual(s.playlist(id)?.createdAt, 1000)
    }

    func testCoversAreUniqueAndAtMostFour() {
        var tracks: [Track] = []
        for i in 0 ..< 6 {
            var track = makeTrack("sc:\(i)", "A")
            track.coverURL = i == 1 ? "c0" : "c\(i)"
            tracks.append(track)
        }
        let playlist = SonarPlaylist(id: "p", name: "P", tracks: tracks, hidden: false, sourceRef: nil, createdAt: 0, updatedAt: 0)
        XCTAssertEqual(playlist.covers, ["c0", "c2", "c3", "c4"])
        XCTAssertEqual(playlist.durationMs, 6 * 200_000)
    }

    func testSavedAlbumsAndFollowedArtists() {
        let dir = tempDirectory()
        let s = store(dir)
        let album = makeAlbum("yma:1", "A")
        XCTAssertTrue(s.toggleSave(album))
        XCTAssertTrue(s.isSaved(album: "yma:1"))
        let artist = Artist(ref: "sca:x", name: "X", avatarURL: nil, followers: 10, url: nil)
        XCTAssertTrue(s.toggleFollow(artist))
        let again = store(dir)
        XCTAssertTrue(again.isSaved(album: "yma:1"))
        XCTAssertTrue(again.isFollowed(artist: "sca:x"))
        XCTAssertFalse(again.toggleSave(album))
        XCTAssertFalse(again.toggleFollow(artist))
        XCTAssertTrue(store(dir).albums.isEmpty)
        XCTAssertTrue(store(dir).artists.isEmpty)
    }

    func testPlaylistMath() {
        XCTAssertEqual(PlaylistMath.cleanName(String(repeating: "я", count: 150))?.count, 100)
        XCTAssertEqual(PlaylistMath.freeName("Новый плейлист", taken: []), "Новый плейлист")
        XCTAssertEqual(PlaylistMath.freeName("Новый плейлист", taken: ["новый плейлист", "Новый плейлист 2"]), "Новый плейлист 3")
        let list = [makeTrack("sc:1", "A"), makeTrack("sc:2", "A")]
        let start = PlaylistMath.add([makeTrack("sc:3", "A"), makeTrack("sc:1", "A")], to: list, atStart: true)
        XCTAssertEqual(start.list.map(\.ref), ["sc:3", "sc:1", "sc:2"])
        XCTAssertEqual(start.added, 1)
        XCTAssertEqual(PlaylistMath.reorder(list, to: ["sc:2", "sc:2", "sc:1"]).map(\.ref), ["sc:2", "sc:1"])
    }

    func testDurationParts() {
        XCTAssertEqual(PlaylistDuration.parts(ms: 51 * 60_000).hours, 0)
        XCTAssertEqual(PlaylistDuration.parts(ms: 51 * 60_000).minutes, 51)
        let long = PlaylistDuration.parts(ms: (6 * 60 + 51) * 60_000 + 20_000)
        XCTAssertEqual(long.hours, 6)
        XCTAssertEqual(long.minutes, 51)
        XCTAssertEqual(PlaylistDuration.parts(ms: 59 * 60_000 + 40_000).hours, 1, "59:40 округляется до часа")
    }
}

/// Свои пресеты эквалайзера и кривая для рисунка.
final class EqualizerExtrasTests: XCTestCase {
    func testUserPresetsRoundTrip() {
        let gains = Equalizer.presets[6].gains
        var list = EqualizerUserPresets.adding("  Мой  ", gains: gains, to: [])
        list = EqualizerUserPresets.adding("Второй", gains: Equalizer.flat, to: list)
        list = EqualizerUserPresets.adding("Мой", gains: Equalizer.presets[7].gains, to: list)
        XCTAssertEqual(list.map(\.name), ["Мой", "Второй"], "то же имя заменяет старый и встаёт первым")
        let raw = EqualizerUserPresets.encode(list)
        let back = EqualizerUserPresets.parse(raw)
        XCTAssertEqual(back, list)
        XCTAssertEqual(EqualizerUserPresets.removing("Мой", from: back).map(\.name), ["Второй"])
        XCTAssertEqual(EqualizerUserPresets.adding("   ", gains: gains, to: list), list)
        XCTAssertEqual(EqualizerUserPresets.encode([]), "")
    }

    func testParseIsLenientAndMatchesPCShape() {
        // формат ПК: [{name, gains}]; кривая не той длины и пустое имя — отброшены, дБ зажаты
        let raw = #"[{"name":"A","gains":[20,0,0,0,0,0,0,0,0,0,0,0]},{"name":"","gains":[0,0,0,0,0,0,0,0,0,0,0,0]},{"name":"B","gains":[1,2]}]"#
        let parsed = EqualizerUserPresets.parse(raw)
        XCTAssertEqual(parsed.map(\.name), ["A"])
        XCTAssertEqual(parsed.first?.gains.first, Equalizer.maxDb)
        XCTAssertTrue(EqualizerUserPresets.parse("не json").isEmpty)
        XCTAssertTrue(EqualizerUserPresets.parse("").isEmpty)
    }

    func testMatchingPrefersUserPresets() {
        let bass = Equalizer.presets.first { $0.name == "Басы" }?.gains ?? Equalizer.flat
        let mine = [Equalizer.Preset(name: "Мой бас", gains: bass)]
        XCTAssertEqual(EqualizerUserPresets.matching(bass, user: mine)?.name, "Мой бас")
        XCTAssertEqual(EqualizerUserPresets.matching(bass, user: [])?.name, "Басы")
    }

    func testCurveIsFlatForFlatGains() {
        let points = EqualizerCurve.points(Equalizer.flat, count: 32)
        XCTAssertEqual(points.count, 32)
        XCTAssertTrue(points.allSatisfy { abs($0.db) < 0.01 })
        XCTAssertEqual(points.first?.x, 0)
        XCTAssertEqual(points.last?.x, 1)
    }

    func testCurveFollowsBands() {
        // +6 дБ на 1 кГц — пик кривой около 1 кГц и близко к +6
        var gains = Equalizer.flat
        gains[5] = 6
        let filter = Biquad.peaking(frequency: 1000, gainDb: 6, q: Equalizer.q, sampleRate: EqualizerCurve.sampleRate)
        XCTAssertEqual(EqualizerCurve.response(filter, frequency: 1000), 6, accuracy: 0.05)
        XCTAssertEqual(EqualizerCurve.response(filter, frequency: 20), 0, accuracy: 0.1)
        let points = EqualizerCurve.points(gains, count: 200)
        let peak = points.max { $0.db < $1.db }
        XCTAssertEqual(peak?.db ?? 0, 6, accuracy: 0.3)
        let peakFrequency = EqualizerCurve.frequency(at: peak?.x ?? 0)
        XCTAssertGreaterThan(peakFrequency, 800)
        XCTAssertLessThan(peakFrequency, 1250)
    }

    func testScaleRoundTrip() {
        XCTAssertEqual(EqualizerCurve.frequency(at: 0), 20, accuracy: 0.001)
        XCTAssertEqual(EqualizerCurve.frequency(at: 1), 20_000, accuracy: 0.1)
        XCTAssertEqual(EqualizerCurve.position(of: EqualizerCurve.frequency(at: 0.37)), 0.37, accuracy: 1e-9)
    }
}
