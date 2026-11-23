import SwiftUI
import UIKit

/// Что занято на телефоне — для «Хранилища».
struct StorageUsage: Equatable, Sendable {
    var downloadsBytes: Int64 = 0
    var downloads = 0
    var coversBytes: Int64 = 0
    var lyricsBytes: Int64 = 0
    var lyrics = 0
    var historyBytes: Int64 = 0

    var total: Int64 { downloadsBytes + coversBytes + lyricsBytes + historyBytes }

    /// Файлы в папке: сколько и сколько весят.
    static func folder(_ url: URL) -> (count: Int, bytes: Int64) {
        guard let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return (0, 0) }
        var count = 0
        var bytes: Int64 = 0
        for case let file as URL in items {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            count += 1
            bytes += Int64(values?.fileSize ?? 0)
        }
        return (count, bytes)
    }

    static func file(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Потолок кэша обложек на диске (`storage.covers_limit_mb`) — AsyncImage берёт обложки через
    /// `URLCache.shared`. Звать при запуске и при смене настройки.
    @MainActor
    static func applyCoverLimit(_ settings: SettingsStore) {
        var mb = 256
        switch settings.value(coverLimitKey) {
        case let .int(value)?: mb = value
        case let .double(value)?: mb = Int(value)
        default: break
        }
        URLCache.shared.diskCapacity = max(64, mb) * 1_048_576
        URLCache.shared.memoryCapacity = 32 * 1_048_576
    }

    static let coverLimitKey = "storage.covers_limit_mb"
    static let coverLimits = [128, 256, 512, 1024]
}

/// Система → «Хранилище» (SETTINGS.md «Кэш / Хранилище», как Windows `Storage.svelte`): сколько занято
/// (полоса по типам), скачанные треки (с подтверждением), кэш обложек (очистка и потолок
/// `storage.covers_limit_mb`), тексты песен (неделя / две у Любимых — `LyricsCache`), история
/// прослушиваний (Недавнее, статистика и вкус волны — с подтверждением), история поиска.
struct StorageSettingsView: View {
    enum Danger: String, Identifiable {
        case downloads, history
        var id: String { rawValue }
    }

    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router
    @State private var downloads = DownloadStore.shared
    @State private var log = PlayLog.shared
    @State private var usage: StorageUsage?
    @State private var confirm: Danger?
    @State private var likedBatch: DownloadPlan.Batch?
    @AppStorage("search.history") private var searchHistory = ""

    private var lyricsDirectory: URL { LyricsCache().directory }
    private var historyFiles: [URL] {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return [base.appendingPathComponent("Sonar/history.json"), base.appendingPathComponent("Sonar/plays.json")]
    }

    private var searchCount: Int { searchHistory.split(separator: "\n").count }

    private var coverLimit: Binding<Int> {
        Binding(get: {
            switch settings.value(StorageUsage.coverLimitKey) {
            case let .int(value)?: value
            case let .double(value)?: Int(value)
            default: 256
            }
        }, set: {
            settings.set(StorageUsage.coverLimitKey, .int($0))
            StorageUsage.applyCoverLimit(settings)
        })
    }

    private var wifiOnly: Binding<Bool> {
        Binding(get: { settings.bool(DownloadStore.wifiOnlyKey) }, set: {
            settings.set(DownloadStore.wifiOnlyKey, $0)
            downloads.resume()
        })
    }

    /// Включение — с подтверждением, если Любимых не хватает (сколько, ~размер, лимит), как ПК `enableLiked`.
    private var autoLiked: Binding<Bool> {
        Binding(get: { settings.bool(LikedAutoDownload.enabledKey) }, set: { on in
            guard on else { return settings.set(LikedAutoDownload.enabledKey, false) }
            let missing = LikedAutoDownload.missing(LibraryStore.shared.liked)
            guard missing.isEmpty else {
                likedBatch = DownloadPlan.Batch(missing, quality: settings.string("audio.quality"), free: nil)
                return
            }
            enableLiked()
        })
    }

    private var likedLimit: Binding<Int> {
        Binding(get: { LikedAutoDownload.limitGB(settings) }, set: {
            settings.set(LikedAutoDownload.limitKey, .int($0))
            LikedAutoDownload.fill()
        })
    }

    private func enableLiked() {
        settings.set(LikedAutoDownload.enabledKey, true)
        LikedAutoDownload.fill()
    }

    /// «120 треков · ~1.4 ГБ · лимит 5 ГБ».
    private func likedSummary(_ batch: DownloadPlan.Batch) -> String {
        let limit = DownloadPlan.bytesText(Int64(LikedAutoDownload.limitGB(settings)) << 30)
        return [tracksCount(batch.tracks.count), "~" + DownloadPlan.bytesText(batch.bytes), t("лимит {n}", ["n": limit])]
            .joined(separator: " · ")
    }

    var body: some View {
        SystemScreen(title: t("Хранилище")) {
            summary
                .cascade(0)

            SystemSection(title: t("Скачанные"), footer: t("Играют без сети. Удалить отдельный трек — в его меню.")) {
                SystemRow(icon: .download, title: t("Скачанные треки"),
                          subtitle: "\(downloads.downloaded.count) \(tn(downloads.downloaded.count, "трек", "трека", "треков")), \(bytesText(usage?.downloadsBytes ?? 0))")
                RowDivider()
                SystemToggle(icon: .cellphone, title: t("Только по Wi‑Fi"),
                             subtitle: t("По сотовой сети загрузки ждут Wi‑Fi"), isOn: wifiOnly)
                RowDivider()
                SystemToggle(icon: .heart, title: t("Скачивать Любимые"),
                             subtitle: t("Лайкнутые треки сами скачиваются на этот телефон по Wi‑Fi, пока не упрутся в лимит"),
                             isOn: autoLiked)
                if settings.bool(LikedAutoDownload.enabledKey) {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 10) {
                        SystemRow(icon: .storage, title: t("Лимит для Любимых"),
                                  subtitle: t("Сколько места на диске могут занять скачанные треки"))
                            .padding(.bottom, -12)
                        SystemSegments(options: DownloadPlan.limitOptions.map { SystemSegments<Int>.Option(id: $0, title: t("{n} ГБ", ["n": "\($0)"])) },
                                       selection: likedLimit)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                    }
                    .transition(.opacity)
                }
                RowDivider()
                SystemButtonRow(icon: .trash, title: t("Удалить все скачанные"), tint: Theme.danger,
                                enabled: !downloads.downloaded.isEmpty) { confirm = .downloads }
            }
            .cascade(1)

            SystemSection(title: t("Очистка кеша")) {
                cacheRow(icon: .pic, title: t("Обложки"), detail: bytesText(usage?.coversBytes ?? 0),
                         tint: Self.coversTint, enabled: (usage?.coversBytes ?? 0) > 0) {
                    URLCache.shared.removeAllCachedResponses()
                    done(t("Обложки удалены"))
                }
                RowDivider()
                cacheRow(icon: .lyrics, title: t("Тексты"),
                         detail: "\(usage?.lyrics ?? 0) \(tn(usage?.lyrics ?? 0, "текст", "текста", "текстов")), \(bytesText(usage?.lyricsBytes ?? 0))",
                         tint: Self.lyricsTint, enabled: (usage?.lyrics ?? 0) > 0) {
                    try? FileManager.default.removeItem(at: lyricsDirectory)
                    done(t("Тексты удалены"))
                }
                RowDivider()
                VStack(alignment: .leading, spacing: 10) {
                    SystemRow(icon: .sliders, title: t("Размер кэша обложек"), subtitle: t("Сверх лимита iOS удаляет старые"))
                        .padding(.bottom, -12)
                    SystemSegments(options: StorageUsage.coverLimits.map { SystemSegments<Int>.Option(id: $0, title: limitTitle($0)) }, selection: coverLimit)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
            .cascade(2)

            SystemSection(title: t("Данные"), footer: t("Тексты хранятся неделю с последнего показа, у Любимых — две.")) {
                SystemButtonRow(icon: .history, title: t("История прослушиваний"),
                                subtitle: "\(log.rows.count) \(tn(log.rows.count, "запись", "записи", "записей")) — \(t("Недавнее, статистика и вкус волны"))",
                                value: bytesText(usage?.historyBytes ?? 0), tint: nil,
                                enabled: !log.rows.isEmpty || !PlayHistory.shared.recent.isEmpty) { confirm = .history }
                RowDivider()
                SystemButtonRow(icon: .search, title: t("История поиска"),
                                subtitle: "\(searchCount) \(tn(searchCount, "запись", "записи", "записей"))",
                                value: searchCount > 0 ? t("Очистить") : nil, enabled: searchCount > 0) {
                    searchHistory = ""
                    done(t("История поиска очищена"))
                }
            }
            .cascade(3)
        }
        .task { await refresh() }
        .confirmationDialog(confirm == .downloads ? t("Удалить все скачанные треки? Их можно будет скачать снова.")
                                : t("Очистить историю прослушиваний? Пропадут Недавнее, статистика и то, что волна узнала о твоём вкусе."),
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { kind in
            Button(kind == .downloads ? t("Удалить") : t("Очистить"), role: .destructive) {
                switch kind {
                case .downloads:
                    downloads.removeAll()
                    done(t("Скачанные удалены"))
                case .history:
                    PlayHistory.shared.clear()
                    done(t("История очищена"))
                }
            }
            Button(t("Отмена"), role: .cancel) {}
        }
        .alert(t("Скачивать Любимые?"), isPresented: Binding(get: { likedBatch != nil }, set: { if !$0 { likedBatch = nil } }),
               presenting: likedBatch) { _ in
            Button(t("Включить")) { enableLiked() }
            Button(t("Отмена"), role: .cancel) {}
        } message: { batch in
            Text(likedSummary(batch) + "\n" + t("Не закрывай Sonar, пока качается"))
        }
    }

    static var downloadsTint: Color { Theme.accent }
    static let coversTint = Color(red: 0.45, green: 0.65, blue: 1.0)
    static let lyricsTint = Color(red: 0.98, green: 0.72, blue: 0.35)
    static let historyTint = Color(red: 0.62, green: 0.86, blue: 0.6)

    /// Итог сверху: «12.4 МБ занято» и полоса по типам.
    private var summary: some View {
        let u = usage ?? StorageUsage()
        let parts: [(String, Int64, Color)] = [
            (t("Скачанные"), u.downloadsBytes, Self.downloadsTint),
            (t("Обложки"), u.coversBytes, Self.coversTint),
            (t("Тексты"), u.lyricsBytes, Self.lyricsTint),
            (t("История"), u.historyBytes, Self.historyTint),
        ]
        let total = max(1, u.total)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(bytesText(u.total))
                    .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                Text(t("Занято"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(parts, id: \.0) { part in
                        Capsule()
                            .fill(part.2)
                            .frame(width: part.1 > 0 ? max(6, (proxy.size.width - 9) * CGFloat(part.1) / CGFloat(total)) : 0)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 12)
            .background(Theme.raised.opacity(0.6), in: Capsule())
            .clipShape(Capsule())
            FlowLegend(parts: parts.map { ($0.0, bytesText($0.1), $0.2) })
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(Motion.spring, value: usage)
        .redacted(reason: usage == nil ? .placeholder : [])
    }

    private func cacheRow(icon: IconName, title: String, detail: String, tint: Color, enabled: Bool,
                          clear: @escaping @MainActor () -> Void) -> some View {
        HStack(spacing: 14) {
            Circle().fill(tint).frame(width: 9, height: 9)
            SonarIcon(icon, size: 22)
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            Button {
                clear()
            } label: {
                Text(t("Очистить"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(enabled ? Theme.text : Theme.textTertiary)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Theme.raised.opacity(0.8), in: Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.94))
            .disabled(!enabled)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 62)
    }

    private func limitTitle(_ mb: Int) -> String {
        mb < 1024 ? t("{n} МБ", ["n": String(mb)]) : t("{n} ГБ", ["n": String(mb / 1024)])
    }

    private func done(_ text: String) {
        Haptics.success()
        router.say(text)
        Task { await refresh() }
    }

    private func refresh() async {
        let lyricsDir = lyricsDirectory
        let files = historyFiles
        let downloadsDir = downloads.directory
        let downloadCount = downloads.downloaded.count
        let measured = await Task.detached(priority: .utility) { () -> StorageUsage in
            var u = StorageUsage()
            let d = StorageUsage.folder(downloadsDir)
            u.downloadsBytes = d.bytes
            u.downloads = downloadCount
            let l = StorageUsage.folder(lyricsDir)
            u.lyrics = l.count
            u.lyricsBytes = l.bytes
            u.historyBytes = files.reduce(0) { $0 + StorageUsage.file($1) }
            return u
        }.value
        var next = measured
        next.coversBytes = Int64(URLCache.shared.currentDiskUsage)
        withAnimation(Motion.spring) { usage = next }
    }
}

/// Подписи к полосе: цвет, тип, размер — переносятся по строкам.
private struct FlowLegend: View {
    let parts: [(String, String, Color)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
            ForEach(parts, id: \.0) { part in
                HStack(spacing: 8) {
                    Circle().fill(part.2).frame(width: 8, height: 8)
                    Text(part.0)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text(part.1)
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}
