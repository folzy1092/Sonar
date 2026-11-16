import Foundation

/// Ссылки установки на устройстве — маршрут «Semi Local», как в IPA Hub / Feather (порт ShadowInstallLinks):
/// IPA лежит на `http://127.0.0.1:PORT/sonar.ipa` (без DNS и без TLS на устройстве), а `itms-services`
/// требует https-манифест с доверенным сертификатом — его собирает из параметров запроса
/// `api.palera.in/genPlist`. Safari открывает страницу `/install`, она передаёт ссылку в iOS.
/// Маршрут через `*.backloop.dev` не переносим: его сертификат отозван 2026-07-31.
/// Только Foundation — покрыт тестами.
enum InstallLinks {
    static let loopback = "127.0.0.1"
    /// Пока своего сервера нет. С сервером манифест переедет на `GET /updates/manifest.plist?ipa=…`
    /// (SPEC §4.6) — достаточно поменять эту константу и `externalManifestURL`.
    static let externalManifestBase = "https://api.palera.in/genPlist"
    static let payloadPath = "/sonar.ipa"
    static let pagePath = "/install"

    /// RFC 3986 unreserved, только ASCII: `CharacterSet.alphanumerics` пропустил бы и не-ASCII буквы.
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    static func payloadURL(port: UInt16) -> URL {
        URL(string: "http://\(loopback):\(port)\(payloadPath)")!
    }

    static func pageURL(port: UInt16) -> URL {
        URL(string: "http://\(loopback):\(port)\(pagePath)")!
    }

    /// palera.in вставляет значения в plist без XML-экранирования — в названии оставляем только то,
    /// что экранировать не нужно.
    static func plainTitle(_ title: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .-_()")
        let cleaned = String(title.filter { allowed.contains($0) }).split(separator: " ").joined(separator: " ")
        return cleaned.isEmpty ? "Sonar" : cleaned
    }

    static func isPlainToken(_ value: String) -> Bool {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_")
        return !value.isEmpty && value.allSatisfy { allowed.contains($0) }
    }

    /// `https://api.palera.in/genPlist?bundleid=…&name=…&version=…&fetchurl=…`
    static func externalManifestURL(bundleId: String, bundleVersion: String, title: String, payload: URL) -> URL? {
        guard isPlainToken(bundleId), isPlainToken(bundleVersion) else { return nil }
        let query = [
            ("bundleid", bundleId),
            ("name", plainTitle(title)),
            ("version", bundleVersion),
            ("fetchurl", payload.absoluteString),
        ].map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        return URL(string: externalManifestBase + "?" + query)
    }

    static func itmsURL(manifest: URL) -> URL? {
        let encoded = encode(manifest.absoluteString)
        guard !encoded.isEmpty else { return nil }
        return URL(string: "itms-services://?action=download-manifest&url=" + encoded)
    }

    /// Почему манифест api.palera.in не годится (коротко, для строки диагностики); nil — это plist для
    /// нашей IPA.
    static func externalManifestProblem(data: Data?, statusCode: Int?, error: Error?, payload: URL) -> String? {
        if let error {
            switch (error as? URLError)?.code {
            case .timedOut?: return "нет ответа"
            case .notConnectedToInternet?, .networkConnectionLost?: return "нет интернета"
            case .cannotFindHost?, .dnsLookupFailed?: return "DNS"
            case .secureConnectionFailed?, .serverCertificateUntrusted?, .serverCertificateHasBadDate?,
                 .serverCertificateNotYetValid?, .serverCertificateHasUnknownRoot?, .clientCertificateRejected?:
                return "TLS"
            case let code?: return "ошибка \(code.rawValue)"
            case nil: return "ошибка"
            }
        }
        guard let statusCode else { return "нет ответа" }
        guard statusCode == 200 else { return "HTTP \(statusCode)" }
        let body = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        guard body.contains("software-package"), body.contains(payload.absoluteString) else { return "неверный ответ" }
        return nil
    }

    /// Страница `/install`: Safari идёт по скрипту, кнопка — на случай второй попытки руками.
    static func installPage(itms: URL) -> String {
        // ссылка — ASCII с процентами: ни кавычек, ни угловых скобок; в атрибуте экранируем только &
        let link = itms.absoluteString
        let attribute = link.replacingOccurrences(of: "&", with: "&amp;")
        return """
        <!doctype html>
        <html lang="ru"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Sonar</title>
        <style>body{margin:0;padding:30vh 24px 0;background:#09090a;color:#fff;font:17px -apple-system,sans-serif;text-align:center}div{opacity:.6}a{display:inline-block;margin-top:18px;padding:14px 28px;border-radius:999px;background:#f58c9e;color:#09090a;text-decoration:none;font-weight:600}</style>
        </head><body>
        <div>Если окно установки не появилось:</div>
        <a href="\(attribute)">Установить Sonar</a>
        <script>window.location="\(link)"</script>
        </body></html>
        """
    }
}
