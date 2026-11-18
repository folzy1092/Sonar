# Sonar для iPhone

SwiftUI, iOS 18+, проект генерирует [XcodeGen](https://github.com/yonaskolb/XcodeGen) из `project.yml`
(`.xcodeproj` в git не хранится). Структура папок — `docs/MAP.md`, стек и устройство — `docs/SPEC.md` §4,
экраны и настройки — `docs/PLATFORMS.md` и `docs/SETTINGS.md`. План работ — `docs/IOS_PROMPT.md`.

```bash
cd ios
xcodegen generate
open Sonar.xcodeproj
```

Mac есть не у всех: каждый пуш в `main` с изменениями `ios/` собирается на GitHub Actions (`ios.yml`) —
тесты на симуляторе и неподписанный `Sonar.ipa` в артефактах запуска. Пуш в `dev` гоняет ту же сборку и тесты
без релиза. Ставится сторонней подписью
(ESign / Feather с P12 + mobileprovision пользователя), дальше приложение обновляет себя само.

## Где что (волна 2026-11-18)

| Что | Где |
|---|---|
| Реестр сервисов | `Sonar/Core/Models/ServiceRegistry.swift` |
| YouTube Music, VK, Spotify | `Sonar/Core/Providers/YouTube*.swift`, `VK*.swift`, `Spotify*.swift` |
| Резерв из другого сервиса | `Sonar/Core/Providers/Fallback.swift`, `MusicCore+Fallback.swift` |
| Умные плейлисты | `Sonar/Core/Smart/`, `Sonar/Features/Library/Smart*.swift` |
| Дубли (ядро) | `Sonar/Core/Library/DupeFinder.swift` |
| Экспорт | `Sonar/Core/Export/` |
| Итоги | `Sonar/Core/Stats/Recap.swift`, `Sonar/Features/Stats/Recap*.swift` |
| Пульт для Sonar на ПК | `Sonar/Core/Remote/`, `Sonar/Playback/RemoteControl.swift` |
| Строки экранов | `Sonar/Core/I18n/Strings+<Экран>.swift` → `I18n.dictionaries` |
