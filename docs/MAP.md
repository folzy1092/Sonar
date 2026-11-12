# Sonar — карта проекта

Что должно лежать в каждой папке. Папки создаются по мере работы; если файла ещё нет —
значит, этап не начат (см. `ROADMAP.md`).

```
Sonar/
├── CLAUDE.md                 инструкции для агента (читать первым)
├── README.md                 коротко о проекте
├── LICENSE                   проприетарная лицензия
├── .gitignore
│
├── docs/                     вся теория
│   ├── TZ.md                 что делаем и зачем, объём MVP
│   ├── SPEC.md               как устроено: архитектура, стек, алгоритмы
│   ├── API.md                контракт сервера (эндпоинты, JSON)
│   ├── DB.md                 схема SQLite
│   ├── SETTINGS.md           каталог всех настроек с ключами и умолчаниями
│   ├── MAP.md                этот файл
│   ├── PSEUDOCODE.md         псевдокод ключевых алгоритмов
│   └── ROADMAP.md            этапы и план по дням
│
├── reference/                (только локально, в .gitignore) скрины Dotify
│   ├── mobile/               photo_1..20, player, likes
│   └── pc/                   Screenshot_1..18
│
├── updates/                  читается приложением с raw.githubusercontent.com
│   ├── update.json           какую сборку объявить
│   └── changelog.json        изменения по сборкам, новые сверху
│
├── server/                   Python 3.13
│   ├── sonar/                пакет приложения
│   │   ├── __main__.py       `python -m sonar`: uvicorn + бот + cloudflared в одном процессе
│   │   ├── config.py         env → Settings (pydantic-settings)
│   │   ├── app.py            FastAPI(), подключение роутеров, обработчик ошибок
│   │   ├── db/
│   │   │   ├── engine.py     async engine, WAL, сессии
│   │   │   ├── models.py     SQLAlchemy-модели (по DB.md)
│   │   │   └── rev.py        next_rev() — глобальный счётчик синка
│   │   ├── security/
│   │   │   ├── passwords.py  argon2id hash/verify
│   │   │   ├── tokens.py     сессии, ключи API, хэши
│   │   │   ├── crypto.py     Fernet для токенов сервисов
│   │   │   └── ratelimit.py  лимиты входа/регистрации (в памяти)
│   │   ├── routers/          тонкие: валидация → вызов services → ответ
│   │   │   ├── auth.py       register, login, logout, telegram start/poll
│   │   │   ├── me.py         профиль, пароль, устройства
│   │   │   ├── services.py   подключение SC/Яндекса, фантомные плейлисты, импорт
│   │   │   ├── catalog.py    search, tracks, stream, related, lyrics, albums, artists
│   │   │   ├── home.py       главная, волна
│   │   │   ├── library.py    лайки, плейлисты
│   │   │   ├── player.py     состояние, plays, stats
│   │   │   ├── sync.py       pull, push, snapshot, replace
│   │   │   ├── integrations.py  Last.fm, ключ API
│   │   │   ├── now.py        GET /oauth/now (формат Dotify)
│   │   │   └── updates.py    manifest.plist
│   │   ├── providers/        вся работа с внешними сервисами — только здесь
│   │   │   ├── base.py       Protocol Provider + модели Track/StreamInfo/...
│   │   │   ├── soundcloud.py
│   │   │   ├── yandex.py
│   │   │   └── registry.py   ref "sc:…" → нужный провайдер с токеном пользователя
│   │   ├── domain/           логика без HTTP
│   │   │   ├── wave.py       сессии волны, SC-эмуляция
│   │   │   ├── stats.py      агрегаты
│   │   │   ├── sync.py       применение ops, конфликты
│   │   │   ├── now.py        сборка Dotify-JSON из player_state
│   │   │   └── lyrics.py     Яндекс LRC → lrclib (порт из selfbot)
│   │   ├── integrations/
│   │   │   └── lastfm.py     auth, scrobble, updateNowPlaying
│   │   ├── bot/              aiogram 3: вход, привязка, команды админа
│   │   │   ├── handlers.py   /start login_… / link_…, кнопки подтверждения
│   │   │   └── admin.py      /user, /setlogin, /ban, /stats (только владелец)
│   │   └── util/             время, ULID, логирование с фильтром токенов
│   ├── migrations/           Alembic
│   ├── tests/                pytest, без сети: провайдеры подменяются фейками
│   ├── bin/                  cloudflared (бинарник, коммитит workflow)
│   ├── data/                 (вне git) sonar.db, аватарки, картинки фона
│   ├── requirements.txt
│   └── .env.example
│
├── ios/
│   ├── project.yml           XcodeGen: таргеты Sonar, SonarTests; bundle com.folzy.sonar
│   ├── Sonar/
│   │   ├── App/
│   │   │   ├── SonarApp.swift        @main, сцена, обработка ссылок
│   │   │   ├── AppState.swift        вошёл/не вошёл, текущий пользователь
│   │   │   ├── RootView.swift        таб-бар + мини-плеер + полный плеер
│   │   │   └── Dependencies.swift    сборка сервисов (APIClient, Player, Sync…)
│   │   ├── Core/
│   │   │   ├── API/          APIClient, эндпоинты, ошибки, DTO (зеркало API.md)
│   │   │   ├── Models/       Track, TrackRef, Playlist, User, PlayerState…
│   │   │   ├── Storage/      SwiftData-модели кэша, Keychain
│   │   │   ├── Sync/         SyncEngine: очередь ops, pull по таймеру
│   │   │   └── Settings/     SettingsStore: ключи из SETTINGS.md, умолчания, синк
│   │   ├── Playback/
│   │   │   ├── PlaybackEngine.swift  AVQueuePlayer, предзагрузка, ошибки потока
│   │   │   ├── QueueManager.swift    очередь, shuffle, repeat, «следующим», похожие
│   │   │   ├── NowPlaying.swift      MPNowPlayingInfoCenter, RemoteCommandCenter
│   │   │   ├── PlayReporter.swift    plays + /player/state (heartbeat)
│   │   │   ├── AudioCache.swift      кэш и скачивание (HLS и progressive)
│   │   │   └── Normalizer.swift      audioMix по gain_db
│   │   ├── DesignSystem/
│   │   │   ├── ThemeStore.swift      акцент, режим, пресеты, анимация смены
│   │   │   ├── CoverColor.swift      извлечение цвета из обложки
│   │   │   ├── Glass.swift           модификатор стекла по настройкам
│   │   │   ├── Components/           кнопки, тогглы, карточки-опции, ползунки 5 видов,
│   │   │   │                          строка трека, коллаж обложек, нижний лист выбора
│   │   │   └── Gestures/             SwipeActionRow, CoverTapHandler
│   │   ├── Features/
│   │   │   ├── Auth/         вход, регистрация (2 шага), быстрый вход через Telegram
│   │   │   ├── Home/         Моя волна, Для вас, Открытия, Недавнее
│   │   │   ├── Search/
│   │   │   ├── Library/      Любимые, плейлисты, фантомные плейлисты сервисов
│   │   │   ├── Playlist/     экран плейлиста, редактирование, импорт
│   │   │   ├── Player/       полный плеер, мини-плеер, очередь, текст
│   │   │   ├── Profile/      шапка, меню настроек, статистика
│   │   │   └── Settings/     Основные, Аудио, Вид, Плеер, Жесты, Безопасность,
│   │   │                     Сервисы, Интеграции, Кэш, Язык, Приватность(🔒), Автообновление
│   │   ├── Update/           порт ShadowSelfUpdate: проверка, загрузка, переподпись,
│   │   │                     локальный сервер установки, экран обновления
│   │   └── Resources/
│   │       ├── Assets.xcassets       иконка, цвета
│   │       ├── Localizable.xcstrings ru, en
│   │       └── Info.plist            фон. аудио, ATS, URL-схема sonar://
│   ├── Packages/             локальные SwiftPM-пакеты (Zsign, ZipArchive из Shadow)
│   └── SonarTests/           модели, синк, очередь, CoverColor
│
├── windows/                  (позже) Rust: Cargo workspace
│   └── README.md             стек и план (SPEC §9)
│
└── .github/workflows/
    ├── ios.yml               macOS: XcodeGen → archive без подписи → IPA → Release build-N
    └── server.yml            pytest при изменениях в server/
```

## Правила раскладки

- Внешние сервисы (SoundCloud, Яндекс, Last.fm) трогаются **только** в `server/sonar/providers`
  и `server/sonar/integrations`. Роутеры и домен о деталях сервисов не знают.
- В iOS экраны (`Features`) не ходят в сеть напрямую — только через `Core` и `Playback`.
- Цвета и размеры в iOS — только из `DesignSystem` (`ThemeStore`), без хардкода в экранах:
  иначе тема под обложку не перекрасит всё.
- Новая настройка: сначала строка в `SETTINGS.md`, потом ключ в `SettingsStore`.
- Новый эндпоинт: сначала `API.md`, потом роутер, потом DTO в `ios/Sonar/Core/API`.
