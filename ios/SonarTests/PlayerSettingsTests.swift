import XCTest
@testable import Sonar

/// Раздел «Плеер»: значения настроек и умолчания (`PlayerPrefs.swift`, `SettingsDefaults+Player.swift`),
/// правка очереди жестами (`QueueMath`), снимок для «Продолжить с прошлого раза» (`PlaybackSnapshot`).
@MainActor
final class PlayerSettingsTests: XCTestCase {
    private func track(_ ref: String) -> Track {
        Track(ref: ref, title: "Song \(ref)", artist: "A", artists: [], album: nil, durationMs: 200_000, coverURL: nil,
              url: nil, explicit: false, available: true, plays: nil, tags: nil)
    }

    private func store() -> SettingsStore {
        let name = "player-settings-\(UUID().uuidString)"
        return SettingsStore(storage: UserDefaults(suiteName: name)!)
    }

    // MARK: - Значения и умолчания

    func testDefaultsMatchSettingsDoc() {
        let settings = store()
        XCTAssertTrue(settings.bool("audio.gapless"))
        XCTAssertTrue(settings.bool("audio.normalize"), "на iPhone нормализация включена сразу")
        XCTAssertTrue(settings.bool("wave.offline"))
        XCTAssertTrue(settings.bool("wave.reasons"))
        XCTAssertEqual(PlayerPrefs.crossfade(settings), 0)
        XCTAssertEqual(InterruptionMode.current(settings), .duck)
        XCTAssertTrue(settings.bool(Equalizer.enabledKey))
        XCTAssertEqual(Equalizer.parse(settings.string(Equalizer.gainsKey)), Equalizer.flat)
        XCTAssertEqual(PlayerStyle.current(settings), .large, "на iPhone — обложка на весь экран, как было")
        XCTAssertEqual(TitleAlign.current(settings), .center)
        XCTAssertEqual(SliderStyle.current(settings), .normal)
        XCTAssertEqual(PlayButtonStyle.current(settings), .circle)
        XCTAssertTrue(settings.bool("player.artist_avatars"))
        XCTAssertTrue(settings.bool("queue.preview"))
        XCTAssertTrue(settings.bool("queue.add_following"))
        XCTAssertEqual(QueueView.current(settings), .extended)
        XCTAssertEqual(RestoreMode.current(settings), .queue)
        // каждое умолчание раздела — из своего перечисления
        for (key, value) in SettingsDefaults.player {
            XCTAssertEqual(settings.value(key), value, key)
        }
    }

    func testUnknownValuesFallBack() {
        XCTAssertEqual(PlayerStyle.from("hologram"), .large)
        XCTAssertEqual(SliderStyle.from("wave_bars"), .wave_bars)
        XCTAssertEqual(SliderStyle.from(""), .normal)
        XCTAssertEqual(PlayerBackground.from("cover_color"), .cover_color)
        XCTAssertEqual(RestoreMode.from("everything"), .queue)
    }

    func testQualityReadsOldIPhoneValue() {
        XCTAssertEqual(AudioQuality.from("lossless"), .max, "старое значение iPhone — «Максимальное»")
        XCTAssertEqual(AudioQuality.from("max"), .max)
        XCTAssertEqual(AudioQuality.from("medium"), .medium)
        let settings = store()
        AudioQuality.low.save(settings)
        XCTAssertEqual(settings.string("audio.quality"), "low")
        XCTAssertEqual(AudioQuality.current(settings), .low)
    }

    func testCrossfadeReadsIntOrDoubleAndClamps() {
        let settings = store()
        settings.set("audio.crossfade", .int(6))
        XCTAssertEqual(PlayerPrefs.crossfade(settings), 6)
        settings.set("audio.crossfade", .double(3.6))
        XCTAssertEqual(PlayerPrefs.crossfade(settings), 4, "ПК может прислать дробное")
        settings.set("audio.crossfade", .int(40))
        XCTAssertEqual(PlayerPrefs.crossfade(settings), Fades.maxCrossfade)
        settings.set("audio.crossfade", .int(-2))
        XCTAssertEqual(PlayerPrefs.crossfade(settings), 0)
    }

    func testWaveBarsStablePerTrack() {
        let a = SliderStyle.bars(count: 48, seed: "sc:1")
        XCTAssertEqual(a.count, 48)
        XCTAssertEqual(a, SliderStyle.bars(count: 48, seed: "sc:1"), "у трека столбики не прыгают")
        XCTAssertNotEqual(a, SliderStyle.bars(count: 48, seed: "ym:2"))
        XCTAssertTrue(a.allSatisfy { $0 >= 0.3 && $0 <= 1 })
    }

    // MARK: - Очередь

    func testRemoveUpcoming() {
        // играет позиция 1; «Далее»: 2, 3, 4
        let order = [0, 1, 2, 3, 4]
        XCTAssertEqual(QueueMath.removeUpcoming(order: order, pos: 1, offset: 0), [0, 1, 3, 4])
        XCTAssertEqual(QueueMath.removeUpcoming(order: order, pos: 1, offset: 2), [0, 1, 2, 3])
        XCTAssertEqual(QueueMath.removeUpcoming(order: order, pos: 1, offset: 3), order, "за концом — ничего")
        XCTAssertEqual(QueueMath.removeUpcoming(order: order, pos: 1, offset: -1), order, "текущий не трогаем")
    }

    func testMoveUpcoming() {
        let order = [0, 1, 2, 3, 4]
        XCTAssertEqual(QueueMath.moveUpcoming(order: order, pos: 1, offset: 2, toEnd: false), [0, 1, 4, 2, 3], "следующим")
        XCTAssertEqual(QueueMath.moveUpcoming(order: order, pos: 1, offset: 0, toEnd: true), [0, 1, 3, 4, 2], "в конец")
        XCTAssertEqual(QueueMath.moveUpcoming(order: order, pos: 4, offset: 0, toEnd: false), order)
    }

    // MARK: - Снимок

    private func snapshot() -> PlaybackSnapshot {
        PlaybackSnapshot(tracks: (0 ..< 5).map { track("sc:\($0)") }, order: [4, 2, 0, 1, 3], pos: 1, position: 42,
                         context: "Любимые", shuffle: true, repeatMode: .all, autoRefs: ["sc:3"])
    }

    func testRestoreModes() {
        let full = snapshot()
        XCTAssertEqual(full.current?.ref, "sc:2")
        XCTAssertNil(full.restored(.none))
        XCTAssertEqual(full.restored(.queue), full)
        let single = full.restored(.track)
        XCTAssertEqual(single?.tracks.map(\.ref), ["sc:2"])
        XCTAssertEqual(single?.order, [0])
        XCTAssertEqual(single?.position, 42, "с той же секунды")
        XCTAssertEqual(single?.repeatMode, .off)
        XCTAssertEqual(single?.shuffle, false)
    }

    func testBrokenSnapshotIsIgnored() {
        var broken = snapshot()
        broken.order = [0, 9]
        XCTAssertNil(broken.restored(.queue))
        broken.order = []
        XCTAssertNil(broken.restored(.track))
    }

    func testTrimKeepsWindowAroundCurrent() {
        let tracks = (0 ..< 500).map { track("sc:\($0)") }
        let long = PlaybackSnapshot(tracks: tracks, order: Array(0 ..< 500), pos: 200, position: 1, context: "Волна",
                                    shuffle: false, repeatMode: .off, autoRefs: ["sc:0", "sc:210"])
        let trimmed = long.trimmed(past: 50, ahead: 100)
        XCTAssertEqual(trimmed.order.count, 151)
        XCTAssertEqual(trimmed.tracks.count, 151)
        XCTAssertEqual(trimmed.current?.ref, "sc:200")
        XCTAssertEqual(trimmed.tracks.first?.ref, "sc:150")
        XCTAssertEqual(trimmed.autoRefs, ["sc:210"], "похожие за окном отпали")
    }

    func testSnapshotFileRoundTrip() {
        let file = PlaybackSnapshotFile(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("player-state-\(UUID().uuidString)/state.json"))
        XCTAssertNil(file.load())
        file.save(snapshot())
        XCTAssertEqual(file.load(), snapshot())
        file.save(nil)
        XCTAssertNil(file.load())
    }
}
