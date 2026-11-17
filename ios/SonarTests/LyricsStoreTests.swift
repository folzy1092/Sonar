import Foundation
import XCTest
@testable import Sonar

/// Источник текстов без сети: ответы задаются заранее, вызовы считаются.
final class FakeLyricsProvider: LyricsProviding, @unchecked Sendable {
    private let lock = NSLock()
    var byTitle: [String: Lyrics] = [:]
    var annotations: [LyricsAnnotation] = []
    var failFind = false
    var translation: (lines: [String], source: String)?
    private var counts: [String: Int] = [:]

    func calls(_ name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[name] ?? 0
    }

    private func hit(_ name: String) {
        lock.lock()
        counts[name, default: 0] += 1
        lock.unlock()
    }

    func find(_ query: LyricsQuery) async throws -> Lyrics? {
        hit("find")
        if failFind { throw LyricsSourceError(status: 503, message: "нет сети") }
        return byTitle[query.title]
    }

    func annotations(_ query: LyricsQuery) async throws -> [LyricsAnnotation] {
        hit("annotations")
        return annotations
    }

    func translate(_ lines: [String], to language: String) async throws -> (lines: [String], source: String) {
        hit("translate")
        guard let translation else { throw LyricsSourceError(status: 500, message: "нет") }
        return translation
    }
}

@MainActor
final class LyricsStoreTests: XCTestCase {
    private func sample(_ texts: [String] = ["Раз", "", "Два"]) -> Lyrics {
        Lyrics(lines: texts.enumerated().map { i, t in LyricLine(id: 0, start: Double(i), end: Double(i + 1), text: t, words: []) },
               synced: true, source: "lrclib")
    }

    private func makeStore(_ provider: FakeLyricsProvider, dir: URL, liked: Set<String> = []) -> LyricsStore {
        let settings = SettingsStore(storage: UserDefaults(suiteName: "lyrics-\(UUID().uuidString)")!)
        return LyricsStore(provider: provider, cache: LyricsCache(directory: dir.appendingPathComponent("cache")),
                           offsetsFile: dir.appendingPathComponent("offsets.json"), settings: settings, isLiked: { liked.contains($0) })
    }

    func testLoadUsesMemoryThenCache() async {
        let dir = tempDirectory()
        let provider = FakeLyricsProvider()
        provider.byTitle["Song sc:1"] = sample()
        let track = makeTrack("sc:1", "A")
        let store = makeStore(provider, dir: dir)
        await store.load(for: track)
        XCTAssertEqual(store.trackRef, "sc:1")
        XCTAssertEqual(store.lyrics?.lines.map(\.text), ["Раз", "", "Два"])
        XCTAssertFalse(store.loading)
        XCTAssertNil(store.failed)
        await store.load(for: track) // тот же трек — из памяти
        XCTAssertEqual(provider.calls("find"), 1)

        // новый запуск: память пустая, текст — из кэша на телефоне
        let again = makeStore(provider, dir: dir)
        await again.load(for: track)
        XCTAssertEqual(again.lyrics, store.lyrics)
        XCTAssertEqual(provider.calls("find"), 1)

        // «Найти заново» — мимо кэша
        provider.byTitle["Song sc:1"] = sample(["Новый"])
        await again.reload(for: track)
        XCTAssertEqual(again.lyrics?.lines.map(\.text), ["Новый"])
        XCTAssertEqual(provider.calls("find"), 2)
    }

    func testNotFoundIsCachedButErrorsAreNot() async {
        let dir = tempDirectory()
        let provider = FakeLyricsProvider()
        let track = makeTrack("ym:5", "B")
        let store = makeStore(provider, dir: dir)
        await store.load(for: track)
        XCTAssertNil(store.lyrics)
        XCTAssertEqual(store.failed, "Текст не найден")
        let again = makeStore(provider, dir: dir)
        await again.load(for: track)
        XCTAssertEqual(again.failed, "Текст не найден")
        XCTAssertEqual(provider.calls("find"), 1, "«не найдено» свежее — в сеть не идём")

        let other = makeTrack("ym:6", "B")
        provider.failFind = true
        await again.load(for: other)
        XCTAssertEqual(again.failed, "Текст не найден")
        provider.failFind = false
        provider.byTitle["Song ym:6"] = sample()
        let third = makeStore(provider, dir: dir)
        await third.load(for: other)
        XCTAssertNotNil(third.lyrics, "сбой сети не кэшируется")
    }

    func testCacheRecheckAndPrune() {
        let dir = tempDirectory()
        let cache = LyricsCache(directory: dir)
        let now = Date()
        cache.put("sc:none", nil, now: now.addingTimeInterval(-31 * 60))
        XCTAssertTrue(cache.lookup("sc:none", now: now) == nil, "устаревшее «нет» — снова в сеть")
        cache.put("sc:fresh-none", nil, now: now)
        guard case .some(.none) = cache.lookup("sc:fresh-none", now: now) else { return XCTFail("свежее «нет» — из кэша") }

        let day: TimeInterval = 86_400
        cache.put("sc:old", sample(), now: now.addingTimeInterval(-8 * day))
        cache.put("sc:liked", sample(), now: now.addingTimeInterval(-8 * day))
        cache.put("sc:ancient", sample(), now: now.addingTimeInterval(-15 * day))
        cache.put("sc:fresh", sample(), now: now)
        let removed = cache.prune(now: now, isLiked: { $0 == "sc:liked" || $0 == "sc:ancient" })
        XCTAssertEqual(removed, 2)
        XCTAssertNil(cache.get("sc:old"))
        XCTAssertNil(cache.get("sc:ancient"))
        XCTAssertNotNil(cache.get("sc:liked"))
        XCTAssertNotNil(cache.get("sc:fresh"))
    }

    func testShowingExtendsCacheLife() {
        let dir = tempDirectory()
        let cache = LyricsCache(directory: dir)
        let now = Date()
        cache.put("sc:1", sample(), now: now.addingTimeInterval(-6 * 86_400))
        _ = cache.lookup("sc:1", now: now) // показ продлевает срок
        XCTAssertEqual(cache.prune(now: now.addingTimeInterval(3 * 86_400), isLiked: { _ in false }), 0)
        XCTAssertEqual(cache.file(for: "sc:1").lastPathComponent, "sc%3A1.json")
    }

    func testOffsetsPersist() {
        let dir = tempDirectory()
        let provider = FakeLyricsProvider()
        let store = makeStore(provider, dir: dir)
        XCTAssertEqual(store.offset(for: "sc:1"), 0)
        store.setOffset(0.25, for: "sc:1")
        store.setOffset(99, for: "sc:2")
        XCTAssertEqual(store.offset(for: "sc:1"), 0.25)
        XCTAssertEqual(store.offset(for: "sc:2"), 15)
        let again = makeStore(provider, dir: dir)
        XCTAssertEqual(again.offset(for: "sc:1"), 0.25)
        again.setOffset(0, for: "sc:1")
        XCTAssertNil(again.offsets["sc:1"], "0 — запись удаляется")
    }

    func testTranslationAndNotes() async throws {
        let dir = tempDirectory()
        let provider = FakeLyricsProvider()
        provider.byTitle["Song sc:1"] = sample(["One", "", "Two"])
        provider.translation = (["Один", "", "Два"], "en")
        provider.annotations = [LyricsAnnotation(lines: ["Two"], body: "про два", reviewed: true)]
        let store = makeStore(provider, dir: dir)
        await store.load(for: makeTrack("sc:1", "A"))
        await store.translate(to: "ru")
        XCTAssertEqual(store.translation, [0: "Один", 2: "Два"])
        XCTAssertEqual(store.translationLanguage, "ru")
        XCTAssertFalse(store.translating)

        // аннотации грузятся в фоне
        for _ in 0 ..< 50 where store.notes.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(store.notes[2]?.body, "про два")

        // следующий трек переводится сам, язык тот же — «уже на этом языке» без сообщения
        provider.byTitle["Song sc:2"] = sample(["Раз"])
        provider.translation = (["Раз"], "ru")
        await store.load(for: makeTrack("sc:2", "A"))
        XCTAssertEqual(store.translation, [:])
        XCTAssertNil(store.translationMessage)
        await store.translate(to: "ru")
        XCTAssertEqual(store.translationMessage, "Текст уже на этом языке")

        store.clearTranslation()
        XCTAssertNil(store.translationLanguage)
        provider.translation = nil
        await store.translate(to: "en")
        XCTAssertEqual(store.translationMessage, "Перевод не удался — попробуй позже")
        XCTAssertNotNil(store.lyrics, "ошибка перевода текст не прячет")
    }

    func testViewSettings() {
        let store = makeStore(FakeLyricsProvider(), dir: tempDirectory())
        XCTAssertEqual(store.mode, .words)
        XCTAssertEqual(store.size, .l)
        XCTAssertEqual(store.style, .blur)
        XCTAssertEqual(store.animation, .normal)
        store.animation = .ladder
        store.size = .xl
        XCTAssertEqual(store.animation, .ladder)
        XCTAssertEqual(store.size, .xl)
    }
}
