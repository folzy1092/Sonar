# Бренд Sonar

| Файл | Что это |
|---|---|
| `icon/sonar_icon_dark.png` | Иконка 1024×1024: белый знак на чёрном (основная, тёмная тема iOS) |
| `icon/sonar_icon_light.png` | Иконка 1024×1024: чёрный знак на белом (светлая тема) |
| `logo.svg` | **Вектор знака** (цвет — `currentColor`), обведён по PNG 2026-11-14, совпадение 99,9 % |
| `icon/sonar_icon_dark.svg`, `icon/sonar_icon_light.svg` | Те же иконки в векторе — главный источник, PNG остаются для iOS |

Знак — буква «S» из двух изогнутых волн-импульсов с «эхом» внутри, строго чёрно-белый.
Цвет в интерфейсе даёт тема под обложку, сам знак всегда монохромный.

Иконки Windows-клиента собираются из вектора: `cd windows && npx tauri icon ../brand/icon/sonar_icon_dark.svg`.
Знак в интерфейсе — `windows/src/assets/logo-mark.svg` и `windows/public/logo-mark.svg` (белая копия `logo.svg`).
Дальше сюда: аватар бота `@SonarMusicApp`, favicon для `site/`.
В приложение иконки копируются в `ios/Sonar/Resources/Assets.xcassets/AppIcon.appiconset`.
