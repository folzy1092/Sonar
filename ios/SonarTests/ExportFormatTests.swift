import XCTest
@testable import Sonar

/// Экспорт плейлиста (`PlaylistExport`) — те же правила и ожидания, что на ПК (`windows/src/lib/export.test.ts`).
final class ExportFormatTests: XCTestCase {
    private func track(
        ref: String = "sc:1",
        title: String = "Song",
        artist: String = "Artist",
        album: AlbumRef? = nil,
        durationMs: Int = 123_400,
        url: String? = "https://soundcloud.com/artist/song"
    ) -> Track {
        Track(ref: ref, title: title, artist: artist, artists: [ArtistRef(ref: "sca:5", name: artist, avatarURL: nil)],
              album: album, durationMs: durationMs, coverURL: nil, url: url, explicit: false, available: true)
    }

    private func item(_ track: Track, addedAt: Int64? = nil) -> ExportItem {
        ExportItem(track: track, addedAt: addedAt)
    }

    // MARK: - Имя файла

    func testSafeFileNameKeepsOrdinaryAndUnicodeNames() {
        XCTAssertEqual(PlaylistExport.safeFileName("Мой плейлист"), "Мой плейлист")
        XCTAssertEqual(PlaylistExport.safeFileName("Café ☕ 2024"), "Café ☕ 2024")
        XCTAssertEqual(PlaylistExport.safeFileName("日本の歌"), "日本の歌")
    }

    func testSafeFileNameReplacesForbiddenAndControlCharacters() {
        XCTAssertEqual(PlaylistExport.safeFileName("AC/DC: Best?"), "AC DC Best")
        XCTAssertEqual(PlaylistExport.safeFileName("a<b>c\"d\\e|f*g"), "a b c d e f g")
        XCTAssertEqual(PlaylistExport.safeFileName("line\nbreak\ttab\u{0}nul"), "line break tab nul")
    }

    func testSafeFileNameTrimsDotsAndFallsBack() {
        XCTAssertEqual(PlaylistExport.safeFileName("  ..hidden.. "), "hidden")
        XCTAssertEqual(PlaylistExport.safeFileName("end."), "end")
        XCTAssertEqual(PlaylistExport.safeFileName(""), "Sonar")
        XCTAssertEqual(PlaylistExport.safeFileName("???"), "Sonar")
        XCTAssertEqual(PlaylistExport.safeFileName(" . . "), "Sonar")
    }

    func testSafeFileNameGuardsWindowsDeviceNames() {
        XCTAssertEqual(PlaylistExport.safeFileName("CON"), "_CON")
        XCTAssertEqual(PlaylistExport.safeFileName("nul"), "_nul")
        XCTAssertEqual(PlaylistExport.safeFileName("com1.backup"), "_com1.backup")
        XCTAssertEqual(PlaylistExport.safeFileName("Console"), "Console")
    }

    func testSafeFileNameLimitsLengthByScalars() {
        XCTAssertEqual(PlaylistExport.safeFileName(String(repeating: "я", count: 300)).unicodeScalars.count, PlaylistExport.maxNameChars)
        XCTAssertEqual(PlaylistExport.safeFileName(String(repeating: "🎵", count: 300)).unicodeScalars.count, PlaylistExport.maxNameChars)
    }

    // MARK: - Ссылки

    func testTrackWebURLPrefersOwnLinkThenRegistry() {
        XCTAssertEqual(PlaylistExport.trackWebURL(track(ref: "ym:7", url: "https://music.yandex.ru/album/3/track/7")),
                       "https://music.yandex.ru/album/3/track/7")
        XCTAssertEqual(PlaylistExport.trackWebURL(track(ref: "ym:7", url: nil)), "https://music.yandex.ru/track/7")
        XCTAssertEqual(PlaylistExport.trackWebURL(track(ref: "yt:dQw4w9WgXcQ", url: nil)), "https://music.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(PlaylistExport.trackWebURL(track(ref: "sp:4uLU6hMCjMI75M1A2tKUQC", url: nil)),
                       "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertEqual(PlaylistExport.trackWebURL(track(ref: "vk:-2001_42", url: nil)), "https://vk.com/audio-2001_42")
        XCTAssertEqual(PlaylistExport.trackWebURL(track(ref: "yt:a b&c", url: nil)), "https://music.youtube.com/watch?v=a%20b%26c")
    }

    func testTrackWebURLIgnoresNonHTTPLinksAndUnknownRefs() {
        XCTAssertNil(PlaylistExport.trackWebURL(track(ref: "sc:1", url: "javascript:alert(1)")))
        XCTAssertNil(PlaylistExport.trackWebURL(track(ref: "sc:1", url: nil)))
        XCTAssertNil(PlaylistExport.trackWebURL(track(ref: "local:abc", url: nil)))
        XCTAssertNil(PlaylistExport.trackWebURL(track(ref: "ymalb:9", url: nil)))
        XCTAssertNil(PlaylistExport.trackWebURL(track(ref: "zz:1", url: nil)))
    }

    // MARK: - M3U8

    func testM3U8WritesHeaderExtinfAndLinks() {
        let out = PlaylistExport.m3u8(name: "Микс", items: [
            item(track()),
            item(track(ref: "ym:7", title: "Хочешь?", artist: "Земфира", url: nil)),
        ])
        XCTAssertEqual(out, [
            "#EXTM3U",
            "#PLAYLIST:Микс",
            "#EXTINF:123,Artist - Song",
            "https://soundcloud.com/artist/song",
            "#EXTINF:123,Земфира - Хочешь?",
            "https://music.yandex.ru/track/7",
            "",
        ].joined(separator: "\n"))
    }

    func testM3U8KeepsEntriesOnOneLineAndMarksUnknownDuration() {
        let out = PlaylistExport.m3u8(name: "a\nb", items: [item(track(ref: "local:x", title: "two\r\nlines", durationMs: 0, url: nil))])
        XCTAssertEqual(out.components(separatedBy: "\n"), ["#EXTM3U", "#PLAYLIST:a b", "#EXTINF:-1,Artist - two lines", "local:x", ""])
        XCTAssertTrue(PlaylistExport.m3u8(name: "x", items: [item(track(title: "One, Two"))]).contains("#EXTINF:123,Artist - One, Two\n"))
        XCTAssertTrue(PlaylistExport.m3u8(name: "x", items: [item(track(artist: ""))]).contains("#EXTINF:123,Song\n"))
    }

    // MARK: - CSV

    func testCSVCellQuoting() {
        XCTAssertEqual(PlaylistExport.csvCell("plain"), "plain")
        XCTAssertEqual(PlaylistExport.csvCell("Ёлка 🎄"), "Ёлка 🎄")
        XCTAssertEqual(PlaylistExport.csvCell("a,b"), "\"a,b\"")
        XCTAssertEqual(PlaylistExport.csvCell("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(PlaylistExport.csvCell("two\nlines"), "\"two\nlines\"")
        XCTAssertEqual(PlaylistExport.csvCell("cr\rhere"), "\"cr\rhere\"")
    }

    func testCSVCellNeutralizesFormulasInTextOnly() {
        XCTAssertEqual(PlaylistExport.csvCell("=HYPERLINK(\"x\")", text: true), "\"'=HYPERLINK(\"\"x\"\")\"")
        XCTAssertEqual(PlaylistExport.csvCell("+1", text: true), "'+1")
        XCTAssertEqual(PlaylistExport.csvCell("@me", text: true), "'@me")
        XCTAssertEqual(PlaylistExport.csvCell("-x"), "-x")
    }

    func testCSVCellChecksFirstScalarNotCharacter() {
        // «\r\n» и «=» с ударением — по одному Character, но начало-формула; итог — как на ПК
        XCTAssertEqual(PlaylistExport.csvCell("\r\n=1", text: true), "\"'\r\n=1\"")
        XCTAssertEqual(PlaylistExport.csvCell("=\u{0301}x", text: true), "'=\u{0301}x")
    }

    func testCSVWritesBOMHeaderAndCRLFRows() {
        let added = Int64(Date(timeIntervalSince1970: 1_794_918_605.999).timeIntervalSince1970 * 1000)
        let out = PlaylistExport.csv(items: [
            item(track(), addedAt: added),
            item(track(ref: "ym:7", title: "Привет, мир", artist: "Он \"сам\"", album: AlbumRef(ref: "ymalb:3", title: "Альбом"), url: nil)),
        ])
        XCTAssertTrue(out.hasPrefix("\u{FEFF}"))
        XCTAssertEqual(String(out.dropFirst()).components(separatedBy: "\r\n"), [
            "title,artist,album,duration,service,link,added",
            "Song,Artist,,123,SoundCloud,https://soundcloud.com/artist/song,2026-11-17T12:30:05Z",
            "\"Привет, мир\",\"Он \"\"сам\"\"\",Альбом,123,Яндекс Музыка,https://music.yandex.ru/track/7,",
            "",
        ])
        XCTAssertTrue(PlaylistExport.csv(items: [item(track())], label: { _ in "SC!" }).contains(",SC!,"))
        XCTAssertEqual(PlaylistExport.csv(items: []), "\u{FEFF}title,artist,album,duration,service,link,added\r\n")
    }

    // MARK: - JSON

    func testJSONWritesAPITrackFieldsPlusAddedAt() throws {
        var withPlays = track()
        withPlays.plays = 5
        let out = try PlaylistExport.json(items: [item(withPlays, addedAt: 1_794_340_594_779), item(track(ref: "ym:2"))])
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows[0].keys), ["ref", "title", "artist", "artists", "album", "duration_ms", "cover_url", "url",
                                           "explicit", "available", "added_at"])
        XCTAssertEqual(rows[0]["added_at"] as? Int64, 1_794_340_594_779)
        XCTAssertNil(rows[0]["plays"])
        XCTAssertTrue(rows[1]["added_at"] is NSNull)
        XCTAssertTrue(rows[0]["album"] is NSNull)
        let artists = try XCTUnwrap(rows[0]["artists"] as? [[String: Any]])
        XCTAssertEqual(artists.first?["name"] as? String, "Artist")
        XCTAssertTrue(artists.first?["avatar_url"] is NSNull)
    }

    func testJSONRoundTripsUnicodeAndEscapesControlCharacters() throws {
        let title = "Кавычка \" и\nперенос 🎶"
        let out = try PlaylistExport.json(items: [item(track(title: title))])
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]])
        XCTAssertEqual(rows.first?["title"] as? String, title)
        XCTAssertTrue(out.contains("\\n"))
        XCTAssertTrue(out.contains("🎶"))
        XCTAssertTrue(out.contains("https://soundcloud.com/artist/song"), "косая черта без экранирования")
        XCTAssertTrue(out.hasSuffix("]\n"))
        let empty = try PlaylistExport.json(items: [])
        let emptyRows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(empty.utf8)) as? [Any])
        XCTAssertTrue(emptyRows.isEmpty)
    }

    // MARK: - Файл

    func testWriteNamesFileAfterPlaylist() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ExportFormatTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try PlaylistExport.write(.csv, name: "AC/DC: Best?", items: [item(track())], in: dir)
        XCTAssertEqual(url.lastPathComponent, "AC DC Best.csv")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("Song,Artist"))
        XCTAssertEqual(ExportFormat.allCases.map(\.fileExtension), ["m3u8", "csv", "json"])
        XCTAssertEqual(ExportFormat.allCases.map(\.label), ["M3U8", "CSV", "JSON"])
    }
}
