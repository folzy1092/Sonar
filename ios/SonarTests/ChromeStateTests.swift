import XCTest
@testable import Sonar

@MainActor
final class ChromeStateTests: XCTestCase {
    func testSmallScrollKeepsBarExpanded() {
        let chrome = ChromeState()
        chrome.scrolled(to: 10)
        chrome.scrolled(to: 20)
        XCTAssertFalse(chrome.collapsed)
    }

    func testScrollDownCollapsesAndUpExpands() {
        let chrome = ChromeState()
        chrome.scrolled(to: 30)
        XCTAssertTrue(chrome.collapsed)
        chrome.scrolled(to: 200)
        chrome.scrolled(to: 190)
        XCTAssertTrue(chrome.collapsed, "мелкий откат вверх не разворачивает")
        chrome.scrolled(to: 170)
        XCTAssertFalse(chrome.collapsed)
    }

    func testTopEdgeAlwaysExpands() {
        let chrome = ChromeState()
        chrome.scrolled(to: 100)
        chrome.scrolled(to: 0)
        XCTAssertFalse(chrome.collapsed)
    }

    func testDeepLinks() {
        XCTAssertEqual(DeepLink(URL(string: "sonar://track/sc:123")!), .track("sc:123"))
        XCTAssertEqual(DeepLink(URL(string: "sonar://user/folzy")!), .user("folzy"))
        XCTAssertNil(DeepLink(URL(string: "https://sonar.folzy.ru")!))
    }
}
