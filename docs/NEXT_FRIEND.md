# Задание: скорость без лагов на iPhone, пространство 1D–16D, «Поделиться» через сайт

Новый спек владельца — **`docs/SPACE_SHARE_PROMPT.md`** (2026-11-22): три независимые части, по порядку
1 → 2 → 3, каждая отдельным коммитом. Перед стартом — CLAUDE.md (общение, git, переводы) и `docs/HANDOFF.md`.
Прошлое задание (пакет 2026-11-22: новинки на iPhone, «Схожесть», совместный плейлист) сделано — см. ROADMAP.

## 0. Сборка iOS

- Падали `8f9fb9e` и `d973a4b`: строгая проверка Sendable в `ios/Sonar/App/ReleaseNotifier.swift`
  (`await center.notificationSettings()` из nonisolated-метода). **Починено** — `@preconcurrency import
  UserNotifications`. Если CI всё ещё красный — смотри лог `ios.yml`, Mac нет.
- Предупреждение `ProfileEditView.swift:156` (захват `label` в `@Sendable`) сборку не валит — по желанию.
- **Каждый пуш в `ios/` отменяет идущую сборку** (`cancel-in-progress`) — правки iPhone копи и пушь пачкой.

## Правила, на которых легко споткнуться

- Строки интерфейса — `t('русский')` + перевод на **en, uk, es, de, pl** (`src/i18n/<язык>/*.ts`), iPhone —
  `cd ios/scripts && node gen-i18n.mjs`, сайт — `site/src/i18n/*.ts`.
- Новая логика на iOS — с XCTest.
- Многие файлы с CRLF: `sed`/замены по `\n` молча не срабатывают — правь Edit-ом или нормализуй.
- Перед коммитом: `cd windows && npm run check && npm test`, `cd src-tauri && CARGO_TARGET_DIR=target-check cargo test`.
- Коммиты — от Folzy, без следов агента. Пуш в `main`.
