import Foundation

/// Что показывает карточка «Синхронизация» в Общих настройках: вошёл ли, идёт ли обмен, когда был последний и чем кончился.
enum SyncCardState: Equatable {
    case signedOut
    case syncing
    case failed(String)
    case never
    case done(Date)

    static func of(signedIn: Bool, syncing: Bool, lastSyncAt: Date?, lastError: String?) -> SyncCardState {
        guard signedIn else { return .signedOut }
        if syncing { return .syncing }
        if let lastError, !lastError.isEmpty { return .failed(lastError) }
        if let lastSyncAt { return .done(lastSyncAt) }
        return .never
    }

    /// «Синхронизировать сейчас» доступна, когда есть с кем и обмен не идёт.
    var canSyncNow: Bool {
        switch self {
        case .signedOut, .syncing: false
        case .failed, .never, .done: true
        }
    }
}
