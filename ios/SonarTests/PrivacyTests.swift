import XCTest
@testable import Sonar

/// Приватность на iPhone: значения `privacy.*`, кто что видит, умолчания и строки экрана.
@MainActor
final class PrivacyTests: XCTestCase {
    private func makeStore() -> SettingsStore {
        SettingsStore(storage: UserDefaults(suiteName: "privacy-\(UUID().uuidString)")!)
    }

    func testAudienceReadsStringsAndOldBooleans() {
        XCTAssertEqual(Audience.of(.string("friends")), .friends)
        XCTAssertEqual(Audience.of(.string("nobody")), .nobody)
        XCTAssertEqual(Audience.of(.bool(true)), .everyone)
        XCTAssertEqual(Audience.of(.bool(false)), .nobody)
        XCTAssertEqual(Audience.of(.string("garbage")), .everyone)
        XCTAssertEqual(Audience.of(.int(3)), .everyone)
        XCTAssertEqual(Audience.of(nil), .everyone)
    }

    func testAudienceVisibility() {
        XCTAssertTrue(Audience.everyone.visible(toFriend: false))
        XCTAssertTrue(Audience.friends.visible(toFriend: true))
        XCTAssertFalse(Audience.friends.visible(toFriend: false))
        XCTAssertFalse(Audience.nobody.visible(toFriend: true))
    }

    func testFriendRequests() {
        XCTAssertEqual(FriendRequests.of(.string("fof")), .fof)
        XCTAssertEqual(FriendRequests.of(.string("??")), .everyone)
        XCTAssertEqual(FriendRequests.of(.bool(false)), .everyone)
        XCTAssertTrue(FriendRequests.everyone.allows(hasMutualFriends: false))
        XCTAssertTrue(FriendRequests.fof.allows(hasMutualFriends: true))
        XCTAssertFalse(FriendRequests.fof.allows(hasMutualFriends: false))
        XCTAssertFalse(FriendRequests.nobody.allows(hasMutualFriends: true))
    }

    func testDefaultsOpenEverything() {
        let store = makeStore()
        for key in PrivacyKey.rows.map(\.key) + [PrivacyKey.friendRequests] {
            XCTAssertEqual(store.value(key), .string("everyone"), key)
        }
    }

    func testChoiceIsStored() {
        let store = makeStore()
        store.set("privacy.likes", .string(Audience.friends.rawValue))
        XCTAssertEqual(Audience.of(store.value("privacy.likes")), .friends)
    }

    func testRowsMatchPcOrder() {
        XCTAssertEqual(PrivacyKey.rows.map(\.key),
                       ["privacy.playlists", "privacy.likes", "privacy.now_playing", "privacy.stats"])
    }

    func testScreenStringsTranslated() {
        let titles = PrivacyKey.rows.flatMap { [$0.title, $0.hint] }
            + Audience.allCases.map(\.title) + FriendRequests.allCases.map(\.title)
            + ["Приватность", "Кто может добавить в друзья", "Остальные не смогут отправить заявку",
               "Друзья и заявки заработают вместе с сервером", "Кто что видит по ссылке на твой профиль"]
        for lang in [Lang.en, .uk] {
            let dict = I18n.dictionaries[lang] ?? [:]
            for key in titles { XCTAssertNotNil(dict[key], "\(lang): \(key)") }
        }
    }
}
