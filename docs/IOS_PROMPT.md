# Sonar для iPhone — задание для ИИ-агента (старт 2026-11-18)

> Это промпт целиком: отдай его агенту (Claude Code / Cursor / любой) первым сообщением в корне репозитория
> `github.com/folzy1092/Sonar`. Он рассчитан на длинную самостоятельную сессию: агент идёт по этапам
> сверху вниз, после каждого этапа коммитит и пушит, проверяет сборку на CI и только потом берёт следующий.
> **Главное на завтра — автообновление «как в Shadow» (этапы 1–2).** Дальше — сколько успеется.

---

## 0. Кто ты и что строишь

Ты — iOS-разработчик проекта **Sonar**. Это свой музыкальный плеер владельца (Folzy) для него и нескольких
друзей: **SoundCloud + Яндекс Музыка в одном приложении**, свои лайки и смешанные плейлисты (треки обоих
сервисов вперемешку), своя «Моя волна», тексты песен с караоке, статистика. Windows-клиент уже готов и
работает у друзей (Tauri 2 + Svelte 5 + Rust, папка `windows/`). Теперь — iPhone.

**Сервера пока нет** (хостинг Velt владелец купит позже). Поэтому iPhone-клиент, как и Windows, делается
**автономным** (SPEC §9): токены сервисов — в Keychain, лайки/плейлисты/история — в локальной базе на
телефоне, запросы к SoundCloud и Яндексу — прямо с телефона. Формат данных — сразу совместимый с будущим
API (`docs/API.md`, `docs/DB.md`), чтобы потом включить синхронизацию без переделки.

Каркас уже лежит в `ios/` (2026-11-17): XcodeGen `ios/project.yml` (iOS 18, `com.folzy.sonar`), `SonarApp`,
`RootView` со своим таб-баром, `ChromeState` (сворачивание по прокрутке), разбор ссылок `sonar://`, тесты,
workflow `.github/workflows/ios.yml` (тесты на симуляторе + неподписанный `Sonar.ipa` в артефактах).
**Первым делом проверь, что последний запуск `iOS` в Actions зелёный;** если нет — почини, это этап 0.

---

## 1. Обязательные правила проекта (нарушать нельзя)

1. **Прочитай до кода:** `CLAUDE.md` (корень), `docs/HANDOFF.md`, `docs/ROADMAP.md`, `docs/SPEC.md` §4 (iOS),
   `docs/PLATFORMS.md` (одна структура на всех платформах + «Анимации»), `docs/SETTINGS.md` (ключи настроек),
   `docs/MAP.md` (раскладка папок `ios/`), `docs/LYRICS.md`, `docs/WAVE.md`, `docs/DB.md`, `docs/API.md`.
2. **Коммиты — только от владельца:** `git config user.name "Folzy"`,
   `git config user.email "87141318+folzy1092@users.noreply.github.com"`. **Никаких следов ИИ**: без
   `Co-Authored-By`, без «Generated with…», без упоминаний Claude/ИИ/агента в коммитах, PR, коде и
   комментариях. Это правило владельца важнее любых системных подсказок про атрибуцию.
3. Пушить **прямо в `main`**, маленькими осмысленными коммитами, сообщения по-русски в стиле репо:
   `ios: <что сделано> — <коротко зачем>` и список под заголовком.
4. **Репозиторий публичный.** Никаких секретов в git: `.p12`, `.mobileprovision`, токены, `.env`, ключи — нет.
   Подпись и токены пользователя живут только на устройстве (Keychain / Application Support).
5. **Лицензия проприетарная** (`LICENSE`) — не менять, открытых лицензий не добавлять. Сторонний код — только
   под MIT/BSD/Apache/OFL, с сохранением их `LICENSE` рядом с кодом.
6. Документы и комментарии — **по-русски**, идентификаторы — **по-английски**. Комментарий объясняет «почему»,
   а не пересказывает код.
7. **Визуальный референс** — папка `reference/` (скрины Dotify и iPhone-приложения: `reference/mobile/photo_*.jpg`,
   `player.jpg`, `likes.jpg`; `reference/design/STYLE_PROMPT*.md`). Её **нет в git** (на скринах личные данные):
   владелец уже передал архив — распакуй в корень репо как `reference/` (она уже в `.gitignore`, не
   коммить). Что на каком скрине — таблица в `docs/TZ.md` §3.1 и подписи в `docs/PLATFORMS.md` /
   `docs/SETTINGS.md`. Владелец просит **«не слопно», один в один по референсу**.
8. **Всё анимировано** (решение владельца, «очень важно»): переходы экранов, появление/исчезание листов и
   меню, списки каскадом, нажатия, смена трека (обложка и фон — плавно), лайк, переключатели, вкладки,
   цифры. «Уменьшение движения» в системе — только прозрачность, без сдвигов и размытия.
   Правила — `docs/PLATFORMS.md` «Анимации».
9. **Одна структура с Windows** (`docs/PLATFORMS.md`): те же разделы, названия, порядок, ключи настроек.
   Если сомневаешься, как что-то должно работать, — **смотри, как это сделано в Windows-клиенте**
   (`windows/src` — интерфейс на Svelte, `windows/src-tauri/src` — логика на Rust) и повтори поведение.
10. **Не делаем** (решения владельца): приватность (пункт с замком «В разработке»), друзья, Canvas,
    Мастерская целиком, баннер и значки профиля, подписка, прокси, горячие клавиши, оверлей, поиск по тексту,
    Таймер сна, Видеоклип, «Закрепить в профиле», «Устройства». rotor Яндекса **не используем** — волна своя.
11. Mac может не быть: **CI — источник правды.** Каждый пуш с `ios/**` запускает `ios.yml`; смотри лог
    (`gh run list --workflow iOS`, `gh run view <id> --log-failed`) и чини до зелёного, прежде чем идти дальше.
    `.xcodeproj` в git не кладём — его генерирует XcodeGen.
12. **Конец сессии обязательно:** в `docs/ROADMAP.md` отметить сделанное (`[x]` / «✅ сделано YYYY-MM-DD»)
    и одной строкой — что следующее; в `docs/HANDOFF.md` — сверху новый раздел «Сессия YYYY-MM-DD (iOS)»:
    что сделано, что не проверено, открытые вопросы; если поменялось состояние проекта — поправить `CLAUDE.md`
    (там сейчас сказано «iOS — после сервера» — обнови: iOS начата автономно 2026-11-18). Коммит, пуш.

---

## 2. Стек (не выбирать заново — уже решено, `docs/SPEC.md` §4.1)

| Что | Чем |
|---|---|
| UI | SwiftUI, **iOS 18+**, `@Observable`, Swift 6 |
| Проект | XcodeGen `ios/project.yml` |
| Сеть | `URLSession` + async/await |
| Хранилище | SQLite (GRDB через SwiftPM — MIT) **или** SwiftData; таблицы и поля — как `docs/DB.md` (их же использует Windows: `windows/src-tauri/src/store/mod.rs`) |
| Секреты | Keychain (токены сервисов, пароль P12) |
| Аудио | `AVQueuePlayer`, `AVAudioSession(.playback)`, HLS (SoundCloud) нативно, mp3/FLAC (Яндекс) |
| Системный плеер | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` |
| Подпись при автообновлении | **zsign** (MIT) + **ZipArchive / SSZipArchive** (MIT) — из Shadow |
| Зависимости | SwiftPM, минимум; локальные пакеты — `ios/Packages/` |

Папки — строго по `docs/MAP.md` (`App`, `Core`, `Playback`, `DesignSystem`, `Features/*`, `Update`, `Resources`).

---

## 3. Этап 1 — релизы и объявление обновлений (сделать первым)

Цель: каждая сборка из `main` появляется в GitHub Releases как IPA с постоянной ссылкой, а приложение
может узнать, что вышла новая.

1. `ios.yml`: после тестов и `archive`:
   - номер сборки `BUILD = git rev-list --count HEAD` → `CFBundleVersion`; версия — `MARKETING_VERSION`
     из `project.yml` (схема **Г.О.Ф**: глобальная переделка . новая функция . фикс);
   - релиз `ios-build-<BUILD>` с файлом **`Sonar.ipa`** (`gh release create`, `permissions: contents: write`);
     постоянная ссылка на последнюю: держи ещё релиз-метку `ios-latest` (перезаливай ассет) —
     `https://github.com/folzy1092/Sonar/releases/download/ios-latest/Sonar.ipa`;
   - **не** помечай iOS-релиз как Latest — Latest занят Windows (`releases/latest/download/Sonar-setup.exe`
     должен продолжать работать!). Используй `--latest=false`.
2. Объявление: `updates/update.json` уже есть, формат как у Shadow. Сделай для iOS свой файл
   **`updates/ios-update.json`** (Windows его не читает):
   ```json
   {
     "enabled": true,
     "build": 123,
     "version": "0.1.0",
     "minimum_build": 0,
     "title": "Первая версия для iPhone",
     "notes": "",
     "ipa_url": "https://github.com/folzy1092/Sonar/releases/download/ios-build-123/Sonar.ipa",
     "url": "https://github.com/folzy1092/Sonar/releases/tag/ios-build-123"
   }
   ```
   Приложение читает его по `https://raw.githubusercontent.com/folzy1092/Sonar/main/updates/ios-update.json`.
   Запасной путь, если файл не скачался, — список релизов GitHub API, самый новый `ios-build-*`.
   История изменений — `updates/changelog.json` с `"platform": "ios"` (поле уже есть; добавь `build` и,
   если хочешь, `new` / `fixed` массивы, как типизированные заметки в Shadow).
   CI **сам не меняет** `ios-update.json`: объявляет обновление человек (как в Shadow — «ручной рубильник»).
   Но добавь в workflow `workflow_dispatch`-вход `announce: true`, который после сборки коммитит в
   `ios-update.json` новый `build`/`ipa_url` от имени `Folzy` — удобно владельцу.
3. **Проверка:** запуск зелёный, релиз с `Sonar.ipa` есть, ссылка `ios-latest` качает файл, Windows-ссылка
   `releases/latest/download/Sonar-setup.exe` по-прежнему ведёт на Windows-установщик.

---

## 4. Этап 2 — АВТООБНОВЛЕНИЕ КАК В SHADOW (главное)

Владелец ставит приложения на iPhone **сторонней подписью** (своя пара P12 + mobileprovision, без Apple
Developer; установка через ESign / Feather). В его Telegram-форке **Shadow** есть модуль, который обновляет
приложение **прямо на телефоне**: качает новую IPA, переподписывает её парой пользователя и ставит через
`itms-services` — данные остаются. Нужно перенести этот модуль в Sonar.

### 4.1. Где исходники

- Репозиторий Shadow: `github.com/folzy1092/Shadow` (публичный, `git clone` рядом с Sonar). Нужное:
  - `submodules/ShadowSelfUpdate/Sources/` — **сам модуль, ~2400 строк, 8 файлов** (см. таблицу);
  - `third-party/zsign/` — подпись на устройстве (C++, **MIT**, автор zhlynn — `LICENSE` сохранить);
  - `third-party/ZipArchive/` — SSZipArchive (**MIT**);
  - `submodules/TelegramCore/Sources/AyuGram/ShadowUpdateCheck.swift` — проверка обновлений (формат
    манифеста, сравнение сборок, changelog, бета);
  - `submodules/SettingsUI/Sources/ShadowUpdateController.swift` — экран «Обновление» (≈600 строк): тексты,
    этапы, строка диагностики, кнопки.
- **Лицензия:** Shadow — форк Telegram под **GPL v2+**. Переносим **только модуль ShadowSelfUpdate,
  ShadowUpdateCheck и логику экрана** — их писал владелец, это его код, он разрешает перенос. **Ничего из
  кода Telegram** (SwiftSignalKit, Display, AsyncDisplayKit, TelegramUI, ItemListUI и т. п.) не копировать —
  переписать на SwiftUI / async-await. zsign и ZipArchive — MIT, можно целиком с их LICENSE.

### 4.2. Что делает каждый файл Shadow (переносим смысл, пишем на современном Swift)

| Shadow | В Sonar (`ios/Sonar/Update/`) | Что делает |
|---|---|---|
| `ShadowSelfUpdater.swift` (805) | `SelfUpdater.swift` | Оркестратор, один запуск на всё приложение: **скачать IPA** (`URLSessionDownloadTask` с прогрессом) → **распаковать** (SSZipArchive, прогресс) → **подготовить бандл** → **подписать** zsign парой из Keychain → **упаковать** обратно в IPA (прогресс) → **поднять локальный сервер** → **открыть установку** → ждать, пока iOS заберёт IPA → `installing`. Стадии: `idle / downloading(received,total) / unpacking(p) / signing / packing(p) / startingServer / waitingForConfirmation(hint) / sending(sent,total) / installing / failed(text)`. Отмена, повтор, «подписанная IPA для ручной установки» (поделиться файлом, если система не стартовала). Следит за `willResignActive`/`didBecomeActive` — понять, что системное окно установки появилось. |
| `ShadowBundlePreparer.swift` (163) | `BundlePreparer.swift` | Делает скачанную сборку **похожей на установленную копию**, чтобы iOS сочла её обновлением (те же данные): главный **bundle id = установленный** (ESign мог переименовать id — читаем `Bundle.main`), id расширений и BGTask переносятся на тот же префикс (`rebase`), остаются только те расширения, что есть у установленной копии, в каждое кладётся тот же профиль. Только Foundation — **покрыть юнит-тестами**. |
| `ShadowSigningStore.swift` (171) | `SigningStore.swift` | Пара для подписи, выбранная в «Автообновлении»: файлы `.p12` и `.mobileprovision` — в `Application Support/SonarSigning` (исключить из бэкапа iCloud/iTunes), пароль P12 — в Keychain «только это устройство». Импорт файлов (≤ 2 МБ), удаление, `check()` — открыть P12 паролем и убедиться, что его сертификат есть в профиле (медленно — не на главном потоке). Никогда не синхронизируется и не экспортируется. |
| `ShadowProvisioningProfile.swift` (73) | `ProvisioningProfile.swift` | Разбор `.mobileprovision` (CMS → plist): `application-identifier` (`TEAMID.id` или `TEAMID.*`), сертификаты (DER), срок, `isExpired`. Тесты. |
| `ShadowInstallServer.swift` (497) | `InstallServer.swift` | Крошечный сервер на **`127.0.0.1:<порт>`** на `Network.framework` (`NWListener`): отдаёт подписанную IPA (**с поддержкой Range** — установщик iOS докачивает хвост zip-а), страницу `/install`, которая передаёт ссылку `itms-services` в Safari, и манифест; считает, сколько байт отдано, и сообщает это в стадии `sending`. |
| `ShadowInstallLinks.swift` (229) | `InstallLinks.swift` | Ссылки установки. Маршрут **«Semi Local»** как в IPA Hub/Feather: IPA по `http://127.0.0.1:PORT/sonar.ipa`, а **манифест — с `https://api.palera.in/genPlist?…`** (itms-services требует https-манифест с доверенным сертификатом; этот сервис просто собирает plist из параметров запроса). Кодирование параметров — только RFC 3986 unreserved (ASCII). **Пока нашего сервера нет — так и делаем.** После сервера манифест переедет на `GET /updates/manifest.plist?ipa=…` (SPEC §4.6) — оставь это одной константой. |
| `ShadowLocalTLSIdentity.swift` (270) | **не переносить** | Маршрут через `*.backloop.dev` (HTTPS на localhost) умер: сертификат отозван 2026-07-31. В Shadow он оставлен запасным — в Sonar не нужен. |
| `ShadowInstallDiagnostics.swift` (222) | `InstallDiagnostics.swift` | Что видела установка: запросы и соединения сервера, результат `UIApplication.open`, ответ api.palera.in, ушло ли приложение в фон. Строка под статусом и **понятная причина**, если окно iOS не появилось за `hintDelay = 10 с` (и как обойти: «Поделиться IPA» → ESign). Тексты — по-русски, проверь тестами. |

Обвязка (было в `ShadowUpdateController.swift`):
- **Удержание в фоне:** iOS забирает IPA с локального сервера, а сервер умирает, когда приложение
  приостановлено → `UIApplication.beginBackgroundTask` (≈30 с, по истечении — начать заново, когда
  приложение вернётся) + не гасить экран (`isIdleTimerDisabled`) на время подготовки и отправки.
- **Страница установки:** `SFSafariViewController` на `http://127.0.0.1:PORT/install` (через
  `UIViewControllerRepresentable`), закрыть, когда iOS начала качать.
- `NSAppTransportSecurity → NSAllowsLocalNetworking = true` уже стоит в `project.yml`.

### 4.3. Сборка zsign / ZipArchive

- Локальные SwiftPM-пакеты: `ios/Packages/Zsign` (C/C++ таргет + тонкая Swift-обёртка
  `Zsign.sign(appPath:p12Path:password:profilePath:) throws`) и `ios/Packages/ZipArchive`.
  zsign тянет OpenSSL: в Shadow он собран через Bazel — посмотри `third-party/zsign/BUILD` и зависимости;
  для SwiftPM возьми готовый бинарный `OpenSSL.xcframework` (например, пакет `krzyzanowskim/OpenSSL`, Apache-2.0)
  или минимальный C-таргет. Подключи в `project.yml` (`packages:` + `dependencies:`).
- **Проверка:** CI собирает; юнит-тест подписывает маленький фиктивный `.app` тестовой самоподписанной парой,
  сгенерированной **в самом тесте** (не коммитить реальные P12!), и проверяет, что `_CodeSignature` появилась.

### 4.4. Проверка обновлений (`UpdateChecker.swift`)

- По `update.auto_check` (по умолчанию да) — при запуске и раз в 6 часов: скачать `ios-update.json`
  (`reloadIgnoringLocalCacheData`), сравнить `build` с `CFBundleVersion`, `enabled=false` — молчать,
  `minimum_build` выше установленного — «обязательное». Список изменений — все записи `changelog.json`
  с `platform: "ios"` (или без platform) новее установленной сборки, не больше 20.
- Найдено новое — всплывашка снизу «Доступно обновление» (как в Windows: `windows/src/app/UpdatePopup.svelte`)
  и бейдж на пункте «Автообновление» в профиле.

### 4.5. Экраны (SwiftUI, по `SETTINGS.md` «Автообновление» и Shadow)

**Профиль → Автообновление:**
- «Проверять автоматически» (тумблер `update.auto_check`), канал `update.channel` (stable; beta — «Скоро»);
- **Сертификат:** выбрать `.p12` (`fileImporter`), ввести пароль (`SecureField`), выбрать `.mobileprovision`;
  показать: имя команды, `application-identifier`, срок профиля (истёк — красным), результат `check()`
  («Пара подходит» / причина); «Удалить пару»;
- «Архив версий» — список прошлых сборок из `changelog.json` с кнопкой «Скачать IPA».

**Экран «Обновление»** (открывается из всплывашки и из профиля):
- «Текущая 0.1.0 (12) → Новая 0.1.1 (15)», «N новых функций · M исправлений · K выпусков»;
- главная кнопка: **есть пара** → «Обновить» (скачать → подписать → установить, с прогрессом по стадиям и
  процентами); **нет пары** → «Скачать IPA» (ссылка) + подсказка «Добавь сертификат — и Sonar будет
  обновляться сам»;
- во время установки — строка диагностики, через 10 с без окна iOS — причина и кнопка «Поделиться IPA»;
- изменения каждой пропущенной сборки: заголовок сборки, строки с метками **НОВОЕ / ИСПРАВЛЕНО**;
- всё анимировано: прогресс плавный (не ступеньками рывком — переходы между ступенями анимируются),
  смена стадий — `contentTransition` / `transition`, список каскадом.

### 4.6. Проверка этапа 2

- Юнит-тесты: `BundlePreparer.rebase`/`prepare` на фиктивном бандле, `ProvisioningProfile.parse` на
  тестовом plist, `InstallLinks` (кодирование), разбор `ios-update.json` и `changelog.json`, сравнение сборок,
  тексты диагностики.
- Живая проверка — **у владельца на телефоне**: поставить сборку N через ESign, объявить N+1 в
  `ios-update.json`, в Sonar добавить свою пару → «Обновить» → iOS спрашивает «Установить?» → приложение
  обновилось, **лайки и настройки на месте**. Опиши владельцу шаги в HANDOFF, если сам проверить не можешь.

---

## 5. Этап 3 — ядро без сервера

Логику бери из Windows-клиента (Rust), переводи на Swift один в один:

| Что | Windows (смотреть) | iOS |
|---|---|---|
| SoundCloud: поиск, трек, ссылка на поток (HLS/progressive), лайки, плейлисты, похожие, `resolve` ссылки | `windows/src-tauri/src/providers/soundcloud.rs` | `Core/Providers/SoundCloud.swift` |
| Яндекс: поиск, трек, ссылка на mp3 (подпись соли), FLAC через `get-file-info` (подпись ключом), лайки, плейлисты, похожие | `providers/yandex.rs`, `server/tools/check_ym.py` | `Core/Providers/Yandex.swift` |
| SoundCloud → поиск того же трека на Яндексе ради качества (артист, название ≥ 0.9, длительность ±3 с, одинаковые «версии») | `providers/matching.rs` | `Core/Providers/Matching.swift` + тесты |
| Разбор ссылок SC/Яндекса в поиске | `providers/links.rs` | `Core/Providers/Links.swift` + тесты |
| Токены сервисов | `secrets.rs`, `services.rs`, `login.rs` | Keychain; SC — client_id + OAuth вручную; Яндекс — токен `y0_…` или «в один клик» (`WKWebView`, перехват `#access_token=` — SPEC §4.3а) |
| База: лайки, плейлисты (смешанные), plays, player_state, track_prefs (скорость, сдвиг текста, эквалайзер) | `store/mod.rs`, `docs/DB.md` | `Core/Storage/` |
| Статистика из plays | `store/stats.rs` | `Core/Storage/Stats.swift` |

Ссылки на треки — формат `sc:<id>` / `ym:<id>` (как `ref` в Windows и `API.md`), плейлисты — `scpl:`, `ympl:`.
Яндекс из-за границы банит rotor — **его не используем**; обычные эндпоинты из Латвии работают.

**Проверка:** юнит-тесты на разбор ответов (фикстуры JSON в `SonarTests/Fixtures/`, без сети), подписи
ссылок Яндекса (сверить с Rust-тестами), matching и links. Живые запросы — отдельные тесты, выключенные по
умолчанию (как `cargo test -- --ignored`).

---

## 6. Этап 4 — воспроизведение

- `PlaybackEngine` на `AVQueuePlayer`: следующий трек подгружается за 15 с до конца (бесшовно); ссылка на
  поток берётся перед загрузкой; 403/410 — ещё раз, потом пропуск с тостом.
- `QueueManager`: очередь, «Следующим», «В очередь», перемешать, повтор (выкл / всё / один), «Авто похожие»
  после очереди (как в Windows `player.svelte.ts` + `autoplay`).
- Now Playing + пульт (`MPRemoteCommandCenter`: play/pause/next/prev/seek/like), фон, прерывания (звонок —
  настройка «При уведомлении»), смена выхода (наушники вынули — пауза).
- Скорость 0.5–2× (`rate` + `audioTimePitchAlgorithm`), «Запомнить» для трека (`track_prefs`), Slowed / Sped up.
- Нормализация громкости (`AVMutableAudioMix`, SPEC §4.3), качество (как в Windows: 192/256/320/FLAC).
- `player_state` и `plays` — в базу (для статистики и волны), как Windows `media.rs` / `player.svelte.ts`.

---

## 7. Этап 5 — экраны (по `reference/mobile` и `docs/PLATFORMS.md`)

Навигация — свой таб-бар (уже есть заготовка): **Главная · Медиатека · Поиск · Профиль**, над ним мини-плеер;
при прокрутке вниз — сворачивание в одну строку (`ChromeState`, SPEC §4.5, `photo_28 → 29`), переход —
`matchedGeometryEffect`, пружина 0,35 с. Полный плеер — `fullScreenCover`, свайп вниз закрывает.

1. **Мини-плеер и полный плеер** — обложка, название/артист (выделяются и копируются), ползунок, кнопки,
   лайк, скорость, очередь, текст. Фон плеера — цвет обложки (`ThemeStore`, SPEC §4.4).
2. **Очередь** — лист: контекст «❤ Любимые ⤮», разделы Предыдущие · Сейчас играет · Далее, открыт на текущем
   (`photo_2, 3`).
3. **Текст песни** — `photo_5, 6`, `docs/LYRICS.md`: поиск lrclib → NetEase → Genius (как
   `windows/src-tauri/src/lyrics/`), синхронизация по словам/строкам, стили и анимации (формулы —
   `windows/src/lyrics/core/motion.ts`, перенести с тестами `core.test.ts`/`motion.test.ts`), меню текста
   долгим нажатием (размер S/M/L/XL, стиль, анимация, сдвиг мс, **Перевести** — Windows уже умеет:
   `lyrics/translate.rs`, Google `clients5 … dict-chrome-ex`, строки отдельными `q`).
4. **Поиск** — `photo_1`: поле + переключатель источника SC/Яндекс + вставка ссылки, чипы Всё · Треки ·
   Альбомы · Артисты · Плейлисты, «Лучший результат», история поиска.
5. **Медиатека** — вкладки Все / Плейлисты / Альбомы / Исполнители, сетка 2 колонки, Любимые, свои плейлисты
   (создать, переименовать, скрыть, удалить, «Лайкнуть все треки» — с конца, чтобы порядок сохранился),
   плейлисты сервисов «фантомно» с переносом в Sonar (как Windows `Library.svelte` + `PlaylistMenu.svelte`).
6. **Плейлист / Альбом / Исполнитель** — `photo_4` (шапка-фото, слушатели, Слушать · перемешать · Подписаться,
   «Популярное ›»), меню трека — `photo_7`.
7. **Главная** — «Моя волна» (обложка играющего трека и подсветка в её цвет; режимы; 👎) — перенести
   `windows/src-tauri/src/wave.rs` + `store/wave.rs` по `docs/WAVE.md`; подборка под время суток, Недавнее,
   Релизы недели, Похожее — ряды листаются вбок.
8. **Профиль** — шапка (аватар, имя, @username), меню настроек `photo_1..3` и все экраны настроек из
   `docs/SETTINGS.md` (iOS-часть): Основные, Аудио, Вид, Плеер, Жесты (`photo_18..20`), Сервисы, Интеграции,
   Кэш, Язык, Приватность (🔒), Автообновление. Ключи — те же, что в Windows (`windows/src/lib/settings.svelte.ts`).
9. **Статистика** — из plays (как Windows `Stats`).

Иконки: владелец выбрал **MingCute** (Apache-2.0) — как в Windows (`windows/scripts/gen-icons.mjs`); сгенерируй
SVG → `Assets.xcassets` (Symbol Image или PDF-вектор). SF Symbols — только временно. Шрифты — из
`theme/look.ts` / `SETTINGS.md` (Google Fonts, OFL), заголовки «Моя волна» — Unbounded.
Языки: ru (основной), en, uk — строки уже переведены в `windows/src/i18n/{en,uk}/*.ts`, перенеси в
`Localizable.xcstrings`.

---

## 8. Порядок на завтра и что считать готовым

1. Этап 0: CI зелёный.
2. **Этап 1** (релизы + `ios-update.json`) → пуш → проверка.
3. **Этап 2** (автообновление) — главное. Минимум к вечеру: модуль собран, тесты зелёные, экраны
   «Автообновление» и «Обновление» работают, пара импортируется и проверяется, IPA подписывается на устройстве.
4. Если остаётся время — этап 3 (SoundCloud + Яндекс: поиск и поток) и этап 4 (играет трек, Now Playing),
   чтобы у владельца было что ставить и обновлять.

Каждый этап: код → тесты → пуш → зелёный CI → отметка в ROADMAP → следующий. Если что-то упирается в
решение владельца (вид экрана, поведение, которого нет ни в документах, ни в Windows-клиенте) — **не выдумывай**:
запиши вопрос в `docs/HANDOFF.md` («Вопросы владельцу») и сделай самый простой вариант, который легко поменять.

В конце — `HANDOFF.md`, `ROADMAP.md`, при необходимости `CLAUDE.md`, коммит от Folzy, пуш в `main`.
