import XCTest
@testable import Sonar

/// Резервный сервис — те же случаи, что `windows/src/lib/fallback.test.ts` и тесты `services/fallback.rs`.
final class FallbackTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONValue(data: Data(text.utf8))
    }

    private func track(_ ref: String, _ artist: String, _ title: String, _ ms: Int, available: Bool = true) -> Track {
        Track(ref: ref, title: title, artist: artist, artists: [ArtistRef(ref: "yma:1", name: artist)],
              album: nil, durationMs: ms, coverURL: nil, url: nil, explicit: false, available: available)
    }

    // MARK: - Порядок

    func testDefaultOrderComesFromRegistry() {
        XCTAssertEqual(FallbackPlan.defaultOrder, [.sc, .ym, .yt], "VK убран — в резерве его нет")
        XCTAssertFalse(FallbackPlan.defaultOrder.contains(.sp))
        XCTAssertFalse(FallbackPlan.defaultOrder.contains(.local))
    }

    func testSavedOrderDropsUnknownAndRepeatsAndAppendsForgotten() {
        XCTAssertEqual(FallbackPlan.order("yt,yandex,sp,yt,nope"), [.yt, .ym, .sc])
        XCTAssertEqual(FallbackPlan.order(" vk , sc "), [.sc, .ym, .yt], "сохранённый VK отбрасывается")
    }

    func testEmptyOrderIsDefault() {
        XCTAssertEqual(FallbackPlan.order(""), FallbackPlan.defaultOrder)
        XCTAssertEqual(FallbackPlan.order(nil), FallbackPlan.defaultOrder)
    }

    func testEncodeRoundTrips() {
        let order: [ServiceID] = [.yt, .sc, .ym]
        XCTAssertEqual(FallbackPlan.encode(order), "yt,sc,ym")
        XCTAssertEqual(FallbackPlan.order(FallbackPlan.encode(order)), order)
    }

    func testSettingsInitParsesOrder() {
        let settings = FallbackSettings(enabled: false, saved: "ym")
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.order, [.ym, .sc, .yt])
        XCTAssertEqual(FallbackSettings(), FallbackSettings(enabled: true, saved: ""))
    }

    func testCandidatesSkipSourceAndTried() {
        let order: [ServiceID] = [.sc, .ym, .yt]
        XCTAssertEqual(FallbackPlan.candidates(order: order, from: .sc, skip: []), [.ym, .yt])
        XCTAssertEqual(FallbackPlan.candidates(order: order, from: .sp, skip: [.ym]), [.sc, .yt])
        XCTAssertEqual(FallbackPlan.candidates(order: order, from: .vk, skip: []), [.sc, .ym, .yt], "старый трек VK уходит в резерв")
    }

    func testMovedReturnsNewList() {
        let list: [ServiceID] = [.sc, .ym, .yt]
        XCTAssertEqual(FallbackPlan.moved(list, from: 2, by: -1), [.sc, .yt, .ym])
        XCTAssertEqual(FallbackPlan.moved(list, from: 0, by: 1), [.ym, .sc, .yt])
        XCTAssertEqual(FallbackPlan.moved(list, from: 0, by: -1), list)
        XCTAssertEqual(FallbackPlan.moved(list, from: 2, by: 1), list)
        XCTAssertEqual(list, [.sc, .ym, .yt])
    }

    func testCanBackUpOnlyWithSearchAndStream() {
        XCTAssertTrue(FallbackPlan.canBackUp(ServiceRegistry.info(.yt)))
        XCTAssertFalse(FallbackPlan.canBackUp(ServiceRegistry.info(.sp)))
        XCTAssertFalse(FallbackPlan.canBackUp(ServiceRegistry.info(.local)))
    }

    // MARK: - Тост и плашка

    func testToastNamesBothServices() {
        let via = FallbackVia(ref: "yt:abc", service: .yt, from: .sc, reason: .unavailable)
        XCTAssertEqual(FallbackPlan.toast(via, lang: .ru), "Играет из YouTube Music — в SoundCloud недоступен")
        XCTAssertEqual(FallbackPlan.toast(via, lang: .en), "Playing from YouTube Music — unavailable on SoundCloud")
    }

    func testToastByReason() {
        let preview = FallbackVia(ref: "sc:1", service: .sc, from: .ym, reason: .preview)
        XCTAssertEqual(FallbackPlan.toast(preview, lang: .ru), "Играет из SoundCloud — в Яндекс Музыке только отрывок")
        XCTAssertEqual(FallbackPlan.toast(preview, lang: .uk), "Грає з SoundCloud — у Яндекс Музиці лише уривок")
        let premium = FallbackVia(ref: "ym:1", service: .ym, from: .sp, reason: .premium)
        XCTAssertEqual(FallbackPlan.toast(premium, lang: .ru), "Играет из Яндекс Музыка — в Spotify нужна подписка")
        let failed = FallbackVia(ref: "vk:1_2", service: .vk, from: .yt, reason: .failed)
        XCTAssertEqual(FallbackPlan.toast(failed, lang: .ru), "Играет из VK Музыка — в YouTube Music недоступен")
    }

    func testPreferredHasNoToast() {
        let via = FallbackVia(ref: "ym:1", service: .ym, from: .sc, reason: .preferred)
        XCTAssertNil(FallbackPlan.toast(via, lang: .ru))
        XCTAssertNil(FallbackPlan.toast(nil, lang: .ru))
    }

    // MARK: - Всплывашка резерва — одна на трек

    func testNoticeOncePerTrack() {
        let via = FallbackVia(ref: "ym:1", service: .ym, from: .sc, reason: .preview)
        // новый трек с резервом — говорим и запоминаем трек
        let first = FallbackNotice.next(via, ref: "sc:1", shown: nil, lang: .ru)
        XCTAssertEqual(first.text, "Играет из Яндекс Музыка — в SoundCloud только отрывок")
        XCTAssertEqual(first.shown, "sc:1")
        // тот же трек загрузился ещё раз (свежая ссылка, попытка попроще) — молчим
        let again = FallbackNotice.next(via, ref: "sc:1", shown: first.shown, lang: .ru)
        XCTAssertNil(again.text)
        XCTAssertEqual(again.shown, "sc:1")
        // другой трек с резервом — снова говорим
        let other = FallbackNotice.next(via, ref: "sc:2", shown: again.shown, lang: .ru)
        XCTAssertNotNil(other.text)
        XCTAssertEqual(other.shown, "sc:2")
    }

    func testNoticeResetsOnTrackWithoutFallback() {
        let via = FallbackVia(ref: "ym:1", service: .ym, from: .sc, reason: .unavailable)
        let plain = FallbackNotice.next(nil, ref: "sc:2", shown: "sc:1", lang: .ru)
        XCTAssertNil(plain.text)
        XCTAssertNil(plain.shown)
        // вернулись к треку с резервом — скажем снова
        XCTAssertNotNil(FallbackNotice.next(via, ref: "sc:1", shown: plain.shown, lang: .ru).text)
        // «SoundCloud через Яндекс» — настройка, без всплывашки
        let preferred = FallbackVia(ref: "ym:1", service: .ym, from: .sc, reason: .preferred)
        XCTAssertNil(FallbackNotice.next(preferred, ref: "sc:3", shown: nil, lang: .ru).text)
    }

    func testNoticeHoldsFourSeconds() {
        let note = "Играет из Яндекс Музыка — в SoundCloud только отрывок"
        XCTAssertEqual(FallbackNotice.seconds(for: note, note: note), 4)
        XCTAssertEqual(FallbackNotice.seconds(for: "Следующим: «Дежавю»", note: note), 2.6)
        XCTAssertEqual(FallbackNotice.seconds(for: note, note: nil), 2.6)
    }

    func testLabeledAddsServiceName() {
        let file = StreamSource.file(url: URL(string: "https://x/a.mp3")!, quality: "MP3 320")
        XCTAssertEqual(FallbackPlan.labeled(file, .ym), .file(url: URL(string: "https://x/a.mp3")!, quality: "MP3 320 · Яндекс Музыка"))
        let hls = StreamSource.hls(url: URL(string: "https://x/a.m3u8")!, quality: "AAC 160")
        XCTAssertEqual(FallbackPlan.labeled(hls, .sc), .hls(url: URL(string: "https://x/a.m3u8")!, quality: "AAC 160 · SoundCloud"))
    }

    func testNameIn() {
        XCTAssertEqual(ServiceRegistry.info(.ym).nameIn, "Яндекс Музыке")
        XCTAssertEqual(ServiceRegistry.info(.vk).nameIn, "VK Музыке")
        XCTAssertEqual(ServiceRegistry.info(.sc).nameIn, "SoundCloud")
        XCTAssertEqual(ServiceRegistry.info(.local).nameIn, "локальных файлах")
    }

    // MARK: - Причины

    func testReasonOfErrors() {
        XCTAssertEqual(Unplayable.reason(of: Unplayable(reason: .premium, message: Spotify.needsFallback)), .premium)
        XCTAssertEqual(Unplayable.reason(of: ServiceError(message: "сеть")), .failed)
        XCTAssertNil(Unplayable.preview(of: ServiceError(message: "сеть")))
        let source = StreamSource.file(url: URL(string: "https://x/p.mp3")!, quality: "MP3")
        XCTAssertEqual(Unplayable.preview(of: Unplayable(reason: .preview, message: "отрывок", preview: source)), source)
        XCTAssertEqual(Unplayable(reason: .unavailable, message: "нет").localizedDescription, "нет")
    }

    func testSoundCloudSnippet() throws {
        XCTAssertTrue(SoundCloud.isSnippet(try json(#"{"policy": "SNIP", "media": {"transcodings": []}}"#)))
        let snipped = try json(#"{"policy": "ALLOW", "media": {"transcodings": [{"format": {"protocol": "progressive", "mime_type": "audio/mpeg"}, "preset": "mp3_1_0", "snipped": true}]}}"#)
        XCTAssertTrue(SoundCloud.isSnippet(snipped))
        let full = try json(#"{"policy": "ALLOW", "media": {"transcodings": [{"format": {"protocol": "progressive", "mime_type": "audio/mpeg"}, "preset": "mp3_1_0", "snipped": false}]}}"#)
        XCTAssertFalse(SoundCloud.isSnippet(full))
    }

    func testYandexPrefersFullTrackOverPreview() throws {
        let infos = try json(#"[{"codec": "mp3", "bitrateInKbps": 320, "preview": true}, {"codec": "mp3", "bitrateInKbps": 192}]"#)
        XCTAssertEqual(Yandex.pickMP3(infos, maxKbps: 320)?["bitrateInKbps"].int, 192)
        let onlyPreview = try json(#"[{"codec": "mp3", "bitrateInKbps": 128, "preview": true}]"#)
        let picked = try XCTUnwrap(Yandex.pickMP3(onlyPreview, maxKbps: 320))
        XCTAssertTrue(Yandex.isPreview(picked))
    }

    // MARK: - Сверка

    func testScoreIgnoresAvailabilityButBestDoesNot() {
        let wanted = TrackMatch.soundCloud(uploader: "EsDeeKid", metaArtist: nil, title: "4 Raws", durationMs: 146_000)
        let gone = track("ym:1", "EsDeeKid", "4 Raws", 146_500, available: false)
        XCTAssertNotNil(wanted.score(gone))
        XCTAssertNil(wanted.best([gone]))
    }

    func testScoreRejectsVersionsAndDuration() {
        let wanted = TrackMatch.soundCloud(uploader: "A", metaArtist: nil, title: "Song", durationMs: 100_000)
        XCTAssertNil(wanted.score(track("ym:1", "A", "Song (Slowed)", 100_000)))
        XCTAssertNil(wanted.score(track("ym:2", "A", "Song", 104_000)))
        XCTAssertNil(wanted.score(track("ym:3", "B", "Song", 100_000)))
    }

    func testSameTrackAcrossServices() {
        let youtube = track("yt:abc", "Кизару", "Дежавю", 180_000)
        let yandex = track("ym:8", "Кизару", "Дежавю", 181_500)
        XCTAssertTrue(TrackMatch.sameTrack(youtube, yandex))
        XCTAssertTrue(TrackMatch.sameTrack(yandex, youtube))
        XCTAssertTrue(TrackMatch.sameTrack(yandex, yandex))
        XCTAssertFalse(TrackMatch.sameTrack(yandex, track("yt:x", "Кизару", "Дежавю (Remix)", 181_000)))
    }

    func testFromTrackUsesArtistsAndTitle() {
        let wanted = TrackMatch.from(track("vk:1_2", "Кизару", "Дежавю", 180_000))
        XCTAssertEqual(wanted.queries, ["Кизару Дежавю"])
        XCTAssertEqual(wanted.durationMs, 180_000)
    }
}
