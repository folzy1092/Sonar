import XCTest
@testable import Sonar

/// Входы в сервисы на всех устройствах — те же случаи, что в `cred_sync.rs` ПК.
final class CredentialSyncTests: XCTestCase {
    private let sc: CredentialSync.Fields = ["client_id": "abc"]
    private let sc2: CredentialSync.Fields = ["client_id": "xyz"]
    private let ym: CredentialSync.Fields = ["token": "y0_a"]

    private func h(_ f: CredentialSync.Fields) -> String { CredentialSync.hash(f) }

    func testHashIgnoresKeyOrderAndDiffersByValue() {
        XCTAssertEqual(h(["a": "1", "b": "2"]), h(["b": "2", "a": "1"]))
        XCTAssertNotEqual(h(sc), h(sc2))
    }

    func testFirstExchangeMineWinsAndRestComesFromServer() {
        let steps = CredentialSync.plan(local: ["soundcloud": sc], remote: ["soundcloud": sc2, "yandex": ym], base: [:])
        XCTAssertEqual(steps, [.push("soundcloud"), .apply("yandex")])
    }

    func testSameOnBothSidesDoesNothing() {
        XCTAssertEqual(CredentialSync.plan(local: ["soundcloud": sc], remote: ["soundcloud": sc], base: [:]), [])
    }

    func testServerChangedAndMineDidNot() {
        let steps = CredentialSync.plan(local: ["soundcloud": sc], remote: ["soundcloud": sc2], base: ["soundcloud": h(sc)])
        XCTAssertEqual(steps, [.apply("soundcloud")])
    }

    func testMineChangedAndServerDidNot() {
        let steps = CredentialSync.plan(local: ["soundcloud": sc2], remote: ["soundcloud": sc], base: ["soundcloud": h(sc)])
        XCTAssertEqual(steps, [.push("soundcloud")])
    }

    func testDisconnectedElsewhereForgetsHere() {
        XCTAssertEqual(CredentialSync.plan(local: ["yandex": ym], remote: [:], base: ["yandex": h(ym)]), [.forget("yandex")])
        // базы нет — это новый вход здесь, а не отключение там
        XCTAssertEqual(CredentialSync.plan(local: ["yandex": ym], remote: [:], base: [:]), [.push("yandex")])
    }

    func testDisconnectedHereDeletesOnServer() {
        XCTAssertEqual(CredentialSync.plan(local: [:], remote: ["yandex": ym], base: ["yandex": h(ym)]), [.delete("yandex")])
        XCTAssertEqual(CredentialSync.plan(local: [:], remote: ["yandex": ym], base: [:]), [.apply("yandex")])
    }

    func testNextBase() {
        let local = ["soundcloud": sc, "yandex": ym]
        let remote = ["soundcloud": sc2, "youtube": ["cookie": "c"]]
        let steps: [CredentialSync.Step] = [.push("soundcloud"), .forget("yandex"), .apply("youtube")]
        let ok = CredentialSync.nextBase(local: local, remote: remote, old: [:], steps: steps, failed: [])
        XCTAssertEqual(ok, ["soundcloud": h(sc), "youtube": h(["cookie": "c"])])
        let failed = CredentialSync.nextBase(local: local, remote: remote, old: ["youtube": "old"], steps: steps, failed: ["youtube"])
        XCTAssertEqual(failed["youtube"], "old", "не вошли — база прежняя")
    }

    func testSkippedFailedApplyNeverTurnsIntoDelete() {
        let sp: CredentialSync.Fields = ["sp_dc": "bad"]
        let next = CredentialSync.nextBase(local: [:], remote: ["spotify": sp], old: [:], steps: [], failed: ["spotify"])
        XCTAssertNil(next["spotify"])
        XCTAssertEqual(CredentialSync.plan(local: [:], remote: ["spotify": sp], base: next), [.apply("spotify")])
    }

    func testFailedApplyWithOwnKeyPushesOwnNextTime() {
        let local = ["soundcloud": sc], remote = ["soundcloud": sc2], old = ["soundcloud": h(sc)]
        let steps = CredentialSync.plan(local: local, remote: remote, base: old)
        XCTAssertEqual(steps, [.apply("soundcloud")])
        let next = CredentialSync.nextBase(local: local, remote: remote, old: old, steps: steps, failed: ["soundcloud"])
        XCTAssertEqual(CredentialSync.plan(local: local, remote: remote, base: next), [.push("soundcloud")])
    }

    func testPushBodyAddsNameAndNullForDelete() throws {
        let body = CredentialSync.pushBody(steps: [.push("soundcloud"), .delete("yandex"), .apply("youtube")],
                                           local: ["soundcloud": .init(fields: sc, name: "Folzy")])
        let json = try JSONValue(data: JSONEncoder().encode(body))
        XCTAssertEqual(json, .object(["soundcloud": .object(["client_id": .string("abc"), "name": .string("Folzy")]),
                                      "yandex": .null]))
    }

    func testCleanTrimsAndDropsEmpty() {
        XCTAssertEqual(CredentialSync.clean(["client_id": " abc ", "oauth_token": nil, "x": "  "]), ["client_id": "abc"])
    }

    func testUnknownServicesDropped() {
        XCTAssertEqual(CredentialSync.known(["vk": ["token": "1"], "yandex": ym]), ["yandex": ym])
    }
}

/// Подставные ключи сервисов.
private actor FakeHost: CredentialHost {
    var local: [String: CredentialSync.Local]
    var failing: Set<String> = []
    private(set) var applied: [String] = []
    private(set) var forgotten: [String] = []

    init(_ local: [String: CredentialSync.Local], failing: Set<String> = []) {
        self.local = local
        self.failing = failing
    }

    func snapshot() async -> [String: CredentialSync.Local] { local }

    func apply(_ service: String, _ fields: CredentialSync.Fields) async throws {
        applied.append(service)
        if failing.contains(service) { throw ServiceError(message: "нет") }
        local[service] = .init(fields: fields, name: nil)
    }

    func forget(_ service: String) async {
        forgotten.append(service)
        local[service] = nil
    }
}

final class CredentialSyncerTests: XCTestCase {
    private func vault() -> SessionVault {
        let v = SessionVault(secrets: MemorySecrets())
        v.secrets.set("tok", SessionVault.tokenAccount)
        return v
    }

    private func client(_ api: FakeAPI, token: String = "tok") -> APIClient {
        APIClient(base: URL(string: "https://try-sonar.ru/api")!, token: token, fetch: api.fetch)
    }

    func testRunPushesMineAppliesRemoteAndSavesBase() async throws {
        let api = FakeAPI()
        api.on("GET /services/credentials", 200, #"{"yandex":{"token":"y0_a"},"vk":{"token":"x"}}"#)
        api.on("PUT /services/credentials", 204, "")
        let host = FakeHost(["soundcloud": .init(fields: ["client_id": "abc"], name: "Folzy")])
        let syncer = CredentialSyncer(host: host)
        let v = vault()

        let changed = try await syncer.run(client: client(api), vault: v)

        XCTAssertTrue(changed)
        let applied = await host.applied
        XCTAssertEqual(applied, ["yandex"])
        XCTAssertEqual(api.body("PUT /services/credentials"),
                       .object(["soundcloud": .object(["client_id": .string("abc"), "name": .string("Folzy")])]))
        XCTAssertEqual(Set(v.credBase.keys), ["soundcloud", "yandex"])
    }

    func testSecondRunIsQuietAndFailedApplyIsNotRetried() async throws {
        let api = FakeAPI()
        api.on("GET /services/credentials", 200, #"{"spotify":{"sp_dc":"bad"}}"#)
        let host = FakeHost([:], failing: ["spotify"])
        let syncer = CredentialSyncer(host: host)
        let v = vault()

        let first = try await syncer.run(client: client(api), vault: v)
        let second = try await syncer.run(client: client(api), vault: v)

        XCTAssertFalse(first)
        XCTAssertFalse(second)
        let applied = await host.applied
        XCTAssertEqual(applied, ["spotify"], "протухший ключ пробуем один раз")
        XCTAssertEqual(api.count("PUT /services/credentials"), 0, "чужой протухший ключ не удаляем с сервера")
        XCTAssertNil(v.credBase["spotify"])
    }

    func testForgetWhenDisconnectedElsewhere() async throws {
        let api = FakeAPI()
        api.on("GET /services/credentials", 200, "{}")
        let ym: CredentialSync.Fields = ["token": "y0_a"]
        let host = FakeHost(["yandex": .init(fields: ym, name: nil)])
        let v = vault()
        v.credBase = ["yandex": CredentialSync.hash(ym)]

        let changed = try await CredentialSyncer(host: host).run(client: client(api), vault: v)

        XCTAssertTrue(changed)
        let forgotten = await host.forgotten
        XCTAssertEqual(forgotten, ["yandex"])
        XCTAssertEqual(v.credBase, [:])
    }

    func testBaseNotSavedAfterSignOut() async throws {
        let api = FakeAPI()
        api.on("GET /services/credentials", 200, #"{"yandex":{"token":"y0_a"}}"#)
        let v = vault()
        v.clear()

        _ = try await CredentialSyncer(host: FakeHost([:])).run(client: client(api), vault: v)

        XCTAssertEqual(v.credBase, [:])
    }

    func testVaultClearsBaseOnSignOut() {
        let v = vault()
        v.credBase = ["yandex": "h"]
        v.clear()
        XCTAssertEqual(v.credBase, [:])
    }
}
