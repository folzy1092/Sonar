// Экспорт списка в файл на iPhone (`Features/Library/ExportSheet.swift`). Те же ключи, что в словаре ПК
// `windows/src/i18n/*/export.ts` (после перегенерации `Strings+Windows.swift` они придут и оттуда), плюс
// строки только iOS. Ключ — русская строка, как в Strings+iOS.swift.

extension I18n {
    static let exportEN: [String: String] = [
        "Экспорт": "Export",
        "для плееров": "for players",
        "для таблиц": "for spreadsheets",
        "все поля": "all fields",
        "Не удалось подготовить файлы": "Couldn't prepare the files",
    ]

    static let exportUK: [String: String] = [
        "Экспорт": "Експорт",
        "для плееров": "для плеєрів",
        "для таблиц": "для таблиць",
        "все поля": "усі поля",
        "Не удалось подготовить файлы": "Не вдалося підготувати файли",
    ]
}
