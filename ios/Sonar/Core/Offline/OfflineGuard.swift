import Foundation

/// Сторож «ни байта в сеть» (`docs/OFFLINE.md` §5): в офлайне перехватывает каждый http(s)-запрос
/// `URLSession.shared` (регистрация в `SonarApp.init`) и своих сессий (`Net.configuration`). Отдаёт только
/// уже лежащее в `URLCache` (обложки `AsyncImage`), остальное — «нет сети». Локальная сеть (пульт ПК,
/// сервер установки) идёт мимо `URLSession` и не трогается. `AVPlayer` мимо сторожа — его держит `PlaybackEngine`.
final class OfflineGuard: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        guard OfflineFlag.isOn, let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if (request.httpMethod ?? "GET") == "GET", let cached = URLCache.shared.cachedResponse(for: request) {
            client?.urlProtocol(self, didReceive: cached.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: cached.data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        OfflineFlag.noteBlocked()
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

/// Свои `URLSession` — только с этой конфигурацией: сторож офлайна первым в цепочке.
/// Сторож-тест (`OfflineTests`) ловит `URLSession(configuration:` без неё.
enum Net {
    static func configuration(_ base: URLSessionConfiguration = .default) -> URLSessionConfiguration {
        base.protocolClasses = [OfflineGuard.self] + (base.protocolClasses ?? [])
        return base
    }
}
