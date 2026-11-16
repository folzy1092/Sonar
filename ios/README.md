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
тесты на симуляторе и неподписанный `Sonar.ipa` в артефактах запуска. Ставится сторонней подписью
(ESign / Feather с P12 + mobileprovision пользователя), дальше приложение обновляет себя само.
