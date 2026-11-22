import Foundation
import UIKit

/// «Скачать» в меню трека: файл трека на телефон — лист «Поделиться» с «Сохранить в Файлы». Уже в кеше
/// («Кешировать», `DownloadStore`) или в подкачке волны (`WaveCache`) — копия оттуда, иначе качаем так же, как
/// кеш (`CoreDownloadFetcher`: файл, не HLS). Файл — во временной папке `Export`, прежний того же трека
/// перезаписывается.
@MainActor
enum TrackExport {
    static func file(for track: Track) async throws -> URL {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        if let local = DownloadStore.shared.localURL(track.ref) ?? WaveCache.shared.localURL(track.ref) {
            let target = folder.appendingPathComponent(fileName(track, ext: local.pathExtension))
            try? files.removeItem(at: target)
            try files.copyItem(at: local, to: target)
            return target
        }
        let fetcher = CoreDownloadFetcher()
        let source = try await fetcher.source(for: track)
        let target = folder.appendingPathComponent(fileName(track, ext: source.fileExtension))
        try? files.removeItem(at: target)
        try await fetcher.fetch(source.url, to: target, progress: { _ in })
        return target
    }

    /// «Исполнитель — Название.mp3»: без символов, которые «Файлы» не примут, не длиннее 120 знаков.
    nonisolated static func fileName(_ track: Track, ext: String) -> String {
        let raw = track.artist.isEmpty ? track.title : "\(track.artist) — \(track.title)"
        let banned = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        var name = raw.components(separatedBy: banned).joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "Sonar" }
        if name.count > 120 { name = String(name.prefix(120)).trimmingCharacters(in: .whitespaces) }
        return ext.isEmpty ? name : "\(name).\(ext)"
    }

    /// Лист «Поделиться» поверх верхнего экрана (меню трека к этому времени закрыто).
    static func share(_ url: URL) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else { return }
        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = top.view
        top.present(controller, animated: true)
    }
}
