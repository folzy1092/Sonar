// Строки только iPhone (на Windows их нет): ключ — русская строка, как в Strings+Windows.swift.
// Главнее Windows-словаря. Новая строка экрана — через `t("…")`, перевод — сюда в оба словаря.

extension I18n {
    static let iosEN: [String: String] = [
        "навигация::Назад": "Back",
    ]

    static let iosUK: [String: String] = [
        "навигация::Назад": "Назад",
    ]
}
