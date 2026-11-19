import XCTest
@testable import Sonar

/// Коллажи без повторов (`Covers`, зеркало ПК `lib/covers.ts` / `store/covers.rs`).
final class CoversTests: XCTestCase {
    private func track(_ url: String?, album: String? = nil, artist: String = "A", ref: String = "sc:1") -> Track {
        var t = makeTrack(ref, artist)
        t.coverURL = url
        t.album = album.map { AlbumRef(ref: $0, title: "Album") }
        return t
    }

    func testKeyStripsSizesSchemeAndQuery() {
        XCTAssertEqual(Covers.key("https://i1.sndcdn.com/artworks-a-t500x500.jpg"), "i1.sndcdn.com/artworks-a.jpg")
        XCTAssertEqual(Covers.key("http://i1.sndcdn.com/artworks-a-large.jpg?x=1"), "i1.sndcdn.com/artworks-a.jpg")
        XCTAssertEqual(Covers.key("https://i1.sndcdn.com/artworks-a-t300x300.jpg"), "i1.sndcdn.com/artworks-a.jpg")
        XCTAssertEqual(Covers.key("https://avatars.yandex.net/get-music-content/1/a/%%"), "avatars.yandex.net/get-music-content/1/a")
        XCTAssertEqual(Covers.key("https://avatars.yandex.net/get-music-content/1/a/400x400"), "avatars.yandex.net/get-music-content/1/a")
        XCTAssertEqual(Covers.key("https://lh3.googleusercontent.com/abc=w544-h544-l90-rj"), "lh3.googleusercontent.com/abc")
    }

    func testOneAlbumAndThreeOthersGiveFourDistinct() {
        // Arrange — 10 треков одного альбома + 3 других
        var list = (0..<10).map { track("https://c/alb-\($0).jpg", album: "ym:alb") }
        list.append(track("https://c/x.jpg", album: "ym:x"))
        list.append(track("https://c/y.jpg", album: "ym:y"))
        list.append(track("https://c/z.jpg", artist: "Z"))
        // Act
        let covers = Covers.collage(list)
        // Assert
        XCTAssertEqual(covers, ["https://c/alb-0.jpg", "https://c/x.jpg", "https://c/y.jpg", "https://c/z.jpg"])
    }

    func testSamePictureInOtherSizeIsRepeat() {
        let list = [track("https://c/a-t500x500.jpg", album: "sc:1"), track("https://c/a-large.jpg", album: "sc:2"),
                    track("https://c/b.jpg")]
        XCTAssertEqual(Covers.distinct(list), ["https://c/a-t500x500.jpg", "https://c/b.jpg"])
    }

    func testWithoutAlbumArtistPlusURL() {
        let list = [track("https://c/a.jpg"), track("https://c/a.jpg?v=2"), track("https://c/b.jpg")]
        XCTAssertEqual(Covers.distinct(list), ["https://c/a.jpg", "https://c/b.jpg"])
    }

    func testScansPastFirstThirtyTracks() {
        var list = (0..<40).map { _ in track("https://c/same.jpg", album: "alb") }
        list += ["1", "2", "3"].map { track("https://c/\($0).jpg") }
        XCTAssertEqual(Covers.collage(list).count, 4)
    }

    func testTwoOrThreeCollapseToFirstAndEmptyStaysEmpty() {
        let three = ["1", "2", "3"].map { track("https://c/\($0).jpg") }
        XCTAssertEqual(Covers.collage(three), ["https://c/1.jpg"])
        XCTAssertEqual(Covers.collage([track(nil)]), [])
        XCTAssertEqual(Covers.collage(three), Covers.collage(three), "порядок стабильный")
    }
}
