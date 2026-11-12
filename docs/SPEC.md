# Sonar — техническая спецификация

Как устроено то, что описано в `TZ.md`. API — `API.md`, база — `DB.md`, настройки —
`SETTINGS.md`, алгоритмы — `PSEUDOCODE.md`.

## 1. Архитектура

```
 iPhone (SwiftUI)                 Windows (Rust, позже)
   │  HTTPS + JSON                    │
   └──────────────┬───────────────────┘
                  ▼
        sonar.folzy.ru  (Cloudflare Tunnel)
                  ▼
   Pterodactyl-сервер · Python 3.13 · один процесс
   ┌───────────────────────────────────────────────┐
   │ FastAPI (uvicorn)       aiogram 3 (бот входа) │
   │   routers/  ──►  services/  ──►  SQLite       │
   │                   │ soundcloud.py             │
   │                   │ yandex.py  (yandex-music) │
   │                   │ lastfm.py   lyrics.py     │
   └───────────────────┼───────────────────────────┘
                       ▼
        api-v2.soundcloud.com · api.music.yandex.net · lrclib · Last.fm

 Аудио: клиент ◄── CDN SoundCloud / Яндекса напрямую (сервер аудио не трогает)
 Обновления: клиент ◄── raw.githubusercontent.com/folzy1092/Sonar/main/updates/*.json
                       ◄── github.com/folzy1092/Sonar/releases (IPA)
 selfbot ──► GET /oauth/now (Bearer ключ API)
```

Принципы:
- **Сервер — источник правды** для аккаунта, библиотеки, настроек, статистики.
- **Токены сервисов живут только на сервере.** Клиент просит «дай поток для `sc:123`» —
  сервер ходит в сервис с токеном пользователя и возвращает короткоживущую ссылку на CDN.
- Клиент работает офлайн с локальной копией и очередью изменений.

## 2. Идентификаторы

- **Трек:** `TrackRef` = строка `"<src>:<id>"`.
  - SoundCloud: `sc:2296053116` (числовой id).
  - Яндекс: `ym:12345678` (id трека; альбом хранится в метаданных, нужен для ссылок).
- **Плейлист сервиса:** `scpl:<id>`, `ympl:<uid>:<kind>`. Плейлист Sonar — `pl_<ulid>`.
- **Контекст воспроизведения** (откуда играет, для статистики и `context` в `/oauth/now`):
  `favorites`, `playlist:<id>`, `wave`, `search`, `album:<ref>`, `artist:<ref>`, `queue`.

## 3. Сервер

### 3.1. Стек

| Что | Чем |
|---|---|
| HTTP | FastAPI + uvicorn (1 воркер) |
| БД | SQLite (WAL) через SQLAlchemy 2 async + aiosqlite, миграции Alembic |
| Бот | aiogram 3, long polling в том же процессе |
| HTTP-клиент | httpx (async), таймауты 10 с, ретрай 2× на сетевые ошибки |
| Яндекс | `yandex-music` (MarshalX) — rotor, лайки, плейлисты, download-info |
| SoundCloud | свой модуль на httpx к `api-v2.soundcloud.com` (опыт `sc_api` из selfbot) |
| Пароли | argon2-cffi (argon2id) |
| Шифрование токенов | `cryptography.fernet`, ключ `SONAR_FERNET_KEY` из env |
| Тесты | pytest + httpx `ASGITransport`, без сети (сервисы подменяются) |

### 3.2. Хостинг

- Второй Pterodactyl-сервер, egg Python. Старт: `python -m sonar` (поднимает uvicorn и бота).
- Код тянется из `main` при перезапуске (как selfbot), данные — `server/data/` (вне git).
- HTTPS: `cloudflared` (бинарник в `server/bin/`, как `telegram-bot-api` в selfbot) поднимает
  туннель `sonar.folzy.ru → http://127.0.0.1:<порт>`. Нужны: DNS folzy.ru на Cloudflare
  и токен туннеля в env `CF_TUNNEL_TOKEN`. Входящий порт тогда даже не нужен.
- Запасной вариант без Cloudflare: порт Pterodactyl + сертификат Let's Encrypt (DNS-01).
- Бэкап: раз в сутки копия `sonar.db` (через `VACUUM INTO`) владельцу в Telegram.

### 3.3. Env

`SONAR_FERNET_KEY`, `SONAR_BOT_TOKEN`, `SONAR_OWNER_TG_ID`, `SONAR_PUBLIC_URL`,
`LASTFM_API_KEY`, `LASTFM_API_SECRET`, `YANDEX_OAUTH_CLIENT_ID`, `CF_TUNNEL_TOKEN`, `PORT`.

### 3.4. Аутентификация

- Сессия = случайный токен 32 байта (`secrets.token_urlsafe`), в БД — только SHA-256.
  Клиент шлёт `Authorization: Bearer <session>`. Токен бессрочный, пока не выйдешь/не отзовут;
  `last_seen_at` обновляется не чаще раза в 5 минут.
- Ключ API «сейчас играет» — отдельный токен (`sk_...`), даёт **только** чтение `/oauth/now`.
- Лимиты: вход по паролю — 5 попыток / 15 мин на логин и на IP; регистрация — 5 / час на IP.

### 3.5. Вход через Telegram

```
App ── POST /auth/telegram/start {purpose: login, device} ──► Server
App ◄── {request_id, link: t.me/<bot>?start=login_<secret>, expires_at}
App: показывает ссылку, [Скопировать] [Открыть] [Назад]; опрашивает
     GET /auth/telegram/poll/{request_id} каждые 2 с
Пользователь ── /start login_<secret> ──► Bot
Bot: аккаунт с этим tg_id есть? ── да ──► «Войти в Sonar на iPhone 15 Pro?» [Войти] [Это не я]
                                 └ нет ─► «Создать аккаунт @<username>?» [Создать] [Отмена]
Bot ── confirm ──► Server: request.status = approved, user_id
App ◄── poll: {status: approved, session, user}
```

Привязка (`purpose: link`) — то же, но запрос создаёт уже вошедший пользователь, и бот
просто записывает `tg_id` в его аккаунт.

### 3.6. Проксирование сервисов

`services/soundcloud.py` и `services/yandex.py` реализуют один интерфейс `Provider`:

```
search(q, kind, limit) -> [Track|Album|Artist|Playlist]
track(id) -> Track
stream(id, quality) -> StreamInfo{url, protocol: hls|progressive, codec, bitrate, expires_at, gain_db?}
user_playlists() -> [ServicePlaylist]       # фантомные
playlist_tracks(id) -> [Track]
user_likes() -> [Track]                     # тоже фантомный «плейлист»
related(id) -> [Track]
wave_next(session, feedback) -> [Track]     # SC: эмуляция на related
home_blocks() -> [Block]                    # «Для вас», «Открытия»
lyrics(id) -> Lyrics|None                   # Яндекс отдаёт LRC
```

- Метаданные треков кэшируются в таблице `tracks` (TTL 7 дней) — чтобы списки плейлистов
  отдавались без походов в сервисы.
- `stream` не кэшируется дольше `expires_at - 60 с`.
- SoundCloud: `client_id` + `OAuth <token>` пользователя; поток — `transcodings` → выбираем
  по качеству (HLS AAC 160 / Opus / MP3 128; 256 AAC при Go+).
- Яндекс: `download-info` → лучший кодек ≤ выбранного качества → подписанная ссылка
  (`md5(SALT + path[1:] + s)`, как в библиотеке). Нормализация — из поля `r128`, если есть.

### 3.7. «Моя волна»

- Яндекс: `rotor/station/user:onyourwave/tracks` + `rotor/station/.../feedback`
  (`radioStarted`, `trackStarted`, `trackFinished`, `skip`, лайк). Сессия волны — `batch_id`
  в памяти сервера на пользователя (TTL 1 ч). Настройки волны Яндекса (занятие, характер,
  настроение) — позже.
- SoundCloud-волна: стартовые сиды = 20 последних лайков с SC → `related` → перемешать →
  отсеять прослушанное за 7 дней и дизлайкнутое → порция по 10.

### 3.8. Статистика

- Клиент шлёт `POST /plays` на каждое засчитанное прослушивание
  (`listened_ms ≥ min(30 000, duration/2)`), пачкой, с `played_at`.
- Сервер пишет в `plays`, скробблит в Last.fm (если включено), отдаёт агрегаты
  `GET /stats?period=week|month|year|all` — считаются SQL-запросами на лету (объёмы
  крошечные: ~100 строк/день/пользователь).

### 3.9. «Сейчас играет»

- Клиент шлёт `PUT /player/state` при: старте трека, паузе/плее, перемотке, смене очереди,
  и раз в 30 с во время игры (heartbeat).
- Сервер хранит последнее состояние на пользователя (`player_state`), Last.fm
  `updateNowPlaying` — при смене трека.
- `/oauth/now`: если heartbeat старше 90 с, `is_playing=false`, `state="paused"`.
  `position_ms` экстраполируется: `position + (now - updated_at)`, если играет.

### 3.10. Синхронизация

- Каждая изменяемая сущность (лайк, плейлист, трек в плейлисте, настройки, состояние плеера)
  имеет `rev` — глобальный монотонный счётчик в БД (`sync_rev`).
- Клиент: изменения → локальная очередь операций (`ops`) → `POST /sync/push` пачкой.
  Ответ — новый `rev`. Конфликт по одному ключу — побеждает позднее `client_ts`.
- `GET /sync/pull?since=<rev>` → все изменения после `rev` (включая удаления — tombstones).
- Ручные кнопки: «Отправить» = `POST /sync/replace` (полный снимок с клиента),
  «Получить» = `GET /sync/snapshot` (полный снимок с сервера, клиент перезаписывает своё).
- Настройки — словарь `ключ → значение`; синхронизируются только ключи с пометкой
  `sync: true` в `SETTINGS.md` (вид и жесты — да; кэш, путь к сертификату — нет).

## 4. iOS-клиент

### 4.1. Стек

| Что | Чем |
|---|---|
| UI | SwiftUI, iOS 17+, `@Observable` |
| Проект | XcodeGen (`ios/project.yml`) → `.xcodeproj` генерируется в CI |
| Сеть | URLSession + async/await, свой `APIClient` |
| Локальные данные | SwiftData (кэш библиотеки, очередь ops), Keychain (сессия, P12) |
| Аудио | AVQueuePlayer (бесшовность), AVAudioSession `.playback` |
| Системный плеер | MPNowPlayingInfoCenter + MPRemoteCommandCenter |
| Картинки | свой кэш (NSCache + диск), downscale |
| Подпись (автообновление) | zsign + ZipArchive (из Shadow) |
| Зависимости | SwiftPM; минимум сторонних |

### 4.2. Модули (папки внутри `ios/Sonar/`)

`App` (вход, DI, навигация) · `Core` (APIClient, модели, хранилище, синк) ·
`Playback` (движок, очередь, кэш аудио, now playing) · `DesignSystem` (тема, стекло,
компоненты, цвет обложки) · `Features/*` (экраны) · `Update` (порт ShadowSelfUpdate) ·
`Resources` (строки ru/en, иконки). Подробно — `MAP.md`.

### 4.3. Воспроизведение

- `PlaybackEngine` держит `AVQueuePlayer`, заранее подгружает следующий элемент
  (за 15 с до конца) → бесшовность.
- Ссылка на поток берётся у сервера перед загрузкой элемента; при ошибке 403/410 —
  ещё раз (ссылка протухла), потом — пропуск трека с тостом.
- HLS (SoundCloud) играет AVPlayer нативно. Кэш HLS — `AVAssetDownloadURLSession`;
  progressive (Яндекс) — обычная загрузка файла.
- Нормализация: `AVMutableAudioMix` с громкостью `10^(gain_db/20)`, где `gain_db` —
  `-14 LUFS - loudness трека` (у Яндекса `r128`; у SC — нет данных, без коррекции).
- «При уведомлении»: обработка `AVAudioSession.interruptionNotification` → приглушить /
  пауза / ничего.

### 4.4. Тема под обложку

- `CoverColorExtractor`: обложка → 64×64 → квантование (k-means, k=5) → выбираем кластер с
  лучшим `saturation × sqrt(share)`, отбрасывая почти чёрные/белые → акцент.
- Для фона — тот же цвет, затемнённый до L=12% (тёмная тема) или осветлённый до 92%.
- Контраст текста на акценте: если < 4.5:1 — текст чёрный/белый, что контрастнее.
- `ThemeStore.accent` анимируется `withAnimation(.easeInOut(0.4))`; все компоненты берут цвет
  только из `ThemeStore` — тогда перекрашивается весь интерфейс.

### 4.5. Навигация

Таб-бар (стиль: стандартный / закруглённый / плавающий): **Главная · Медиатека · Поиск ·
Профиль**. Над таб-баром — мини-плеер. Полный плеер — `fullScreenCover` со свайпом вниз.

### 4.6. Автообновление

Порт `ShadowSelfUpdate` (≈2400 строк): `UpdateChecker` (JSON) → `IPADownloader` →
`BundlePreparer` + zsign (переподпись P12 пользователя) → `InstallServer` на
`127.0.0.1:<port>` + `manifest.plist` → `SFSafariViewController` открывает
`itms-services://?action=download-manifest&url=...` → iOS ставит.
Отличия от Shadow: SwiftSignalKit → async/await, Bazel → SwiftPM, manifest — с нашего сервера
(`GET /updates/manifest.plist?ipa=...`) вместо `api.palera.in`.

## 5. Сборка и релизы

- `.github/workflows/ios.yml` (macos-15): XcodeGen → `xcodebuild archive
  CODE_SIGNING_ALLOWED=NO` → `Payload/Sonar.app` → `Sonar.ipa` → GitHub Release
  `build-<N>` + `latest`. Номер сборки — `git rev-list --count HEAD`.
- Объявление обновления — правка `updates/update.json` + запись в `updates/changelog.json`
  (`[skip ci]`), как в Shadow.
- `.github/workflows/server.yml` — pytest на каждый push в `server/`.

## 6. Безопасность

- Пароли argon2id; токены сервисов Fernet; сессии и ключи API — хэши в БД.
- В логах никогда не печатать токены (фильтр в логгере).
- Бот подтверждает вход кнопкой с названием устройства и текстом «Если это не ты — не жми».
- Отвязать Telegram нельзя без пароля (иначе можно потерять вход).

## 7. Локализация

String Catalog (`Localizable.xcstrings`), ru — основной, en. Язык в настройках
(«Системный / Русский / English»), применяется без перезапуска.

## 8. Логи и ошибки

- Сервер: ошибки — владельцу в Telegram (тема «Tests» на этапе разработки), с дедупликацией
  10 мин (как `log_error` в selfbot).
- Клиент: последние 500 строк лога в файле, «Отправить лог» в настройках «О приложении».

## 9. Windows (позже, черновик)

- Rust. UI — **Slint** (нативный рендер, без WebView, ~40–60 МБ RAM) — главный кандидат;
  запасной — Tauri (WebView2, проще стекло, но ~150–200 МБ).
- Аудио: symphonia (декод) + cpal (вывод, выбор устройства), HLS — свой загрузчик сегментов.
- Discord RPC — крейт `discord-rich-presence`. Трей, автозапуск, оверлей, мини-плеер —
  по `reference/pc` (см. `SETTINGS.md`, раздел PC).
- Тот же API сервера — никаких изменений на сервере.
