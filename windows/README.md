# Sonar для Windows

ПК-клиент Sonar — первая платформа проекта (`docs/SPEC.md` §9).

**Стек:** Tauri 2 (Rust, окно на WebView2) · Svelte 5 + TypeScript · Vite · свой CSS · иконки Tabler.

## Запуск

Нужны Node.js 24 и Rust (stable).

```bash
npm install
npm run tauri dev      # окно приложения с горячей перезагрузкой
npm run dev            # только интерфейс в браузере (кнопки окна — заглушки)
npm run check          # проверка типов
npm run tauri build    # установщик NSIS → src-tauri/target/release/bundle/nsis/
```

## Устройство

| Где | Что |
|---|---|
| `src/App.svelte` | оболочка: колонка иконок, карточка-страница, мини-плеер |
| `src/app/` | левая панель, кнопки окна, строка поиска, мини-плеер, роутер |
| `src/pages/` | Главная, Медиатека, Поиск, Плеер, Настройки |
| `src/components/` | иконки, кнопки, плитки, пустые состояния |
| `src/theme/tokens.css` | цвета, радиусы, шрифты, анимации — CSS-переменные |
| `src-tauri/` | Rust: конфиг окна, права, иконки |

Полная карта — `docs/MAP.md`, план — `docs/ROADMAP.md` (блок W).
CI: `.github/workflows/windows.yml` собирает установщик на каждый пуш в `windows/`.
