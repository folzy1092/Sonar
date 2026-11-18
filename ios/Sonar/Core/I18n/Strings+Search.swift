// Строки поиска на iPhone: подсказка-дописывание под полем (`Autocomplete`, чип в `SearchView`).
// Отдельным словарём, чтобы не трогать общий сгенерированный Strings+Windows.swift; ключ — русская строка.
// Ключи из общих словарей сюда не повторять: этот словарь сливается последним и перебил бы их.

extension I18n {
    static let searchEN: [String: String] = [
        "Дописать: {text}": "Complete: {text}",
    ]

    static let searchUK: [String: String] = [
        "Дописать: {text}": "Дописати: {text}",
    ]
}
