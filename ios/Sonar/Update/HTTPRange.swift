import Foundation

/// Заголовок `Range` для `InstallServer`: установщик iOS сначала читает хвост zip-а (каталог), потом
/// остальное — без поддержки Range установка обрывается. Только Foundation — покрыт тестами.
enum HTTPRange {
    /// "bytes=a-b", "bytes=a-" или "bytes=-n"; nil — весь файл.
    static func parse(_ header: String?, size: Int64) -> ClosedRange<Int64>? {
        guard let header, header.hasPrefix("bytes="), size > 0 else { return nil }
        let spec = header.dropFirst("bytes=".count).components(separatedBy: ",")[0].trimmingCharacters(in: .whitespaces)
        let parts = spec.components(separatedBy: "-")
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            guard let suffix = Int64(parts[1]), suffix > 0 else { return nil }
            return max(0, size - suffix) ... size - 1
        }
        guard let start = Int64(parts[0]), start >= 0, start < size else { return nil }
        let end = parts[1].isEmpty ? size - 1 : min(Int64(parts[1]) ?? (size - 1), size - 1)
        guard end >= start else { return nil }
        return start ... end
    }
}
