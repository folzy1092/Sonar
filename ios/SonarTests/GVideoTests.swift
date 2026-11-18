import XCTest
@testable import Sonar

/// Скачивание YouTube Music кусками: те же правила, что `windows/src-tauri/src/gvideo.rs`.
final class GVideoTests: XCTestCase {
    func testRecognisesGoogleVideoHostsOnly() throws {
        XCTAssertTrue(GVideo.isGVideo(try XCTUnwrap(URL(string: "https://rr3---sn-abc.googlevideo.com/videoplayback?clen=5"))))
        XCTAssertFalse(GVideo.isGVideo(try XCTUnwrap(URL(string: "http://rr3---sn-abc.googlevideo.com/videoplayback"))))
        XCTAssertFalse(GVideo.isGVideo(try XCTUnwrap(URL(string: "https://googlevideo.com.evil.com/videoplayback"))))
        XCTAssertFalse(GVideo.isGVideo(try XCTUnwrap(URL(string: "https://strm.yandex.ru/a.mp3"))))
    }

    func testContentLengthFromClen() throws {
        let url = try XCTUnwrap(URL(string: "https://rr1---sn-x.googlevideo.com/videoplayback?itag=140&clen=5242881&mime=audio%2Fmp4"))
        XCTAssertEqual(GVideo.contentLength(url), 5_242_881)
        XCTAssertNil(GVideo.contentLength(try XCTUnwrap(URL(string: "https://rr1---sn-x.googlevideo.com/videoplayback?itag=140"))))
        XCTAssertNil(GVideo.contentLength(try XCTUnwrap(URL(string: "https://rr1---sn-x.googlevideo.com/videoplayback?clen=0"))))
        XCTAssertNil(GVideo.contentLength(try XCTUnwrap(URL(string: "https://rr1---sn-x.googlevideo.com/videoplayback?clen=abc"))))
    }

    func testSpansCoverWholeFileWithoutGaps() {
        let mb: Int64 = 1024 * 1024
        let spans = GVideo.spans(total: 20 * mb)
        XCTAssertEqual(spans, [0 ... 8 * mb - 1, 8 * mb ... 16 * mb - 1, 16 * mb ... 20 * mb - 1])
        XCTAssertEqual(spans.map(GVideo.length).reduce(0, +), 20 * mb)
        XCTAssertEqual(GVideo.spans(total: 10, chunk: 5), [0 ... 4, 5 ... 9])
        XCTAssertEqual(GVideo.spans(total: 3, chunk: 5), [0 ... 2])
        XCTAssertEqual(GVideo.spans(total: 0), [])
    }

    func testRangeHeaderIsBounded() {
        XCTAssertEqual(GVideo.rangeHeader(0 ... 8_388_607), "bytes=0-8388607")
        XCTAssertEqual(GVideo.rangeHeader(16 ... 16), "bytes=16-16")
    }
}
