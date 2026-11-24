# Бренд Sonar

| Файл | Что это |
|---|---|
| `icon/sonar_icon_dark.png`, `icon/sonar_icon_dark.svg` | **Основной значок** — «Стекло» (решение владельца 2026-11-24): объёмный знак на тёмной плитке 1024×1024, как у iPhone. Собирается `app-icons/build.mjs` |
| `icon/sonar_icon_windows.svg` | Он же плиткой с прозрачными углами — из него `tauri icon` делает значки exe и установщика |
| `icon/sonar_icon_light.png`, `icon/sonar_icon_light.svg` | Старый плоский чёрный знак на белом (светлая тема), не обновлялся |
| `logo.svg` | **Вектор знака** (цвет — `currentColor`), обведён по PNG 2026-11-14, совпадение 99,9 %. Контур, из которого строятся все значки; в интерфейсе знак остаётся плоским и берёт цвет у темы |
| `app-icons/` | Значки приложения на выбор: `<id>.svg` — одиннадцать вариантов вместе с «Плоским» (прежним), `index.html` — галерея, `icons.json` — список для тестов, `build.mjs` — генератор |

Знак — буква «S» из двух изогнутых волн-импульсов с «эхом» внутри. Плоским он остаётся в интерфейсе
(левая панель, заставка, лого на сайте): там знак маленький, а цвет даёт тема под обложку. Объём — только у значка
приложения: иконка экрана, exe, панель задач, трей.

## Значки на выбор

Интерфейс → Вид → «Значок приложения» (ПК и iPhone, настройка `appearance.app_icon`, `docs/SETTINGS.md`):
**Стекло** (основной), Плоский, Фаска, Подушка, Блок, Эхо, Колодец, Хром, Вдавленный, Светлый, Чёрный (белая буква в чёрной плите), Белый (чёрная буква в белой).
На ПК выбор меняет значок окна, панели задач и трея на лету (`windows/src-tauri/src/app_icon.rs`); ярлыки и
закреплённая кнопка остаются с основным — их значок Windows берёт из exe. На iPhone — альтернативные значки iOS.

Всё делает один скрипт — после правки знака или вариантов:

```
cd brand/app-icons && npm install && node build.mjs
cd ../../windows && npx tauri icon ../brand/icon/sonar_icon_windows.svg
```

Скрипт пишет: `app-icons/<id>.svg`, основной значок (`icon/sonar_icon_dark.*`, `icon/sonar_icon_windows.svg`),
`site/public/apple-touch-icon.png`, PNG для Windows (`windows/src-tauri/icons/app/`, `windows/public/app-icons/`) и наборы
iOS в `ios/Sonar/Resources/Assets.xcassets` (`AppIcon`, `AppIcon-<Имя>`, `IconPreview-<id>`). Новый вариант — запись в
`build.mjs` (+ `ORDER`), id в `windows/src/lib/app-icons.ts`, `windows/src-tauri/src/app_icon.rs`, `ios/Sonar/Core/Settings/AppIcon.swift`,
имя набора в `ios/project.yml`, переводы названия — тесты всех трёх сторон скажут, что забыто. Объём строится на градиентах и
внутренних тенях, а не на фильтрах освещения: в resvg, которым всё собирается, освещение зернит.

Иконки Windows-клиента: `windows/src/assets/logo-mark.svg` и `windows/public/logo-mark.svg` (белая копия `logo.svg`).
Дальше сюда: аватар бота `@SonarMusicApp` (ставится руками в BotFather), favicon для `site/` — берёт `icon/sonar_icon_dark.svg`.
