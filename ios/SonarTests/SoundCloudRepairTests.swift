import XCTest
@testable import Sonar

/// Починка ключей SoundCloud после 401 (`Core/Providers/SoundCloudRepair.swift`, docs/POLISH_PROMPT.md п. 8) —
/// те же случаи, что `services/sc_repair.rs` на ПК.
final class SoundCloudRepairTests: XCTestCase {
    private actor Seen {
        var calls: [String] = []
        func add(_ value: String) { calls.append(value) }
    }

    private struct NoToken: Error {}

    private static let unauthorized = ServiceError(message: "SoundCloud: HTTP 401")

    private func creds(_ id: String, _ token: String?) -> SoundCloudCreds {
        SoundCloudCreds(clientId: id, oauthToken: token)
    }

    /// Запрос проходит только с этими id и токеном; все попытки записываются.
    private func server(_ okId: String, _ okToken: String, _ seen: Seen) -> @Sendable (SoundCloudCreds) async throws -> Int {
        { creds in
            let token = creds.oauthToken ?? ""
            await seen.add("\(creds.clientId)/\(token)")
            guard creds.clientId == okId, token == okToken else { throw Self.unauthorized }
            return 7
        }
    }

    func testNewClientIdIsEnough() async throws {
        let seen = Seen()
        let out = await SoundCloudRepair.repair(old: creds("old", "tok"), error: Self.unauthorized,
                                                call: server("new", "tok", seen),
                                                freshId: { "new" }, relogin: { _ in XCTFail("тихий вход не нужен"); return nil })
        XCTAssertEqual(try out.result.get(), 7)
        XCTAssertEqual(out.save?.creds.clientId, "new")
        XCTAssertEqual(out.save?.fix, .clientId)
        XCTAssertFalse(out.relogin)
        let calls = await seen.calls
        XCTAssertEqual(calls, ["new/tok"])
    }

    func testFallsBackToSilentReloginWithNewId() async throws {
        let seen = Seen()
        let out = await SoundCloudRepair.repair(old: creds("old", "tok"), error: Self.unauthorized,
                                                call: server("new", "fresh", seen),
                                                freshId: { "new" }, relogin: { _ in "fresh" })
        XCTAssertEqual(try out.result.get(), 7)
        XCTAssertEqual(out.save?.creds, creds("new", "fresh"))
        XCTAssertEqual(out.save?.fix, .token)
        let calls = await seen.calls
        XCTAssertEqual(calls, ["new/tok", "new/fresh"])
    }

    func testSameIdOnSiteGoesStraightToRelogin() async throws {
        let seen = Seen()
        let out = await SoundCloudRepair.repair(old: creds("old", "tok"), error: Self.unauthorized,
                                                call: server("old", "fresh", seen),
                                                freshId: { "old" }, relogin: { old in old == "tok" ? "fresh" : nil })
        XCTAssertEqual(try out.result.get(), 7)
        let calls = await seen.calls
        XCTAssertEqual(calls, ["old/fresh"])
    }

    func testNothingHelpsAsksToLogInAgain() async {
        let seen = Seen()
        // тихий вход вернул тот же токен — повторять нечего
        let out = await SoundCloudRepair.repair(old: creds("old", "tok"), error: Self.unauthorized,
                                                call: server("x", "y", seen),
                                                freshId: { "new" }, relogin: { _ in "tok" })
        XCTAssertTrue(out.relogin)
        XCTAssertNil(out.save)
        XCTAssertThrowsError(try out.result.get()) { error in
            XCTAssertTrue((error as? ServiceError)?.message.contains("войди в SoundCloud заново") == true)
        }
        let calls = await seen.calls
        XCTAssertEqual(calls, ["new/tok"])
    }

    func testSiteUnreachableAndNoTokenKeepsOriginalError() async {
        let seen = Seen()
        let out = await SoundCloudRepair.repair(old: creds("own", nil), error: Self.unauthorized,
                                                call: server("x", "y", seen),
                                                freshId: { throw NoToken() },
                                                relogin: { _ in XCTFail("без токена входить нечем"); return nil })
        XCTAssertFalse(out.relogin)
        XCTAssertNil(out.save)
        XCTAssertTrue(MusicCore.isAuthError(out.result.failure ?? NoToken()))
        let calls = await seen.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testOtherErrorWithNewIdStillSavesIt() async {
        // 404 на новом id: ключ подошёл, просто трека нет — id сохраняем, ошибку отдаём
        let out = await SoundCloudRepair.repair(old: creds("old", "tok"), error: Self.unauthorized,
                                                call: { creds -> Int in
                                                    throw creds.clientId == "new" ? ServiceError(message: "SoundCloud: HTTP 404") : Self.unauthorized
                                                },
                                                freshId: { "new" }, relogin: { _ in nil })
        XCTAssertEqual((out.result.failure as? ServiceError)?.message, "SoundCloud: HTTP 404")
        XCTAssertEqual(out.save?.fix, .clientId)
    }

    func testJournalLinesCarryNoValues() {
        for line in [SoundCloudRepair.Fix.clientId.journal, SoundCloudRepair.Fix.token.journal, SoundCloudRepair.journalRelogin,
                     SoundCloudRepair.journalDeferred] {
            XCTAssertTrue(line.hasPrefix("SoundCloud: 401"))
        }
    }

    func testBannerStringsAreTranslated() {
        for key in ["Войди в SoundCloud заново", "Войти заново", "SoundCloud снова подключён", "Вход устарел"] {
            XCTAssertNotEqual(I18n.translate(key, lang: .en), key)
            XCTAssertNotEqual(I18n.translate(key, lang: .uk), key)
        }
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
