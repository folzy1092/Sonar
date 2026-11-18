import XCTest
@testable import Sonar

/// Подсказка-дописывание в поиске — те же случаи, что Windows `autocomplete.test.ts`.
final class AutocompleteTests: XCTestCase {
    private func track(_ title: String, _ artists: String...) -> Track {
        var base = makeTrack("sc:\(title)", artists.first ?? "", title: title)
        base.artist = artists.joined(separator: ", ")
        base.artists = artists.map { ArtistRef(ref: "sca:\($0.lowercased())", name: $0, avatarURL: nil) }
        return base
    }

    // MARK: кандидаты

    func testLikedArtistsByLikeCountThenOrder() {
        let liked = [track("a", "Onda Andar"), track("b", "Lil Peep"), track("c", "Lil Peep", "Onda Andar"),
                     track("d", "Lil Peep"), track("e", "Burial")]
        XCTAssertEqual(Autocomplete.likedArtists(liked), ["Lil Peep", "Onda Andar", "Burial"])
    }

    func testArtistStringWhenNoArtistList() {
        var only = track("t", "Mareux")
        only.artists = []
        XCTAssertEqual(Autocomplete.likedArtists([only]), ["Mareux"])
    }

    func testPriorityLikedThenHistoryThenRecentWithoutDupes() {
        let list = Autocomplete.candidates(liked: [track("x", "Onda Andar")],
                                           history: ["onda andar", "Onyx", "Night Drive"],
                                           recent: [track("Opal", "Four Tet")])
        XCTAssertEqual(list, ["Onda Andar", "Onyx", "Night Drive", "Four Tet", "Opal"])
    }

    func testSkipsEmptyAndTooLong() {
        let long = String(repeating: "L", count: Autocomplete.maxCandidate + 1)
        XCTAssertEqual(Autocomplete.candidates(liked: [], history: ["  ", long, "Lo"], recent: []), ["Lo"])
    }

    func testEmptySourcesGiveNoHint() {
        XCTAssertEqual(Autocomplete.candidates(liked: [], history: [], recent: []), [])
        XCTAssertNil(Autocomplete.suggest([], typed: "onda"))
    }

    // MARK: подсказка

    private let list = ["Onda Andar", "Lil Peep", "Onyx", "Лето"]

    func testFirstByPriorityWins() {
        XCTAssertEqual(Autocomplete.suggest(list, typed: "On")?.full, "Onda Andar")
        XCTAssertEqual(Autocomplete.suggest(list, typed: "Ony")?.full, "Onyx")
    }

    func testCaseInsensitiveTailKeepsOriginalCase() {
        XCTAssertEqual(Autocomplete.suggest(list, typed: "onda"), .init(full: "Onda Andar", tail: " Andar", relayout: false))
        XCTAssertEqual(Autocomplete.suggest(list, typed: "ONDA A"), .init(full: "Onda Andar", tail: "ndar", relayout: false))
    }

    func testOnlyPrefixOfWholeString() {
        XCTAssertNil(Autocomplete.suggest(list, typed: "peep"))
    }

    func testNeedsTwoCharacters() {
        XCTAssertNil(Autocomplete.suggest(list, typed: "O"))
        XCTAssertNil(Autocomplete.suggest(list, typed: " O"))
    }

    func testFullyTypedHasNothingToAdd() {
        XCTAssertNil(Autocomplete.suggest(list, typed: "onyx"))
    }

    func testRussianLayoutInsteadOfEnglish() {
        XCTAssertEqual(Autocomplete.suggest(list, typed: "щтвф"), .init(full: "Onda Andar", tail: "", relayout: true))
        XCTAssertEqual(Autocomplete.suggest(list, typed: "ЩТВФ")?.full, "Onda Andar")
    }

    func testUkrainianLayout() {
        XCTAssertEqual(Autocomplete.suggest(["Sigur Ros"], typed: "іш"), .init(full: "Sigur Ros", tail: "", relayout: true))
    }

    func testEnglishLayoutInsteadOfRussian() {
        XCTAssertEqual(Autocomplete.suggest(list, typed: "ktn")?.full, "Лето")
    }

    func testDirectMatchBeatsLayout() {
        XCTAssertEqual(Autocomplete.suggest(["Лил", "Kto"], typed: "kt")?.full, "Kto")
    }

    // MARK: раскладка

    func testLayoutTables() {
        XCTAssertEqual(Autocomplete.Layout.enToRu("ghbdtn"), "привет")
        XCTAssertEqual(Autocomplete.Layout.enToRu("`krf"), "ёлка")
        XCTAssertEqual(Autocomplete.Layout.enToUk("ghbdsn"), "привіт")
        XCTAssertEqual(Autocomplete.Layout.cyrToEn("руддщ"), "hello")
        XCTAssertEqual(Autocomplete.Layout.cyrToEn("іїє"), "s]'")
        XCTAssertEqual(Autocomplete.Layout.cyrToEn("ґ"), "u")
        XCTAssertEqual(Autocomplete.Layout.enToRu("lj 2077"), "до 2077")
    }
}
