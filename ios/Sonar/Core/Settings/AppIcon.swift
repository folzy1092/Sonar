import Foundation

/// Значок приложения (Интерфейс → Вид → «Значок приложения», решение владельца 2026-11-24): основной —
/// «Стекло», остальные — альтернативные значки iOS (`UIApplication.setAlternateIconName`). Те же id, порядок
/// и названия, что на ПК (`windows/src/lib/app-icons.ts`). Файлы делает `brand/app-icons/build.mjs`: наборы
/// `AppIcon` / `AppIcon-<Имя>` и образцы для плиток `IconPreview-<id>` в Assets.xcassets; список наборов —
/// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` в `project.yml` (тест сверяет его с Info.plist).
/// Что выбрано, помнит сама iOS (`alternateIconName`), своей настройки нет — у каждого устройства свой значок.
enum AppIcon: String, CaseIterable, Identifiable, Sendable {
    case glass, flat, bevel, puff, block, echo, well, chrome, carved, light, black, white

    var id: String { rawValue }

    /// Основной: тот, что в самом наборе `AppIcon`.
    static let primary = AppIcon.glass

    /// Имя набора в каталоге: `AppIcon` или `AppIcon-<Имя>`.
    var setName: String {
        self == Self.primary ? "AppIcon" : "AppIcon-" + rawValue.prefix(1).uppercased() + String(rawValue.dropFirst())
    }

    /// Имя для `setAlternateIconName`: у основного — nil (вернуть значок по умолчанию).
    var alternateName: String? {
        self == Self.primary ? nil : setName
    }

    /// Образец для плитки (`IconPreview-<id>` в каталоге).
    var preview: String { "IconPreview-\(rawValue)" }

    /// Название — ключ перевода: `t(icon.title)`.
    var title: String {
        switch self {
        case .glass: "значок::Стекло"
        case .flat: "значок::Плоский"
        case .bevel: "значок::Фаска"
        case .puff: "значок::Подушка"
        case .block: "значок::Блок"
        case .echo: "значок::Эхо"
        case .well: "значок::Колодец"
        case .chrome: "значок::Хром"
        case .carved: "значок::Вдавленный"
        case .light: "значок::Светлый"
        case .black: "значок::Чёрный"
        case .white: "значок::Белый"
        }
    }

    /// Текущий значок по `UIApplication.alternateIconName` (nil — основной). Незнакомое имя (значок из другой
    /// сборки) — тоже основной.
    static func current(alternateName: String?) -> AppIcon {
        guard let alternateName else { return primary }
        return allCases.first { $0.alternateName == alternateName } ?? primary
    }
}
