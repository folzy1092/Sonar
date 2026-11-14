# Sonar для Windows

ПК-клиент Sonar — первая платформа проекта (`docs/SPEC.md` §9).

**Стек:** Tauri 2 (Rust, окно на WebView2) · Svelte 5 + TypeScript · Vite · свой CSS · иконки Tabler.

## Запуск

Без команд — двойной клик в корне репо: **«Собрать и запустить.bat»** (свежая версия, пересобирает
только изменённое) или **«Запустить.bat»** (последняя собранная, мгновенно).

Нужны Node.js 24 и Rust (stable).

```bash
npm install
npm run tauri dev      # окно приложения с горячей перезагрузкой
npm run dev            # только интерфейс в браузере (кнопки окна — заглушки)
npm run check          # проверка типов
npm test               # тесты интерфейса (vitest): очередь
cd src-tauri && cargo test   # тесты Rust: провайдеры, база, аудио-сервер
# живые проверки SoundCloud (сеть): SC_CLIENT_ID=… cargo test -- --ignored --nocapture
npm run tauri build    # установщик NSIS → src-tauri/target/release/bundle/nsis/
```

## Устройство

| Где | Что |
|---|---|
| `src/App.svelte` | оболочка: колонка иконок, карточка-страница, мини-плеер |
| `src/app/` | левая панель, кнопки окна, строка поиска, мини-плеер, роутер |
| `src/pages/` | Главная, Медиатека, Поиск, Плеер, Настройки |
| `src/components/` | иконки, кнопки, плитки, пустые состояния, обложка, строка трека |
| `src/player/` | движок на `<audio>` + hls.js, очередь, кнопка скорости, громкость, ползунок |
| `src/lib/api.ts` | вызовы Rust (`invoke`) и типы из `docs/API.md` |
| `src/theme/tokens.css` | цвета, радиусы, шрифты, анимации — CSS-переменные |
| `src-tauri/src/providers/` | SoundCloud и Яндекс Музыка: поиск, трек, ссылка на поток |
| `src-tauri/src/stream.rs` | локальный аудио-сервер `127.0.0.1`: `/file`, `/hls`, `/seg` |
| `src-tauri/src/store/` | локальный SQLite по схеме `docs/DB.md` |
| `src-tauri/src/secrets.rs` | токены в Диспетчере учётных данных Windows |
| `src-tauri/src/media.rs` | медиа-клавиши и плашка Windows (souvlaki) |
| `src-tauri/` | Rust: конфиг окна, права, иконки |

Полная карта — `docs/MAP.md`, план — `docs/ROADMAP.md` (блок W).
CI: `.github/workflows/windows.yml` собирает установщик на каждый пуш в `windows/`.
