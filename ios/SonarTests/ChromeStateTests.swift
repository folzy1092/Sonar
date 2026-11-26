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
        XCTAssertNil(DeepLink(URL(string: "https://try-sonar.ru")!))
    }
}

final class TabTapTests: XCTestCase {
    func testOtherTabIsSelected() {
        XCTAssertEqual(TabTap.of(.library, current: .home, collapsed: false), .select)
        XCTAssertEqual(TabTap.of(.search, current: .profile, collapsed: true), .select)
    }

    func testCurrentTabGoesToTop() {
        XCTAssertEqual(TabTap.of(.profile, current: .profile, collapsed: false), .toTop)
    }

    func testCollapsedCircleGoesToTopWithoutExpanding() {
        for tab in Tab.allCases {
            XCTAssertEqual(TabTap.of(tab, current: tab, collapsed: true), .toTopCollapsed,
                           "левый круг свёрнутой панели ведёт к началу вкладки, панель не разворачивает")
        }
    }
}

@MainActor
final class ChromeExpandTests: XCTestCase {
    func testExpandButtonDoesNotRecollapseAtOnce() {
        let chrome = ChromeState()
        chrome.scrolled(to: 300)
        XCTAssertTrue(chrome.collapsed)
        chrome.expand()
        chrome.scrolled(to: 302)
        chrome.scrolled(to: 310)
        XCTAssertFalse(chrome.collapsed, "после разворота кнопкой мелкая прокрутка не сворачивает")
        chrome.scrolled(to: 340)
        XCTAssertTrue(chrome.collapsed)
        chrome.select(.library)
        XCTAssertFalse(chrome.collapsed)
        XCTAssertEqual(chrome.tab, .library)
    }
}

@MainActor
final class ChromeHoldTests: XCTestCase {
    func testScrollToTopKeepsBarCollapsed() {
        let chrome = ChromeState()
        chrome.scrolled(to: 800)
        XCTAssertTrue(chrome.collapsed)
        chrome.holdCollapsed()
        for offset in stride(from: CGFloat(700), through: 0, by: -100) { chrome.scrolled(to: offset) }
        XCTAssertTrue(chrome.collapsed, "экран сам доехал до начала — панель осталась свёрнутой")
    }

    func testFingerReleasesHold() {
        let chrome = ChromeState()
        chrome.scrolled(to: 800)
        chrome.holdCollapsed()
        chrome.scrolled(to: 0)
        chrome.scrolled(to: 10)
        chrome.scrolled(to: 40)
        XCTAssertTrue(chrome.collapsed, "палец повёл вниз — панель свёрнута, дальше обычные правила")
        chrome.scrolled(to: 10)
        XCTAssertFalse(chrome.collapsed, "вверх больше порога — развернулась")
    }

    func testPullAtTopExpands() {
        let chrome = ChromeState()
        chrome.scrolled(to: 800)
        chrome.holdCollapsed()
        chrome.scrolled(to: 0)
        chrome.scrolled(to: -20)
        XCTAssertFalse(chrome.collapsed, "потянули за верх — разворачиваем")
    }

    func testHoldNeedsCollapsedBar() {
        let chrome = ChromeState()
        chrome.holdCollapsed()
        chrome.scrolled(to: 100)
        XCTAssertTrue(chrome.collapsed, "развёрнутую панель удержание не трогает — обычная прокрутка сворачивает")
    }
}
