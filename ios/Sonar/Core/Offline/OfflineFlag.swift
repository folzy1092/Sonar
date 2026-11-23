import Foundation
import os

/// Флаг офлайн-режима (`general.offline`, `docs/OFFLINE.md` §4) — для кода вне главного актора: сторож сети
/// (`OfflineGuard`) зовётся с потоков `URLSession`. Пишет его только `OfflineMode`.
enum OfflineFlag {
    static let key = "general.offline"

    private struct State {
        var isOn = false
        var blocked = 0
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static var isOn: Bool { state.withLock { $0.isOn } }

    /// Сколько запросов сторож не пустил в сеть с последнего включения (Система → Общее → Сеть).
    static var blocked: Int { state.withLock { $0.blocked } }

    static func set(_ on: Bool) {
        state.withLock {
            if !on { $0.blocked = 0 }
            $0.isOn = on
        }
    }

    static func noteBlocked() {
        state.withLock { $0.blocked += 1 }
    }

    /// Прочитать флаг прямо из сохранённых настроек (`SettingsStore`, ключ `sonar.settings`) — до всего
    /// остального при запуске (§4.1). Настроек нет (первый запуск) — выключен; сохранены, но не читаются —
    /// включён: лучше не пустить в сеть, чем пустить в роуминге.
    static func read(from storage: UserDefaults, storageKey: String = "sonar.settings") -> Bool {
        guard let data = storage.data(forKey: storageKey) else { return false }
        guard let saved = try? JSONDecoder().decode([String: SettingValue].self, from: data) else { return true }
        if case let .bool(on)? = saved[key] { return on }
        return false
    }
}
