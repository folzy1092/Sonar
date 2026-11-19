import Foundation

/// Что видела установка — строка под статусом на экране «Обновление» и понятная причина, если окно iOS
/// не появилось за `SelfUpdater.hintDelay`. Порт ShadowInstallDiagnostics без маршрута backloop.
/// Только Foundation — тексты проверены тестами.

/// Запросы и соединения, которые увидел `InstallServer`.
struct InstallActivity: Equatable, Sendable {
    var listener = "запуск"
    var isReady = false
    var connections = 0
    var connectionErrors = 0
    var lastConnectionError: String?
    var pageRequested = false
    var payloadRequested = false
}

struct InstallDiagnostics: Equatable, Sendable {
    enum Opener: Equatable, Sendable {
        /// SFSafariViewController со страницей http://127.0.0.1:PORT/install.
        case safariPage
        /// UIApplication.open(itms-services://…).
        case openURL
    }

    enum Check: Equatable, Sendable {
        case pending
        case ok
        case failed(String)
    }

    var opener: Opener = .safariPage
    /// Ответ UIApplication.open; nil — ещё не ответил.
    var openResult: Bool?
    /// Свой GET манифеста с api.palera.in — до того, как его запросит iOS.
    var externalManifest: Check = .pending
    /// Запасной манифест из репо (raw.githubusercontent.com); nil — не понадобился.
    var fallbackManifest: Check?
    var server = InstallActivity()
    /// После ссылки приложение ушло в неактивное — значит, системное окно его закрыло.
    var promptSeen = false

    var line: String {
        var parts = ["HTTP 127.0.0.1", "манифест palera \(Self.mark(externalManifest))"]
        if let fallbackManifest { parts.append("репо \(Self.mark(fallbackManifest))") }
        switch opener {
        case .safariPage: parts.append("Safari \(server.pageRequested ? "✓" : "—")")
        case .openURL: parts.append("open \(openResult.map { $0 ? "✓" : "✗" } ?? "…")")
        }
        parts.append("сервер \(server.listener)")
        var connections = "подкл. \(server.connections)"
        if server.connectionErrors > 0 { connections += ", ошибок \(server.connectionErrors)" }
        if let error = server.lastConnectionError { connections += " (\(error))" }
        parts.append(connections)
        parts.append("ipa \(server.payloadRequested ? "✓" : "—")")
        return parts.joined(separator: " · ")
    }

    /// Почему окна iOS нет — самое конкретное первым; в конце — как обойти.
    var cause: String {
        reason + " Или «Поделиться подписанной IPA» и установить её через ESign."
    }

    private var reason: String {
        if !server.isReady {
            return "Локальный сервер не работает (\(server.listener)). «Показать окно установки» перезапустит его."
        }
        if server.payloadRequested {
            return "iOS начала загрузку, но не закончила. Держи Sonar открытым и нажми «Показать окно установки»."
        }
        if opener == .openURL, openResult == false {
            return "iOS отказалась открыть ссылку itms-services."
        }
        // без манифеста iOS нечего показать: если что-то и закрыло приложение — это было не окно установки
        if case let .failed(error) = externalManifest, fallbackManifest != .ok {
            return "Не удалось получить манифест с api.palera.in (\(error)): без него iOS не покажет окно. Проверь интернет и VPN."
        }
        if promptSeen {
            return "Окно установки было, но iOS не начала загрузку. Если нажал «Отмена» — нажми «Показать окно установки»."
        }
        if opener == .safariPage, !server.pageRequested {
            return "Safari не открыл страницу установки на 127.0.0.1. «Показать окно установки» откроет окно напрямую."
        }
        return "Ссылка установки открыта, но iOS не показала окно. Обычно iOS не смогла скачать манифест с api.palera.in: проверь VPN и DNS-фильтры."
    }

    private static func mark(_ check: Check) -> String {
        switch check {
        case .pending: "…"
        case .ok: "✓"
        case let .failed(error): "✗ \(error)"
        }
    }
}
