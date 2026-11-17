import SwiftUI

/// «Экспорт» списка (NEXT_PROMPT, этап 8; на ПК — подменю `ExportItems.svelte`): три файла — M3U8, CSV и
/// JSON (`PlaylistExport`) — готовятся во временной папке, каждый отдаётся листом «Поделиться» (`ShareLink`):
/// «Сохранить в Файлы», почта, мессенджеры. Имя файла — название списка.
struct ExportSheet: View {
    /// Название списка — оно же имя файла (уже переведённое для Любимых).
    let name: String
    let tracks: [Track]
    @Environment(\.dismiss) private var dismiss
    @State private var files: [ExportFormat: URL] = [:]
    @State private var failed = false

    /// Все экспорты лежат здесь; старые убираются при следующем экспорте.
    private static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(t("Экспорт"))
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    CircleButton(icon: .close, size: 44, iconSize: 20, label: t("Закрыть")) { dismiss() }
                }
                Text("«\(name)» · " + tracksCount(tracks.count))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 4)

                if failed {
                    Text(t("Не удалось подготовить файлы"))
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.danger)
                        .padding(.top, 26)
                        .transition(.opacity)
                } else if files.isEmpty {
                    ProgressView()
                        .tint(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(ExportFormat.allCases.enumerated()), id: \.element) { index, format in
                            if let url = files[format] {
                                row(format, url: url).cascade(index)
                            }
                        }
                    }
                    .padding(.top, 26)
                    .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 26)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .animation(Motion.spring, value: files.isEmpty)
        .animation(Motion.spring, value: failed)
        .task { await prepare() }
    }

    private func row(_ format: ExportFormat, url: URL) -> some View {
        ShareLink(item: url) {
            HStack(spacing: 22) {
                SonarIcon(icon(format), size: 24)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(format.label)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text(hint(format))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                SonarIcon(.share, size: 20)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityLabel(format.label + ", " + hint(format))
    }

    private func icon(_ format: ExportFormat) -> IconName {
        switch format {
        case .m3u8: .music
        case .csv: .grid
        case .json: .document
        }
    }

    private func hint(_ format: ExportFormat) -> String {
        switch format {
        case .m3u8: t("для плееров")
        case .csv: t("для таблиц")
        case .json: t("все поля")
        }
    }

    /// Три файла в своей папке `Export/<UUID>/` — имя файла остаётся названием списка. Названия сервисов
    /// переводятся здесь (на главном потоке), запись — в фоне.
    private func prepare() async {
        let items = tracks.map { ExportItem(track: $0, addedAt: nil) }
        let labels = Dictionary(tracks.map { ($0.ref, $0.ref) }, uniquingKeysWith: { first, _ in first })
            .mapValues { ref in
                let service = PlaylistExport.serviceName(ref)
                return service.isEmpty ? "" : t(service)
            }
        let name = name
        let folder = Self.folder
        let result = await Task.detached(priority: .userInitiated) { () -> Result<[ExportFormat: URL], Error> in
            Result {
                let manager = FileManager.default
                if manager.fileExists(atPath: folder.path) {
                    try manager.removeItem(at: folder)
                }
                let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
                var urls: [ExportFormat: URL] = [:]
                for format in ExportFormat.allCases {
                    urls[format] = try PlaylistExport.write(format, name: name, items: items, in: directory,
                                                            label: { labels[$0] ?? "" })
                }
                return urls
            }
        }.value
        switch result {
        case let .success(urls):
            files = urls
        case let .failure(error):
            // путь не пишем: в нём папка приложения; хватит вида ошибки
            CrashLog.warn("экспорт: не удалось подготовить файлы (\(type(of: error)))")
            failed = true
        }
    }
}
