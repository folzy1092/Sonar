import XCTest
@testable import Sonar

final class ServiceCheckTests: XCTestCase {
    private struct Boom: LocalizedError {
        var errorDescription: String? { "SoundCloud: 401" }
    }

    func testSuccessMarksOk() async {
        let result = await ServiceChecker.run(connected: [.ym]) { _ in }
        XCTAssertEqual(result.map(\.service), [.ym])
        XCTAssertTrue(result[0].ok)
        XCTAssertNil(result[0].error)
        XCTAssertFalse(result[0].timedOut)
    }

    func testErrorKeepsServiceText() async {
        let result = await ServiceChecker.run(connected: [.sc]) { _ in throw Boom() }
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].ok)
        XCTAssertEqual(result[0].error, "SoundCloud: 401")
        XCTAssertFalse(result[0].timedOut)
    }

    func testSlowServiceTimesOutWithoutWaiting() async {
        let clock = ContinuousClock()
        let started = clock.now
        let result = await ServiceChecker.run(connected: [.yt], timeout: .milliseconds(50)) { _ in
            try await Task.sleep(for: .seconds(30))
        }
        XCTAssertLessThan(clock.now - started, .seconds(5), "тайм-аут не должен ждать сам поиск")
        XCTAssertFalse(result[0].ok)
        XCTAssertTrue(result[0].timedOut)
        XCTAssertNil(result[0].error)
        XCTAssertGreaterThanOrEqual(result[0].ms, 50)
    }

    func testNothingConnectedChecksNothing() async {
        let calls = Counter()
        let result = await ServiceChecker.run(connected: []) { _ in await calls.bump() }
        XCTAssertTrue(result.isEmpty)
        let count = await calls.value
        XCTAssertEqual(count, 0)
    }

    func testOrderFollowsRegistryNotAnswers() async {
        // Яндекс отвечает последним, SoundCloud — первым, а список всё равно в порядке реестра.
        let connected: Set<ServiceID> = [.sp, .ym, .sc, .vk]
        let result = await ServiceChecker.run(connected: connected) { id in
            let delay: [ServiceID: Int] = [.sc: 0, .vk: 10, .sp: 20, .ym: 40]
            try await Task.sleep(for: .milliseconds(delay[id] ?? 0))
        }
        let expected = ServiceRegistry.implemented.map(\.id).filter(connected.contains)
        XCTAssertEqual(result.map(\.service), expected)
        XCTAssertEqual(result.map(\.service), [.sc, .ym, .vk, .sp])
    }

    func testServicesRunInParallel() async {
        let clock = ContinuousClock()
        let started = clock.now
        _ = await ServiceChecker.run(connected: [.sc, .ym, .yt, .vk]) { _ in
            try await Task.sleep(for: .milliseconds(300))
        }
        XCTAssertLessThan(clock.now - started, .milliseconds(1000), "четыре по 300 мс — параллельно, не 1.2 с")
    }

    func testSecondsFormatLikeDesktop() {
        XCTAssertEqual(ServiceChecker.seconds(420), "0.4")
        XCTAssertEqual(ServiceChecker.seconds(1500), "1.5")
        XCTAssertEqual(ServiceChecker.seconds(15000), "15.0")
    }

    private actor Counter {
        var value = 0
        func bump() { value += 1 }
    }
}
