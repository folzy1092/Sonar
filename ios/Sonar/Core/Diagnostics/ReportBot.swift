import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // тесты логики на Linux
#endif

// Бот отчётов — как на ПК (`crashlog.rs` `send`): Telegram Bot API `sendDocument` в чат и тему из
// секретов CI `SONAR_REPORT_BOT_TOKEN`, `SONAR_REPORT_CHAT`, `SONAR_REPORT_THREAD`. CI подставляет их
// в build settings → Info.plist (`SonarReportBotToken`, `SonarReportChat`, `SonarReportThread`);
// в репозитории их нет. Сборка без них — «Отправить лог» открывает системное «Поделиться».

/// Куда слать отчёты (из сборки).
struct ReportBot: Equatable, Sendable {
    var token: String
    var chat: String
    var thread: String?

    static let tokenKey = "SonarReportBotToken"
    static let chatKey = "SonarReportChat"
    static let threadKey = "SonarReportThread"

    /// Из Info.plist; пусто или не подставлено (`$(SONAR_REPORT_CHAT)`) — бота нет.
    static func from(info: [String: Any]?) -> ReportBot? {
        func clean(_ name: String) -> String? {
            guard let raw = (info?[name] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
            return raw
        }
        guard let token = clean(tokenKey), let chat = clean(chatKey) else { return nil }
        return ReportBot(token: token, chat: chat, thread: clean(threadKey))
    }

    static var bundled: ReportBot? { from(info: Bundle.main.infoDictionary) }

    var endpoint: URL { URL(string: "https://api.telegram.org/bot\(token)/sendDocument")! }

    /// Запрос `sendDocument` с файлом отчёта.
    func request(caption: String, fileName: String, file: Data, boundary: String = "SonarReport-\(UUID().uuidString)") -> URLRequest {
        var fields: [(String, String)] = [("chat_id", chat)]
        if let thread { fields.append(("message_thread_id", thread)) }
        fields.append(("caption", String(caption.prefix(1000))))
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Multipart.body(fields: fields, fileField: "document", fileName: fileName,
                                          mime: "text/plain", file: file, boundary: boundary)
        return request
    }

    enum SendError: Error, Equatable {
        /// Telegram ответил не 200 или `ok: false`; описание — от Telegram.
        case rejected(status: Int, description: String?)
    }

    /// Отправить. Ошибка сети — как есть, отказ Telegram — `SendError.rejected`.
    func send(caption: String, fileName: String, file: Data, session: URLSession = .shared) async throws {
        let (data, response) = try await session.data(for: request(caption: caption, fileName: fileName, file: file))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let reply = Self.parseReply(data)
        guard status == 200, reply.ok else { throw SendError.rejected(status: status, description: reply.description) }
    }

    /// Ответ Bot API: `{"ok":true,...}` / `{"ok":false,"description":"Bad Request: chat not found"}`.
    static func parseReply(_ data: Data) -> (ok: Bool, description: String?) {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return ((json?["ok"] as? Bool) ?? false, json?["description"] as? String)
    }
}

/// `multipart/form-data` (RFC 7578): текстовые поля и один файл.
enum Multipart {
    static func body(fields: [(String, String)], fileField: String, fileName: String, mime: String,
                     file: Data, boundary: String) -> Data {
        var data = Data()
        func add(_ text: String) { data.append(Data(text.utf8)) }
        for (name, value) in fields {
            add("--\(boundary)\r\n")
            add("Content-Disposition: form-data; name=\"\(escape(name))\"\r\n\r\n")
            add(value)
            add("\r\n")
        }
        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"\(escape(fileField))\"; filename=\"\(escape(fileName))\"\r\n")
        add("Content-Type: \(mime); charset=utf-8\r\n\r\n")
        data.append(file)
        add("\r\n--\(boundary)--\r\n")
        return data
    }

    /// Кавычки и переводы строк в имени ломают заголовок — убираем.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: " ")
    }
}
