import Foundation

/// Журнал синка на телефоне. На ПК каждая строка SQLite сама несёт `rev`; на iPhone данные лежат в JSON
/// хранилищ (`LibraryStore`, `SettingsStore`…), поэтому журнал держит рядом последнее известное значение
/// каждой строки и её `rev`. `scan` сравнивает снимок хранилищ с журналом: новое или изменённое получает
/// свежий `rev` (как `next_rev()` на ПК), пропавшее — tombstone `.null`.
///
/// «Не отправлено» = `rev > pushedRev`. Пришедшее с сервера пишется с `rev = 0` — обратно не поедет.
/// Строки, которые телефон хранить не умеет (настройки-объекты ПК, альбомы в лайках; элемент плейлиста, пока сам
/// плейлист не пришёл),
/// лежат здесь же с `foreign = true`: не теряются и не превращаются в удаление.
struct SyncJournal: Codable, Equatable, Sendable {
    struct Row: Codable, Equatable, Sendable {
        var value: JSONValue
        var rev: Int
        var ts: Int64
        var foreign = false
    }

    private(set) var rows: [SyncKey: Row] = [:]
    /// Глобальный локальный счётчик (`sync_rev` на ПК).
    private(set) var rev = 0
    /// Всё до этого rev отправлено.
    private(set) var pushedRev = 0
    /// До какого серверного rev уже получено (`GET /sync/pull?since=`).
    var pulledRev = 0
    /// Прослушивания до этого момента (мс) уже ушли в `POST /plays`.
    var playsUploadedAt: Int64 = 0
    /// С кем идёт обмен (`SyncTarget.tag`: сервер или ПК по Wi‑Fi). `nil` — журнал до синка по Wi‑Fi, был только сервер.
    private(set) var target: String?

    enum CodingKeys: String, CodingKey {
        case rows, rev, pushedRev, pulledRev, playsUploadedAt, target
    }

    init() {}

    // словарь с ключом-структурой JSON пишет массивом пар — пишем списком строк
    private struct StoredRow: Codable {
        var t: String
        var k: String
        var row: Row
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = try c.decodeIfPresent([StoredRow].self, forKey: .rows) ?? []
        rows = Dictionary(list.map { (SyncKey($0.t, $0.k), $0.row) }, uniquingKeysWith: { _, b in b })
        rev = try c.decodeIfPresent(Int.self, forKey: .rev) ?? 0
        pushedRev = try c.decodeIfPresent(Int.self, forKey: .pushedRev) ?? 0
        pulledRev = try c.decodeIfPresent(Int.self, forKey: .pulledRev) ?? 0
        playsUploadedAt = try c.decodeIfPresent(Int64.self, forKey: .playsUploadedAt) ?? 0
        target = try c.decodeIfPresent(String.self, forKey: .target)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rows.sorted { $0.key < $1.key }.map { StoredRow(t: $0.key.type, k: $0.key.key, row: $0.value) }, forKey: .rows)
        try c.encode(rev, forKey: .rev)
        try c.encode(pushedRev, forKey: .pushedRev)
        try c.encode(pulledRev, forKey: .pulledRev)
        try c.encode(playsUploadedAt, forKey: .playsUploadedAt)
        try c.encodeIfPresent(target, forKey: .target)
    }

    /// Сменить сторону обмена. Новая не видела ни нашего `pushedRev`, ни своего `rev` — отправляем всё
    /// заново и забираем всё её (повтор безопасен: сторона узнаёт значение). Строки с `rev = 0` — пришедшие
    /// и наше же эхо от прежней стороны — получают свежий `rev`, иначе сброс `pushedRev` их не поднимет
    /// (как `Store::sync_target` на ПК). Прослушивания не трогаем — ПК их не берёт, метка `playsUploadedAt`
    /// только про сервер. Вернёт, сменилась ли сторона.
    @discardableResult
    mutating func use(target tag: String) -> Bool {
        if (target ?? "server") == tag {
            target = tag
            return false
        }
        target = tag
        for key in rows.keys.sorted() where rows[key]?.rev == 0 {
            rev += 1
            rows[key]?.rev = rev
        }
        pushedRev = 0
        pulledRev = 0
        return true
    }

    // MARK: чтение

    func value(_ key: SyncKey) -> JSONValue? {
        rows[key].map(\.value)
    }

    func value(_ type: String, _ key: String) -> JSONValue? {
        value(SyncKey(type, key))
    }

    /// Есть ли у строки своё неотправленное изменение.
    func isPending(_ key: SyncKey) -> Bool {
        (rows[key]?.rev ?? 0) > pushedRev
    }

    var pendingCount: Int {
        rows.values.filter { $0.rev > pushedRev }.count
    }

    // MARK: свои изменения

    /// Сверить снимок хранилищ с журналом для типов `types`. Вернёт, сколько строк изменилось.
    @discardableResult
    mutating func record(_ snapshot: [SyncKey: JSONValue], types: Set<String>, now: Int64) -> Int {
        var changed = 0
        for (key, value) in snapshot.sorted(by: { $0.key < $1.key }) where types.contains(key.type) {
            if let row = rows[key], row.value == value, !row.foreign { continue }
            if let row = rows[key], row.value == value, row.foreign {
                // своё совпало с пришедшим — теперь строка наша, отправлять нечего
                rows[key]?.foreign = false
                continue
            }
            rev += 1
            rows[key] = Row(value: value, rev: rev, ts: now)
            changed += 1
        }
        for (key, row) in rows.sorted(by: { $0.key < $1.key })
        where types.contains(key.type) && !row.foreign && !row.value.isNull && snapshot[key] == nil {
            rev += 1
            rows[key] = Row(value: .null, rev: rev, ts: now)
            changed += 1
        }
        return changed
    }

    /// Неотправленное, не больше `limit` операций.
    func pendingOps(deviceId: String, limit: Int) -> PushPlan {
        var ops = rows.compactMap { key, row -> SyncOp? in
            guard row.rev > pushedRev else { return nil }
            return SyncOp(opId: "\(deviceId):\(key.type):\(key.key):\(row.rev)", type: key.type, key: key.key,
                          value: row.value, clientTs: row.ts, rev: row.rev)
        }
        ops.sort { $0.rev < $1.rev }
        var upto = ops.last?.rev ?? max(pushedRev, rev)
        if ops.count > limit {
            upto = ops[limit].rev - 1
            ops = Array(ops.prefix(limit))
        }
        return PushPlan(ops: ops, upto: upto)
    }

    /// Сервер принял отправку — всё до `upto` отправлено.
    mutating func markPushed(_ upto: Int) {
        if upto > pushedRev { pushedRev = upto }
    }

    // MARK: пришедшее

    /// Записать пришедшее с сервера (`rev = 0` — уже на сервере).
    mutating func store(_ key: SyncKey, value: JSONValue, foreign: Bool, now: Int64) {
        rows[key] = Row(value: value, rev: 0, ts: now, foreign: foreign)
    }

    /// Хранилище приняло пришедшую строку позже (`SyncAdapter.finishApply`): она больше не «чужая».
    mutating func adopt(_ key: SyncKey) {
        rows[key]?.foreign = false
    }

    /// После применения: значение, каким его теперь видит хранилище (чтобы `scan` не принял его за своё).
    mutating func settle(_ key: SyncKey, value: JSONValue?) {
        guard var row = rows[key], row.rev <= pushedRev else { return }
        row.value = value ?? .null
        rows[key] = row
    }

    /// Выход из аккаунта: другой аккаунт начнёт с чистого слияния. Данные на телефоне не трогаются.
    mutating func reset() {
        self = SyncJournal()
    }
}
