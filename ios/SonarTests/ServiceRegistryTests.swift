import XCTest
@testable import Sonar

/// Реестр сервисов — та же таблица, что docs/API.md «Префиксы ref» и Windows `registry.rs` / `services.ts`.
final class ServiceRegistryTests: XCTestCase {
    private struct Row {
        let id: ServiceID
        let key: String
        let name: String
        let color: String
        let icon: String?
        let iconMono: String?
        let prefixes: ServicePrefixes
        let implemented: Bool
    }

    private let table: [Row] = [
        Row(id: .sc, key: "soundcloud", name: "SoundCloud", color: "#FF5500", icon: "SoundCloud.svg", iconMono: "soundcloud-mono.svg",
            prefixes: ServicePrefixes(track: "sc", album: "scalb", artist: "sca", playlist: "scpl"), implemented: true),
        Row(id: .ym, key: "yandex", name: "Яндекс Музыка", color: "#FFBC0D", icon: "Yandex-Music.svg", iconMono: "yandex-music-mono.svg",
            prefixes: ServicePrefixes(track: "ym", album: "ymalb", artist: "yma", playlist: "ympl"), implemented: true),
        Row(id: .yt, key: "youtube", name: "YouTube Music", color: "#FF0033", icon: "youtube-music.svg", iconMono: "youtube-music-mono.svg",
            prefixes: ServicePrefixes(track: "yt", album: "ytalb", artist: "yta", playlist: "ytpl"), implemented: true),
        Row(id: .vk, key: "vk", name: "VK Музыка", color: "#0077FF", icon: "vk.svg", iconMono: "vk-mono.svg",
            prefixes: ServicePrefixes(track: "vk", album: "vkalb", artist: "vka", playlist: "vkpl"), implemented: true),
        Row(id: .sp, key: "spotify", name: "Spotify", color: "#1ED760", icon: "spotify.svg", iconMono: "spotify-mono.svg",
            prefixes: ServicePrefixes(track: "sp", album: "spalb", artist: "spa", playlist: "sppl"), implemented: false),
        Row(id: .local, key: "local", name: "Локальные файлы", color: "#8E8E93", icon: nil, iconMono: nil,
            prefixes: ServicePrefixes(track: "local", album: nil, artist: nil, playlist: nil), implemented: false),
    ]

    func testTable() {
        XCTAssertEqual(ServiceRegistry.all.map(\.id), [.sc, .ym, .yt, .vk, .sp, .local])
        XCTAssertEqual(ServiceRegistry.all.count, table.count)
        for (info, row) in zip(ServiceRegistry.all, table) {
            XCTAssertEqual(info.id, row.id)
            XCTAssertEqual(info.key, row.key, row.id.rawValue)
            XCTAssertEqual(info.name, row.name, row.id.rawValue)
            XCTAssertEqual(info.color, row.color, row.id.rawValue)
            XCTAssertEqual(info.icon, row.icon, row.id.rawValue)
            XCTAssertEqual(info.iconMono, row.iconMono, row.id.rawValue)
            XCTAssertEqual(info.prefixes, row.prefixes, row.id.rawValue)
            XCTAssertEqual(info.implemented, row.implemented, row.id.rawValue)
            XCTAssertEqual(ServiceRegistry.info(row.id), info)
        }
        let spotify = ServiceRegistry.info(.sp).caps
        XCTAssertFalse(spotify.stream)
        XCTAssertFalse(spotify.key)
        let local = ServiceRegistry.info(.local).caps
        XCTAssertEqual(local, ServiceCaps(search: false, stream: true, library: true, playlists: false, similar: false, login: false, key: false))
        XCTAssertEqual(ServiceRegistry.implemented.map(\.id), [.sc, .ym, .yt, .vk])
        XCTAssertTrue(ServiceRegistry.info(.yt).caps.key, "cookie YouTube Music вручную")
    }

    func testPrefixesUnique() {
        let all = ServiceRegistry.all.flatMap { info in
            [info.prefixes.track, info.prefixes.album, info.prefixes.artist, info.prefixes.playlist].compactMap { $0 }
        }
        XCTAssertEqual(all.count, 21)
        XCTAssertEqual(Set(all).count, all.count, "префиксы не должны повторяться")
    }

    func testParse() {
        let cases: [(String, ServiceID?, RefKind?)] = [
            ("sc:123", .sc, .track),
            ("scalb:9", .sc, .album),
            ("sca:7", .sc, .artist),
            ("scpl:likes", .sc, .playlist),
            ("ympl:42:1003", .ym, .playlist),
            ("ymalb:5", .ym, .album),
            ("yma:1", .ym, .artist),
            ("yt:abc", .yt, .track),
            ("vk:-2001_456", .vk, .track),
            ("vkalb:-2000111_77_k9", .vk, .album),
            ("vka:123", .vk, .artist),
            ("vkpl:likes", .vk, .playlist),
            ("local:abc", .local, .track),
            ("pl_x", nil, nil),
            ("similar:sc:1", nil, nil),
            ("sc", nil, nil),
            ("", nil, nil),
            (":1", nil, nil),
        ]
        for (ref, service, kind) in cases {
            let parsed = ServiceRegistry.parse(ref: ref)
            XCTAssertEqual(parsed?.info.id, service, ref)
            XCTAssertEqual(parsed?.kind, kind, ref)
            XCTAssertEqual(ServiceRegistry.service(of: ref), service, ref)
        }
    }

    func testByKey() {
        XCTAssertEqual(ServiceRegistry.byKey("sc")?.id, .sc)
        XCTAssertEqual(ServiceRegistry.byKey("soundcloud")?.id, .sc)
        XCTAssertEqual(ServiceRegistry.byKey("yandex")?.id, .ym)
        XCTAssertEqual(ServiceRegistry.byKey("youtube")?.id, .yt)
        XCTAssertEqual(ServiceRegistry.byKey("yt")?.id, .yt)
        XCTAssertNil(ServiceRegistry.byKey("zz"))
        XCTAssertNil(ServiceRegistry.byKey(""))
    }

    func testServiceRefEquivalence() {
        func old(_ ref: String) -> Service? {
            if ref.hasPrefix("sc") { return .soundcloud }
            if ref.hasPrefix("ym") { return .yandex }
            if ref.hasPrefix("yt") { return .youtube }
            return nil
        }
        for ref in ["sc:1", "scpl:likes", "scalb:2", "sca:3", "ym:1", "ympl:1:2", "ymalb:2", "yma:3", "yt:1", "ytpl:likes", "ytalb:2", "yta:3"] {
            XCTAssertNotNil(Service(ref: ref), ref)
            XCTAssertEqual(Service(ref: ref), old(ref), ref)
        }
        XCTAssertEqual(Service(ref: "yt:1"), .youtube)
        XCTAssertNil(Service(ref: "pl_x"))
        XCTAssertEqual(Service(id: .sc), .soundcloud)
        XCTAssertEqual(Service(id: .ym), .yandex)
        XCTAssertEqual(Service(id: .yt), .youtube)
        XCTAssertEqual(Service.youtube.id, .yt)
        XCTAssertEqual(Service.youtube.info.key, "youtube")
        XCTAssertEqual(Service.youtube.title, "YouTube Music")
        XCTAssertEqual(Service(id: .vk), .vk)
        XCTAssertEqual(Service(ref: "vkpl:1_2"), .vk)
        XCTAssertEqual(Service.vk.info.key, "vk")
        XCTAssertEqual(Service.vk.title, "VK Музыка")
        XCTAssertNil(Service(id: .sp))
        XCTAssertEqual(Service.soundcloud.id, .sc)
        XCTAssertEqual(Service.yandex.info.key, "yandex")
        XCTAssertEqual(Service.soundcloud.title, "SoundCloud")
        XCTAssertEqual(Service.yandex.title, "Яндекс Музыка")
    }

    func testMainArtistRefUnchanged() {
        var track = makeTrack("sc:1", "A", artistRef: "sca:0")
        XCTAssertNil(track.mainArtistRef)
        track.artists = [ArtistRef(ref: "sca:0", name: "A"), ArtistRef(ref: "scalb:1", name: "B"), ArtistRef(ref: "yma:5", name: "C")]
        XCTAssertEqual(track.mainArtistRef, "yma:5")
        track.artists = [ArtistRef(ref: "yta:1", name: "A")]
        XCTAssertEqual(track.mainArtistRef, "yta:1")
        track.artists = [ArtistRef(ref: "vka:1", name: "A")]
        XCTAssertNil(track.mainArtistRef)
        track.artists = [ArtistRef(ref: "vka:9", name: "A")]
        XCTAssertEqual(track.mainArtistRef, "vka:9")
    }

    func testAllCasesUnchanged() {
        XCTAssertEqual(Service.allCases, [.soundcloud, .yandex, .youtube, .vk])
        XCTAssertEqual(Service.youtube.rawValue, "youtube")
        XCTAssertEqual(Service.soundcloud.rawValue, "soundcloud")
        XCTAssertEqual(Service.yandex.rawValue, "yandex")
        // сырое значение — имя в Keychain и настройках, как key реестра
        XCTAssertEqual(Service.allCases.map(\.rawValue), Service.allCases.map(\.info.key))
    }

    /// Кнопка сервиса в Поиске: по кругу через все подключаемые сервисы.
    func testSearchSourceCycles() {
        XCTAssertEqual(Service.soundcloud.next, .yandex)
        XCTAssertEqual(Service.yandex.next, .youtube)
        XCTAssertEqual(Service.youtube.next, .soundcloud)
    }

    func testServiceAccountDecodesWithoutPremium() throws {
        let old = #"{"name":"a","avatarURL":null,"uid":"1"}"#
        let account = try JSONDecoder().decode(ServiceAccount.self, from: Data(old.utf8))
        XCTAssertEqual(account.name, "a")
        XCTAssertEqual(account.uid, "1")
        XCTAssertNil(account.premium)
        let back = try JSONDecoder().decode(ServiceAccount.self, from: JSONEncoder().encode(ServiceAccount(name: "b", premium: true)))
        XCTAssertEqual(back.premium, true)
    }

    func testYandexParseAccountPremium() throws {
        let plus = try JSONValue(data: Data(#"{"account":{"uid":42,"login":"anna","displayName":"Анна"},"plus":{"hasPlus":true}}"#.utf8))
        let account = try Yandex.parseAccount(plus)
        XCTAssertEqual(account.name, "Анна")
        XCTAssertEqual(account.uid, "42")
        XCTAssertEqual(account.premium, true)

        let noPlus = try JSONValue(data: Data(#"{"account":{"uid":"7","login":"bob"},"plus":{"hasPlus":false}}"#.utf8))
        XCTAssertEqual(try Yandex.parseAccount(noPlus).premium, false)
        XCTAssertEqual(try Yandex.parseAccount(noPlus).name, "bob")

        let missing = try JSONValue(data: Data(#"{"account":{"uid":7}}"#.utf8))
        XCTAssertNil(try Yandex.parseAccount(missing).premium)

        XCTAssertThrowsError(try Yandex.parseAccount(JSONValue(data: Data(#"{"account":{}}"#.utf8))))
    }

    func testProvidersInRegistry() {
        XCTAssertEqual(SoundCloud.serviceID, .sc)
        XCTAssertEqual(Yandex.serviceID, .ym)
        XCTAssertEqual(YouTube.serviceID, .yt)
        XCTAssertTrue(ServiceRegistry.info(YouTube.serviceID).implemented)
        XCTAssertTrue(ServiceRegistry.info(SoundCloud.serviceID).implemented)
        XCTAssertTrue(ServiceRegistry.info(Yandex.serviceID).implemented)
    }
}
