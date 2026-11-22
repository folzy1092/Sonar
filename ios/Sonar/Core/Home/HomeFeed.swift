import Foundation
import Observation

/// Подборки Главной на телефоне (до сервера — без него, как Windows `home-data.svelte.ts` и
/// `commands.rs` `home_releases`):
/// - «Для вас» — похожее на Любимые и недавнее от привычных артистов и их популярное;
/// - «Открытия» — похожее, но от артистов, которых нет ни в Любимых, ни в истории;
/// - «Релизы» — свежие альбомы и синглы артистов из Любимых (мало — новинки Яндекса).
/// Без 👎 и недоступных. Кэш — JSON в Application Support, сеть — не чаще раза в 6 ч (или force).
@MainActor
@Observable
final class HomeFeed {
    static let ttl: TimeInterval = 6 * 3600

    /// «Для вас».
    var forYou: [Track] { snapshot.forYou.filter { !library.isDisliked($0.ref) } }
    /// «Открытия».
    var discoveries: [Track] { snapshot.discoveries.filter { !library.isDisliked($0.ref) } }
    /// Почему трек в «Открытиях»: «Похоже на <исполнители затравок>»; нет причины — пусто.
    func reason(for ref: String) -> String {
        guard let seeds = snapshot.reasons[ref], !seeds.isEmpty else { return "" }
        return t("Похоже на {list}", ["list": seeds.prefix(3).joined(separator: ", ")])
    }
    /// «Релизы», свежие первыми.
    var releases: [Album] { snapshot.releases }
    private(set) var loading = false
    /// Когда подборки обновлялись последний раз.
    var updatedAt: Date? { snapshot.at }

    private struct Snapshot: Codable {
        var forYou: [Track] = []
        var discoveries: [Track] = []
        var releases: [Album] = []
        /// «Открытия»: ref → исполнители затравок, которые его советуют.
        var reasons: [String: [String]] = [:]
        var at: Date?

        init(forYou: [Track] = [], discoveries: [Track] = [], releases: [Album] = [], reasons: [String: [String]] = [:], at: Date? = nil) {
            self.forYou = forYou
            self.discoveries = discoveries
            self.releases = releases
            self.reasons = reasons
            self.at = at
        }

        // старый home.json без reasons читается как есть
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            forYou = try c.decodeIfPresent([Track].self, forKey: .forYou) ?? []
            discoveries = try c.decodeIfPresent([Track].self, forKey: .discoveries) ?? []
            releases = try c.decodeIfPresent([Album].self, forKey: .releases) ?? []
            reasons = try c.decodeIfPresent([String: [String]].self, forKey: .reasons) ?? [:]
            at = try c.decodeIfPresent(Date.self, forKey: .at)
        }

        var isEmpty: Bool { forYou.isEmpty && discoveries.isEmpty && releases.isEmpty }
    }

    private var snapshot = Snapshot()
    @ObservationIgnored private let source: MusicSource
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let history: PlayHistory
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let random: () -> Double

    init(source: MusicSource, library: LibraryStore, history: PlayHistory, file: URL? = nil,
         now: @escaping () -> Date = Date.init, random: @escaping () -> Double = { Double.random(in: 0 ..< 1) }) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.source = source
        self.library = library
        self.history = history
        self.file = file ?? base.appendingPathComponent("Sonar/home.json")
        self.now = now
        self.random = random
        if let data = try? Data(contentsOf: self.file), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = saved
        }
    }

    /// Обновить подборки. Без force — только если кэш старше 6 ч или пуст. Нет ни Любимых, ни истории —
    /// пустые ряды (не ошибка). Сеть не ответила совсем — остаётся старое.
    func refresh(force: Bool = false) async {
        guard !loading else { return }
        if !force, let at = snapshot.at, now().timeIntervalSince(at) < Self.ttl, !snapshot.isEmpty { return }
        let liked = library.liked
        let recent = history.recent
        guard !liked.isEmpty || !recent.isEmpty else {
            snapshot = Snapshot(at: now())
            save()
            return
        }
        loading = true
        defer { loading = false }

        let seeds = HomeMath.seeds(liked: liked, recent: recent, random: random)
        let artists = WaveMath.favoriteArtistRefs(liked: liked, recent: recent, limit: 4)
        let releaseArtists = WaveMath.favoriteArtistRefs(liked: liked, recent: recent, limit: 12)
        let source = source
        async let similarLists = concurrentMap(seeds) { try await source.similar(to: $0, limit: 20) }
        async let topLists = concurrentMap(artists) { try await source.artistTop($0, limit: 10) }
        async let albumLists = concurrentMap(releaseArtists) { try await source.artistAlbums($0) }
        let (rawSimilar, tops, albums) = await (similarLists, topLists, albumLists)
        // хвост выдачи (перезаливы, треки на десяток прослушиваний) — не вкус, чистим до отбора
        let similar = rawSimilar.map { $0.map(HomeMath.cleanPool) }

        let answered = (similar + tops).contains { $0 != nil } || albums.contains { $0 != nil }
        guard answered else { return }

        var exclude = Set(liked.map(\.ref)).union(recent.map(\.ref))
        exclude.formUnion(library.disliked)
        // подпись затравки для «почему этот трек» — её исполнитель
        let byRef = Dictionary((liked + recent).map { ($0.ref, $0.mainArtistName) }, uniquingKeysWith: { first, _ in first })
        let answeredSeeds = zip(seeds, similar).compactMap { ref, list in list.map { _ in byRef[ref] ?? "" } }
        let split = HomeMath.split(similar: similar.compactMap { $0 }, tops: tops.compactMap { $0 },
                                   taste: history.taste(liked: liked), exclude: exclude, seedLabels: answeredSeeds)
        var fresh = HomeMath.freshReleases(albums.compactMap { $0 }.flatMap { $0.prefix(8) }, now: now())
        if fresh.count < 4, let more = try? await source.newReleases(limit: 16) {
            fresh = HomeMath.mergeReleases(fresh, more)
        }
        snapshot = Snapshot(forYou: split.forYou, discoveries: split.discoveries, releases: fresh, reasons: split.reasons, at: now())
        save()
    }

    /// «deadwilliam, gothviolence, lil peep…» — первые 3 уникальных артиста ряда.
    func subtitle(_ tracks: [Track]) -> String {
        HomeMath.subtitle(tracks)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// Чистая часть Главной — тесты гоняют на Linux.
enum HomeMath {
    static let rowLimit = 20
    /// Свежий релиз — не старше стольких дней.
    static let releaseDays = 90
    /// Незнакомые артисты SoundCloud с меньшим числом прослушиваний — случайные заливы, не «Открытия».
    static let minPlaysUnknown = 1000

    /// Сиды подборок: 4 случайных из 20 свежих Любимых и 2 последних из истории, без повторов.
    static func seeds(liked: [Track], recent: [Track], random: () -> Double) -> [String] {
        var out = WaveMath.sample(Array(liked.prefix(20).map(\.ref)), 4, random: random)
        for track in recent where out.count < 6 && !out.contains(track.ref) {
            out.append(track.ref)
            if out.count >= 6 { break }
        }
        return out
    }

    /// Списки по кругу: первый из каждого, второй из каждого…
    static func interleave(_ lists: [[Track]]) -> [Track] {
        let longest = lists.map(\.count).max() ?? 0
        var out: [Track] = []
        for i in 0 ..< longest {
            for list in lists where i < list.count { out.append(list[i]) }
        }
        return out
    }

    /// Похожее и популярное → «Для вас» (знакомые артисты, ≤ 2 трека на артиста) и «Открытия»
    /// (незнакомые, по одному треку на артиста). Без exclude, недоступных и повторов. В «Открытия» —
    /// только артисты, которых советуют хотя бы две затравки: одиночный совет SoundCloud — случайный трек
    /// жанра (как ПК `pickWithReasons` с `fill: false`). Мало — значит мало, без добора.
    /// `reasons` — ref «Открытия» → подписи затравок (`seedLabels`, по индексу списка `similar`).
    static func split(similar: [[Track]], tops: [[Track]], taste: Taste, exclude: Set<String>,
                      seedLabels: [String] = [],
                      limit: Int = rowLimit) -> (forYou: [Track], discoveries: [Track], reasons: [String: [String]]) {
        let pool = interleave(similar)
        // какие затравки (по индексу) советуют исполнителя
        var support: [String: Set<Int>] = [:]
        for (i, list) in similar.enumerated() {
            for track in list { for key in track.artistKeys where !key.isEmpty { support[key, default: []].insert(i) } }
        }
        func seedsOf(_ track: Track) -> [Int] {
            Array(track.artistKeys.reduce(into: Set<Int>()) { $0.formUnion(support[$1] ?? []) }).sorted()
        }
        let known = pool.filter { taste.isKnown($0) }
        let unknown = pool.filter { !taste.isKnown($0) && ($0.plays ?? Int.max) >= minPlaysUnknown && seedsOf($0).count >= 2 }
        var seen = exclude
        // не два трека артиста подряд: неподходящий ждёт следующего шанса, а не теряется
        func take(_ list: [Track], perArtist cap: Int) -> [Track] {
            var counts: [String: Int] = [:]
            var out: [Track] = []
            var pending: [Track] = []
            for track in list where track.available && !seen.contains(track.ref) {
                seen.insert(track.ref)
                pending.append(track)
                while out.count < limit, let i = pending.firstIndex(where: { t in
                    (counts[t.artistKey] ?? 0) < cap && out.last?.artistKey != t.artistKey
                }) {
                    let t = pending.remove(at: i)
                    counts[t.artistKey, default: 0] += 1
                    out.append(t)
                }
            }
            // что не встало, снова доступно другому ряду
            for track in pending { seen.remove(track.ref) }
            return out
        }
        let forYou = take(interleave([known, interleave(tops)]), perArtist: 2)
        let discoveries = take(unknown, perArtist: 1)
        var reasons: [String: [String]] = [:]
        for track in discoveries {
            var seen = Set<String>()
            let labels = seedsOf(track).compactMap { $0 < seedLabels.count ? seedLabels[$0] : nil }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            if !labels.isEmpty { reasons[track.ref] = labels }
        }
        return (forYou, discoveries, reasons)
    }

    /// Перезалив: то же название и длина в пределах этого — один трек разными аккаунтами.
    static let reuploadMs = 2000
    /// Ниже этой доли медианы прослушиваний выдачи (и ниже `minPlaysTail`) — хвост, а не похожее.
    static let tailMedianShare = 0.01
    static let minPlaysTail = 100

    /// Выдача похожего без хвоста (порт ПК `cleanSimilar(pool, 0)`): склеивает перезаливы (то же название
    /// без регистра и длина ±2 с) и выкидывает почти не слушанное — порог 1 % медианы, не меньше 100, но не
    /// выше самой медианы (нишевая выдача целиком остаётся). Треки без счётчика (Яндекс) не трогает.
    static func cleanPool(_ tracks: [Track]) -> [Track] {
        var kept: [Track] = []
        for track in tracks {
            let title = track.title.lowercased()
            let dup = track.durationMs > 0 && kept.contains {
                $0.durationMs > 0 && $0.title.lowercased() == title && abs($0.durationMs - track.durationMs) <= reuploadMs
            }
            if !dup { kept.append(track) }
        }
        let counted = kept.compactMap(\.plays).sorted()
        guard !counted.isEmpty else { return kept }
        let m = counted.count / 2
        let median = counted.count % 2 == 1 ? Double(counted[m]) : Double(counted[m - 1] + counted[m]) / 2
        let floor = min(median, max(Double(minPlaysTail), median * tailMedianShare))
        return kept.filter { track in
            guard let plays = track.plays else { return true }
            return Double(plays) >= floor
        }
    }

    /// Ключ сортировки релиза: `YYYY-MM-DD`, без даты — `YYYY-00-00`.
    static func releaseKey(_ album: Album) -> String {
        album.released ?? String(format: "%04d-00-00", album.year ?? 0)
    }

    static func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Свежие релизы: вышли за последние 90 дней (не в будущем), без точной даты — в этом году;
    /// без повторов (по ref и по «артист + название»), новые первыми, до 20.
    static func freshReleases(_ albums: [Album], now: Date, days: Int = releaseDays, limit: Int = rowLimit) -> [Album] {
        let today = dayString(now)
        let cutoff = dayString(now.addingTimeInterval(-Double(days) * 86_400))
        let year = Int(today.prefix(4)) ?? 0
        let fresh = albums.filter { album in
            if let released = album.released { return released >= cutoff && released <= today }
            return album.year == year
        }
        return mergeReleases(fresh.sorted { releaseKey($0) > releaseKey($1) }, [], limit: limit)
    }

    /// Склеить два списка релизов без повторов, порядок сохраняется.
    static func mergeReleases(_ first: [Album], _ second: [Album], limit: Int = rowLimit) -> [Album] {
        var refs = Set<String>()
        var names = Set<String>()
        var out: [Album] = []
        for album in first + second where out.count < limit {
            let name = "\(album.artist.lowercased())\u{1F}\(album.title.lowercased())"
            guard refs.insert(album.ref).inserted, names.insert(name).inserted else { continue }
            out.append(album)
        }
        return out
    }

    /// «deadwilliam, gothviolence, lil peep…»: первые 3 уникальных артиста (без учёта регистра),
    /// «…» — если артистов больше.
    static func subtitle(_ tracks: [Track], count: Int = 3) -> String {
        var keys = Set<String>()
        var names: [String] = []
        var more = false
        for track in tracks {
            let name = track.mainArtistName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, keys.insert(name.lowercased()).inserted else { continue }
            if names.count == count {
                more = true
                break
            }
            names.append(name)
        }
        return names.joined(separator: ", ") + (more ? "…" : "")
    }
}
