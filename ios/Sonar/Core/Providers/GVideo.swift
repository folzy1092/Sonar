import Foundation

/// Файлы YouTube Music с `*.googlevideo.com`. CDN отдаёт быстро только запросы с ограниченным
/// диапазоном (`Range: bytes=a-b`); запрос без конца или без Range режется до ~35 КБ/с и обрывается —
/// поэтому «Скачать» берёт файл кусками по 8 МБ, как аудио-сервер ПК (`windows/src-tauri/src/gvideo.rs`).
/// Плееру это не нужно: AVPlayer сам просит ограниченные диапазоны.
enum GVideo {
    /// Размер одного запроса к CDN.
    static let chunk: Int64 = 8 * 1024 * 1024

    static func isGVideo(_ url: URL) -> Bool {
        url.scheme == "https" && (url.host?.hasSuffix(".googlevideo.com") ?? false)
    }

    /// Размер файла из параметра `clen` ссылки; нет или не число — nil.
    static func contentLength(_ url: URL) -> Int64? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let raw = items.first(where: { $0.name == "clen" })?.value, let n = Int64(raw), n > 0 else { return nil }
        return n
    }

    /// Файл `total` байт кусками не больше `chunk`: `[0…c-1, c…2c-1, …, …total-1]`.
    static func spans(total: Int64, chunk: Int64 = GVideo.chunk) -> [ClosedRange<Int64>] {
        guard total > 0 else { return [] }
        let step = max(chunk, 1)
        return stride(from: Int64(0), to: total, by: Int(step)).map { start in
            start ... min(start + step - 1, total - 1)
        }
    }

    /// Заголовок `Range` для куска.
    static func rangeHeader(_ span: ClosedRange<Int64>) -> String {
        "bytes=\(span.lowerBound)-\(span.upperBound)"
    }

    /// Сколько байт в куске.
    static func length(_ span: ClosedRange<Int64>) -> Int64 {
        span.upperBound - span.lowerBound + 1
    }
}
