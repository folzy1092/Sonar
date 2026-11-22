# Sonar — каталог настроек

Каждая настройка — ключ `раздел.имя`, хранится как JSON-значение. **sync** — уходит на сервер
и одинакова на всех устройствах. Ключи общие для iOS и Windows, если смысл совпадает.
Референс — файл в `reference/` (только локально).

**Подача на ПК** (NEXT_PROMPT «Этап 0» п. 4–6, 2026-11-18; ключи и порядок пунктов на экране не
менялись — только вид): у каждого подраздела и группы — строка «что это меняет»; сверху главные
пункты, хвост раздела — под свёрнутым «Ещё настройки» (`components/settings/More.svelte`). Сверху панели —
**поиск по настройкам**: каталог `lib/settings-catalog.ts` (раздел, подраздел, название,
подсказка, синонимы), клик по результату открывает раздел, раскрывает «Ещё настройки» и
подсвечивает пункт (`lib/settings-jump.ts`). Выбор вида — **плитки-картинки** со схемой окна
(`Tiles.svelte` + `WindowDiagram.svelte`, выбранная — с рамкой акцента и `use:indicator`);
у неочевидного — живое превью (мини-плеер целиком — `MiniPreview.svelte`, вкладки — схема
окна). Панель — во всю ширину окна с отступами, содержимое в 1–2 колонки по ширине.
Новый пункт настроек добавлять ещё и в каталог поиска (тест `settings-catalog.test.ts`).

## Меню настроек iOS (`mobile/photo_1..3`)

Порядок и названия разделов **те же, что вкладки на Windows** (`docs/PLATFORMS.md`):

```
[Шапка профиля: аватар, имя, @username, #номер, дата регистрации] [Поделиться] [✎]
Аккаунт:     Статистика · Безопасность · Приватность
Интерфейс:   Вид (на ПК с 2026-11-18 — вместе с вкладками) · Вкладки (iOS)
Плеер:       Аудио · Вид плеера · Очередь (на ПК с 2026-11-18 — внутри «Плеера») · Мини-плеер · Жесты
Сервисы:     SoundCloud · Яндекс Музыка · VK Музыка   (PC: карточки — из реестра сервисов, только работающие; iOS — прежний ServicesView)
Интеграции:  Ключ API
Система:     Общее (язык, платформа, медиатека, синхронизация; внизу — о приложении) · Клавиши (PC) · Обновления · Хранилище
О приложении (низ «Общего»): знак, название, версия (двойной клик по знаку — проверка обновлений) ·
             Сайт (`sonar.folzy.ru`) · Телеграм (t.me/SonarUpdates) · Соглашение · Конфиденциальность ·
             Сбросить настройки · Выйти
```
Убрано: Подписка, Прокси, Кастомизация, Мастерская, Discord (только Windows).

## Основные — `general.*` (`photo_11`, `pc/16`)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `general.platform` | key работающего сервиса из реестра (`API.md` §2 «Префиксы ref»): `soundcloud` / `yandex` | `soundcloud` | да |
| `general.restore` | `none` / `track` / `queue` | `queue` | да |
| `general.similar_autoplay` | bool | `true` | да |
| `general.add_position` | `start` / `end` | `start` | да |
| `general.language` | `ru` / `en` / `uk` / `es` / `de` / `pl` (SPEC §7) — язык интерфейса, меняется на лету (Windows: `lib/i18n.svelte.ts`, ключ перевода — русская строка, словари `src/i18n/{en,uk,es,de,pl}/*.ts`; нет строки в es / de / pl — английская). Выбор — раскрывающийся по клику список с флагами, пункты каскадом (iPhone — лист) | язык системы, если он в списке, иначе `ru` (ПК — `lib/system-lang.ts`) | нет |

Кнопки «Отправить на сервер» / «Получить с сервера» — действия, не настройки.
`general.platform` — откуда главная берёт волну и рекомендации. Значение — `key` сервиса (не короткий id);
в выборе только работающие сервисы реестра с похожими треками (`caps.similar`), значения и умолчание прежние.
С 2026-11-18 на ПК в выборе и `vk`: волна стартует от «Моей музыки» VK, если VK подключён (иначе — SoundCloud);
на iOS выбор пока SoundCloud / Яндекс. Spotify в выбор не попадает — рекомендаций Spotify не берём (API.md §2 «Spotify»).

**Сервисы** (2026-11-18): список сервисов — реестр (Windows `lib/services.ts`, iOS `Core/Models/ServiceRegistry.swift`),
в его порядке; показываются только работающие сервисы (сейчас SoundCloud, Яндекс Музыка, YouTube Music, VK Музыка, Spotify и файлы с компьютера), остальные скрыты
до готовности, без «скоро». Windows: карточка `pages/settings/ServiceCard.svelte` — статус (имя аккаунта, плашка
«Премиум», если сервис сообщает о подписке), «Войти», «Вручную» — вставить ключ (`connect_service_key`, ключ
проверяется запросом и уходит в keyring), «Отключить». iOS — прежний экран `ServicesView`, Spotify там — своя секция
`SpotifyServiceSection` (окно входа или поле «Ключ sp_dc»). Spotify без Premium (и всегда на iPhone) — медиатека и
ссылки, подпись «Spotify — медиатека и ссылки; играет резервный сервис.». Настроек в `settings`
у раздела нет: ключи — только в Keychain / keyring.

iOS (2026-11-17, Система → **Общее**, `Features/Settings/System/GeneralSettingsView.swift`): Язык (лист из
трёх, меняется сразу — `Core/I18n/`: `t("русская строка")`, `tn(n, …)`, словари `Strings+Windows.swift` из
`windows/src/i18n` генератором `ios/scripts/gen-i18n.mjs` + `Strings+iOS.swift`), Платформа, Медиатека →
Добавление, Синхронизация (две строки «С сервером»), внизу «О приложении» (знак — двойной тап проверяет
обновления, версия, Сайт · Телеграм · Соглашение · Конфиденциальность, «Сбросить настройки» с подтверждением).
«Авто похожие» — в Очереди.

### Виджет и Siri — `widget.*` (только iOS, 2026-11-17)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `widget.quick_playlist` | `liked` (Любимые) / `downloaded` (Скачанные) / ref плейлиста сервиса из Медиатеки (`scpl:<id>`, `scpl:likes`, `ympl:<uid>:<kind>`, `ympl:likes`, `ytpl:<id>`, `ytpl:likes`); пусто или непонятное — Любимые (`Core/Shortcuts/PlayTarget.swift` `QuickPlaylist`) | `liked` | нет |
| `widget.quick_playlist_title` | название выбранного плейлиста сервиса — показать строку без сети | `""` | нет |

iOS: Система → **Общее** → «Виджет и Siri» → «Быстрый плейлист» (лист `QuickPlaylistSheet`: Любимые, Скачанные,
плейлисты SoundCloud и Яндекса). Его играют кнопка «Быстрый плейлист» виджета (`sonar://play/quick`) и команда
Siri / «Команд» «Быстрый плейлист». Другие ссылки виджета — `sonar://play/liked` и `sonar://play/wave`
(`App/DeepLink.swift` → `Playback/QuickPlay.swift`). Виджет — цель `SonarWidget` (`ios/SonarWidget/`): средний —
три кнопки, маленький — одна на выбор («Изменить виджет» → «Что включать»). Он статичный: App Groups сторонняя
подпись не даёт, данных приложения виджет не видит. В том же расширении (iOS 18) — «Моя волна» без настроек:
кнопка Пункта управления (её же можно поставить на экран блокировки вместо фонарика и на кнопку действия;
интент `Core/Shortcuts/OpenWaveIntent.swift` открывает Sonar ссылкой `sonar://play/wave`, значок — свой символ
знака `sonar.mark` из `ios/scripts/gen-symbol.mjs`) и значки экрана блокировки — круглый (знак) и
прямоугольный (знак и «Моя волна»), касание — `sonar://play/wave`. Подпись — та же пара, что у приложения
(одна `SonarWidget.appex`). Команды Siri (`App/SonarIntents.swift`, App Intents, без
entitlement): «Моя волна», «Любимые», «Быстрый плейлист», «Пауза», «Продолжить», «Следующий трек» — играют в
фоне, Sonar не открывается. У Siri нет русского: голосом — английские фразы (`Resources/en.lproj/AppShortcuts.strings`,
«Play My Wave in Sonar»), по-русски команды — в приложении «Команды» и в Spotlight.

## Главная — `home.*` (подборки «Для тебя», ПК, 2026-11-18)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `home.similar_seed` | трек-затравка подборки «Похоже на трек»: `{ref, title, artist, cover_url}`, выбирается на её странице («Выбрать трек»: Любимые, медиатека и недавнее); пусто — последний прослушанный трек | `null` | нет |

Подборки «Для тебя» (`windows/src/lib/home-mixes.ts`, `pages/mixes.svelte.ts`) — «Твой вечер/утро/день/ночь»,
«Недавнее», «Новое для тебя» (похожее на любимое без исполнителей из истории и Любимых), «Свежие артисты» (то же, но
меньше 50 000 прослушиваний на SoundCloud — у Яндекса счётчика нет, его треки сюда не идут), «Похоже на трек». Клик
по карточке открывает страницу подборки (`router.go('mix', id)`): «Слушать», «Перемешать», «Сохранить как плейлист».
Сетевые подборки держатся до полуночи в `localStorage` (`sonar.home-mixes`), не в настройках.

## Статистика — `stats.*` (Аккаунт → Статистика, TZ photo_7, 8 без друзей)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `stats.period` (iOS) | `week` / `month` / `year` / `all` — открытый период | `month` | нет |
| `stats.recap_seen` | итоги, которые уже открывали или скрыли: id через запятую, старые первыми, до 24 последних (`month-2026-10,year-2026`); такое приглашение на Главной второй раз не приходит, открыть старые итоги из Статистики — не возвращает приглашение | `""` | да |

iOS (2026-11-17, `StatsView`): по журналу прослушиваний на телефоне (`Core/Stats/PlayLog.swift`,
`plays.json`; пишет `PlayHistory`, старая история переносится один раз) — время (часы / минуты со счётом),
прослушивания, треки, артисты, «к прошлому периоду», столбики по дням / месяцам (тап — время дня), кольцо по
часам суток с пиком, дни недели, серия дней, треков в день, любимый день, топ-10 артистов (страница артиста)
и треков (играть с него). Подсчёт — `ListeningStats.swift`, как Windows `store/stats.rs`.

**Итоги месяца и года** (2026-11-18, ПК и iPhone): Статистика → «Итоги» — годы и до 12 месяцев с
прослушиваниями; на Главной — приглашение в первую неделю месяца (итоги прошлого месяца) и с декабря по
первую неделю января (итоги года; когда год уже открыт — в первую неделю ещё и прошлый месяц), если за
период набралось от 30 минут. Карточки на весь экран: минуты,
топ-5 треков и артистов, новый артист, любимый час, самый длинный день, «на повторе N раз», сервисы в %.
Цвета — из обложки первого трека топа. Подсчёт — Windows `store/recap.rs`, iOS `Core/Stats/Recap.swift`.

## Аудио — `audio.*` (`photo_12`, `pc/4,5`)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `audio.quality` | `low`(192) / `medium`(256) / `high`(320) / `max`(от 1411, FLAC Яндекса; нет FLAC — 320). SoundCloud отдаёт максимум сам (AAC 160, с Go+ — 256) | `max` | нет |
| `audio.yt_quality` | `normal` / `high` — YouTube Music. ПК: Обычное — AAC 128, Высокое — Opus 160 (Opus 256 Premium не берём: поток идёт гостем, плееры с cookie требуют расшифровки подписи ссылок). iPhone — тот же ключ, только AAC (AVPlayer не играет Opus): Обычное — AAC 128, Высокое — AAC 256, если есть, иначе 128. Плеер → Аудио → «YouTube Music» | `high` | да |
| `audio.fallback` | bool — **резервный сервис** (NEXT_PROMPT этап 4): свой сервис трек не играет — недоступен (`available:false`, заблюрен на Яндексе), только отрывок (превью Яндекса, `SNIP` SoundCloud), Spotify без Premium, поток не открылся после повтора — тот же трек из другого сервиса по порядку `audio.fallback_order`, со всплывашкой «Играет из YouTube Music — в SoundCloud недоступен». Сверка строгая: длительность ±3 с, исполнитель, название, одинаковые «версии». Не нашёлся или выключено — как раньше: ошибка / «Нужен резервный сервис». Плеер → Аудио → «Резервный сервис» | `true` | нет |
| `audio.fallback_order` | список id реестра (`sc`, `ym`, `yt`, `vk`) — где искать замену сначала; меняется перетаскиванием. Пусто, неизвестные и повторы — прочь, забытые и новые сервисы — в конец в порядке реестра. Spotify и локальные файлы резервом не бывают (нет потока / поиска); Яндекс и VK ищутся, только если подключены. ПК — `lib/fallback.ts` + `services/fallback.rs`, iPhone — тот же ключ строкой id через запятую (`SettingValue` без массивов; `FallbackPlan.order` в `Core/Providers/Fallback.swift`), порядок меняют стрелки ↑ ↓ | `[]` (= `sc, ym, yt, vk`) | нет |
| `audio.sc_via_yandex` | bool — трек SoundCloud играть с Яндекса, если там есть тот же (исполнитель, название ±0.9, длительность ±3 с, одинаковые «версии»); нет — SoundCloud. С 2026-11-18 — через тот же механизм резерва (Яндекс первым, без всплывашки; найденное запоминается в `track_alias`). По умолчанию выключено: на Яндексе треки бывают заблюрены (решение владельца 2026-11-17) | `false` | нет |
| `audio.gapless` | bool | `true` | да |
| `audio.splash_sound` (PC) | bool — **звук при запуске**: аккорд рояля (VCSL, CC0; сведён `windows/scripts/gen-splash-sound.mjs` в `public/splash-chord.wav`) в такт двум волнам заставки «сонар-поле» (`index.html`) при запуске и Ctrl+R. Заставка рисуется до загрузки настроек — читает зеркало `localStorage["sonar.splash_sound"]`. Плеер → Аудио → «Громкость и переходы» | `false` | нет |
| `audio.normalize` | bool. iPhone: громкие треки Яндекса приглушаются громкостью плеера по их `r128.i` (цель −14 LUFS, до −12 дБ; работает и на HLS), остальное — выравниватель `AudioTap` на файлах | `false` (PC), `true` (iOS) | да |
| `audio.on_interruption` (iOS) | `duck` / `pause` / `none` — что после звонка, Siri, будильника (паузу ставит сама iOS): вернуть плавно (с 20 % громкости за 2 с) / оставить на паузе / вернуть сразу; возвращает, только если до звонка играло и iOS разрешила (`shouldResume`) | `duck` | да |
| `audio.crossfade` | число, секунды 0…12 (0 — выкл; включение ставит 6). Наложение двух дек и на ПК, и на iPhone (2026-11-17: две `AVQueuePlayer`, следующий заранее во второй, равная мощность; не длиннее трети любого из двух треков). 0 — бесшовно (`audio.gapless`) | `0` | да |
| `audio.output_device` (PC) | id устройства | системное | нет |

Качество — пожелание: сервер выбирает ближайшее доступное (SC выше 256 не даёт). На iPhone старое
значение `lossless` читается как `max`.

**iPhone** (Профиль → Аудио, `ios/Sonar/Features/Settings/Player/AudioSettingsView.swift`): всё применяется
сразу — `PlaybackEngine` следит за настройками. Эквалайзер (`audio.eq`, `audio.eq_enabled` — на iPhone
`audio.eq` строкой «12 чисел через запятую», пусто — ровно) и нормализация — `MTAudioProcessingTap`
(`Playback/AudioTap.swift`, формулы `Playback/PlayerDSP.swift`): звучат только на **файлах** (Яндекс mp3 / FLAC,
SoundCloud через Яндекс, прогрессивный mp3 SoundCloud, скачанные). Поток **HLS** (почти весь SoundCloud) AVPlayer
проигрывает мимо `audioMix` — там без эквалайзера и нормализации, в настройках так и написано. Свои пресеты
(`audio.eq_presets`) на iPhone — тот же JSON `[{name, gains}]`, только строкой (`Core/Settings/EqualizerExtras.swift`):
«+» сохраняет текущую кривую, долгое нажатие — удалить; сверху листа — кривая (АЧХ фильтров). Правка кривой
сохраняется сразу (без «Сохранить»).
`audio.gapless` выключен (и нет кроссфейда) — следующий трек не подгружается заранее.

**Таймер сна** (iPhone, не настройка — состояние плеера): лист скорости в плеере (кнопка ползунков), 15 / 30 / 45 /
60 мин или «Конец трека». Минуты — последние 30 с громкость плавно уходит в ноль, потом пауза; «Конец трека» —
последние ≤ 12 с трека затихают, следующий загружается на паузе. Включён — луна на кнопке
(`Playback/PlayerExtras.swift` `SleepTimer`, `Features/Player/SleepTimerSheet.swift`).

## Профиль — `profile.*` (Аккаунт → Профиль, Windows 2026-11-16, оформление — 2026-11-18)

До сервера профиль хранится в настройках (синхронизируется как остальные); с сервером — `GET /me`
и `PATCH /me` (`API.md`). Пусто — имя и аватар из подключённого сервиса.

| Ключ | Значения | По умолчанию | Синк |
|---|---|---|---|
| `profile.name` | отображаемое имя (приветствие на главной), до 40 знаков | `''` | да |
| `profile.username` | `@username`: латиница, цифры, `_`, 3–32 | `''` | да |
| `profile.avatar` | WebP data URL 256×256, обрезан в круг (iPhone — JPEG data URL 256×256 из галереи, `ProfileEditView`) | `''` | да |
| `profile.banner` | баннер над аватаром: WebP data URL 900×300 (центр-кроп, `coverFromFile`) | `''` | да |
| `profile.background` | фон всей карточки профиля: WebP data URL 960×540 | `''` | да |
| `profile.color` | цвет профиля (ник, кольцо аватара, акценты): `''` без цвета · `red` `orange` `yellow` `lime` `green` `teal` `blue` `violet` `pink` `white` (`lib/profile-look.ts`) | `''` | да |
| `profile.status` | строка под ником, до 80 знаков | `''` | да |
| `profile.bio` | «О себе», до 190 знаков | `''` | да |
| `profile.links` | до 5 ссылок `[{kind: telegram\|discord\|site, url}]`; `@ник` → `t.me/ник`, только http(s) | `[]` | да |
| `profile.layout` | вид шапки: `avatar` · `big_name` · `banner` · `center` | `avatar` | да |
| `profile.nick_font` | шрифт ника: `default` · `caveat` · `marck` · `pacifico` · `lobster` · `amatic` · `pixel` · `retro` · `russo` · `unbounded` · `tektur` · `dela` | `default` | да |
| `profile.nick_effect` | эффект ника: `none` · `shimmer` · `neon` · `cartoon` · `highlight` · `3d` · `retro` | `none` | да |
| `profile.showcase` | витрина, до 6 мест `[{kind: playlist\|album\|artist\|track, ref, title, subtitle, cover_url}]`; плейлисты из `privacy.hidden_playlists` не ставятся и не показываются | `[]` | да |

Уровней, значков, Мастерской и Canvas нет (решение владельца 2026-11-18). На ПК всё это видно в превью
«как увидят другие» сверху страницы; публичная страница по ссылке и `ProfileView` на iPhone покажут баннер,
фон и эффекты, когда появится сервер.

## Приватность — `privacy.*` (Аккаунт → Приватность, решение владельца 2026-11-18)

Кто что видит в профиле и кто может добавить в друзья. Аудитория — `everyone` (все) / `friends` (только
друзья) / `nobody` (никто). Скрытое не попадает в `PublicProfile` вовсе (`lib/public-profile.ts`
`buildPublicProfile(…, viewer)`); с сервером `GET /public/users/{username}` режет по тем же ключам с учётом
дружбы. Предпросмотр «Как видят мой профиль» переключается «Гость / Друг». Друзья и заявки — с сервером.

| Ключ | Значения | По умолчанию | Синк |
|---|---|---|---|
| `privacy.friend_requests` | `everyone` / `fof` (друзья друзей) / `nobody` — кто может отправить заявку в друзья | `everyone` | да |
| `privacy.playlists` | аудитория — все плейлисты Sonar разом | `everyone` | да |
| `privacy.hidden_playlists` | id плейлистов, скрытых **ото всех** (и от друзей): меню плейлиста → «Скрыть от других» / «Показать другим». Не путать с `hidden` плейлиста — тот прячет из «Все» в своей медиатеке | `[]` | да |
| `privacy.likes` | аудитория — Любимые | `everyone` | да |
| `privacy.now_playing` | аудитория — трек, который играет сейчас | `everyone` | да |
| `privacy.stats` | аудитория — прослушивания, часы, любимые артисты | `everyone` | да |

Старые значения (bool и `visible`, сборка 2026-11-18) читаются через `audienceOf`: `true` → все, `false` → никто.

## Поиск — `search.*` (единый поиск, 2026-11-18)

| Ключ | Значения | По умолчанию | Синк |
|---|---|---|---|
| `search.preferred` | id сервиса (`sc`, `ym`, `yt`, `vk`, `sp`) — чьи результаты кнопки «Все» стоят сверху; дальше — порядок `audio.fallback_order`, один трек из разных сервисов склеивается (название + главный артист, длительность ±10 с). Система → Общее → «Поиск сначала в» | `sc` | да |

## Медиатека — `library.*` (карта исполнителей, ПК, 2026-11-18)

| Ключ | Значения | По умолчанию | Синк |
|---|---|---|---|
| `library.artists_view` | `list` / `map` — вкладка «Исполнители»: плитки или карта (переключатель «Список · Карта», запоминается) | `list` | да |
| `library.map_banner_done` | bool — баннер «Вот твоя музыкальная карта» уже был: показывается один раз после первого переноса плейлистов или при ≥ 20 исполнителях на карте, пропадает после клика по нему или крестика | `false` | да |

Карта — `windows/src/app/artist-map/` + `windows/src/lib/artist-map/` (узлы, связи и раскладка), граф — Rust
`src-tauri/src/artist_graph/` (фиты из названий, подписки SoundCloud фоном, общие соавторы, «похожие» сервисов),
кэш связей — таблицы миграции № 13 (`docs/DB.md`). На iPhone пока нет.

## Вид — `appearance.*` (`photo_13..15`, `pc/1..3`)

ПК (2026-11-18, `SETTINGS_NEXT` «Вид»): карточки **Тема** (режим, «Цвет» — готовые темы сеткой, сила темы под обложку) ·
**Прозрачность** · **Текст** (группы шрифтов капсулами, сетка 4 колонки «Aa + название», первые 16 и «Ещё N»,
«Свой»; размер, жирность — `LookText.svelte`) · **Форма** (живые примеры над выбором: скругление, кнопки окна;
площадки, масштабы, анимации — `LookShape.svelte`) · **Вкладки** (бывший отдельный пункт, `TabsView.svelte`;
`settingsPanel.show(_, 'tabs')` открывает «Вид»).

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `appearance.mode` | `system` / `dark` / `light` — светлая: формулы `palette.ts SURFACES_LIGHT`, «как в системе» — `prefers-color-scheme` на лету | `dark` | да |
| `appearance.cover_theme` | bool — тема под обложку | `true` | да |
| `appearance.cover_strength` | `weak` / `medium` / `strong` — сила темы под обложку (Интерфейс → Тема, видна при «Под трек»): фон и поверхности уходят за светлотой обложки — тёмная темнее, светлая светлее — на 8 / 14 / 20 % (не больше 20 %; полный сдвиг у явно тёмной или светлой обложки, у обычной — 10–15 % на «Средне», у серой середины — почти ноль), с лёгким оттенком её цвета; не до чёрного и не в серый, текст держит контраст AA (сдвиг ослабляется), смена плавная 0.6 с (`palette.ts` `COVER_STRENGTH`, `Palette.swift` `CoverStrength`) | `medium` | да |
| `appearance.preset` | `neutral`, `amoled`, `crimson`, `nord`, `sky`, `mint`, `violet`, `blossom`, `sakura`, `terminal`, `aqua`, `sunset`, `slate` — выбор готовой темы выключает «Под трек» | `neutral` | да |
| `appearance.animations` | bool — выключено: только прозрачность, как «Меньше движения» | `true` | да |
| `appearance.tab_style` | `standard` (во всю ширину у края) / `rounded` (во всю ширину, скруглён сверху) / `floating` (капсула) / `compact` (узкая капсула, только значки) — нижняя панель iPhone (`BottomChrome`, Интерфейс → Вкладки, 2026-11-17) | `floating` | да |
| `appearance.mini_player` | `capsule` / `standard` / `minimal` / `deck` / `custom` — заготовка мини-плеера (выставляет фон, прогресс, обложку, скругление; поменял пункт — `custom`). iOS (названия 2026-11-17): Капсула = цвет обложки + кольцо + круг + круглое; Обложка (`standard`) = сама обложка + заливка + закруглённая + среднее; Тихий (`minimal`) = цвет темы + линия + закруглённая + мягкое; Лента (`deck`) = сама обложка + линия + без обложки + без скругления | `capsule` | да |
| `appearance.mini_background` | `cover_color` (цвет обложки) / `cover` (сама обложка, размытая) / `theme` (цвет темы) — фон мини-плеера (iOS, 2026-11-17) | `cover_color` | да |
| `appearance.background` | `standard` (тема) / `cover_color` (мягкое свечение цвета обложки сверху) / `cover` (сама обложка, размытая) / `custom` (свой фон; iPhone — картинка из галереи, файл на телефоне `Application Support/Look/backdrop.jpg`, до сервера) — фон под экранами (`AppBackdrop`) | `cover_color` | да |
| `appearance.progress_indicator` | `none` или набор через запятую из `line` (линия внизу мини-плеера) / `fill` (заливка фона) / `ring` (кольцо на обложке) — можно несколько сразу (`line,ring`); iOS — Профиль → Мини-плеер (2026-11-17) | `ring` | да |
| `appearance.cover_shape` | `rounded` / `circle` / `hidden` (обложка в мини-плеере) | `circle` | да |
| `appearance.corner_radius` | `none` / `soft` / `rounded` / `pill` (Нет / Маленькое / Среднее / Большое) | `rounded` | да |
| `appearance.glass` | bool — прозрачность окна: Windows 11 — Mica, Windows 10 — Acrylic (`glass.rs`); iPhone — стекло нижней панели (выкл. — плотная поверхность темы) | `false` (PC), `true` (iOS) | да |
| `appearance.glass_type` | `balance` / `ultra` / `no_blur` — iPhone: Баланс — плотное размытие, Ультра — тонкое, Без размытия — только прозрачность | `ultra` | да |
| `appearance.opacity` | 15–100 % — альфа фона окна и карточек при прозрачности (iPhone — поверхности панели) | `80` | да |
| `appearance.glass_blur` | 0–40 px — радиус размытия у панелей и меню | `16` (PC) | да |
| `appearance.bg_blur` | 0–40 px — размытие фона-картинки (у «Самой обложки» поверх своего) | `0` | да |
| `appearance.bg_dim` | 0–90 % — затемнение фона-картинки сверх базового | `0` | да |
| `appearance.bg_custom` | id своего фона на сервере (картинка или видео ≤ 10 с) / null | `null` | да |
| `appearance.font` | `default`, имя шрифта из списка ниже или `custom:<имя>` (свой файл, PC — в IndexedDB); ось стиля «шрифт интерфейса» | `Golos Text Variable` (стиль Sonar) | да |
| `appearance.font_size` | 12 / 14 / 16 / 18 / 20 | `16` | да |
| `appearance.font_weight` (PC) | `auto` / 400 / 500 / 600 / 700 | `auto` | да |
| `appearance.scale_window` (PC) | 75–125 % (зум WebView) | `100` | нет |
| `appearance.scale_fullscreen` (PC) | `0` — «Авто» (как в окне) или 75–125 % — когда окно развёрнуто (`zoom.rs` `pick`) | `100` | нет |
| `appearance.window_buttons` (PC) | `auto` (как в системе: на Windows — Windows) / `windows` (значки) / `macos` (три кружка, значки при наведении) — `lib/window-buttons.ts`, `WindowControls.svelte` | `auto` | да |
| `appearance.show_sources` (PC) | bool — «Показывать площадки»: значок сервиса рядом с длительностью трека в списках (`TrackRow`) | `false` | да |

### Стиль — `appearance.*` (Интерфейс → Стиль, 2026-11-16)

Стиль — набор **независимых осей**. Готовый стиль ставит все оси; правка любой оси вручную (в
«Стиле» или «Виде») делает стиль «Своим» (несохранённым), совпали оси с готовым или сохранённым —
снова он. Тема под обложку и готовые темы остаются: стиль задаёт **формулы**, тема — **исходный цвет**.
Скругления (`corner_radius`) — тоже строка «Своего», но готовые стили их не меняют.
Код: Windows — `windows/src/theme/style.ts` (оси, готовые стили, `matchStyle`), `theme/palette.ts`
(`SURFACES`, `SURFACE_DECOR`), анимации — `lib/track-fx.svelte.ts`, `lib/like-fx.ts`, `theme/fx.css`,
`components/LoadFx.svelte`, экран — `pages/settings/Style.svelte`.

| Ключ | Значения | По умолчанию | Синк |
|---|---|---|---|
| `appearance.style` | `classic` / `sonar` / `echo` / `signal` / `edge` / `tactile` / `monolith` / `custom:<id>` (сохранённый) / `custom` (несохранённый «Свой») | `classic` | да |
| `appearance.surface` | `classic` / `echo` / `signal` / `edge` / `tactile` / `monolith` — формулы фона, поверхностей, границ (OKLCH), тени и блики, вид кнопок | `classic` | да |
| `appearance.font_display` | имя шрифта — заголовки («Моя волна», страницы, разделы) со своей шириной / жирностью | `Manrope Variable` | да |
| `appearance.title_style` | `plain` / `editorial` (капсом, крупно, номера разделов «02», линейка над разделом) | `plain` | да |
| `appearance.icon_stroke` | `1.5` / `1.75` / `2` — толщина линий иконок панели и кнопок плеера | `1.75` | да |
| `appearance.anim_track` | `classic` / `echo` / `signal` / `edge` / `tactile` / `monolith` / `fade` — анимация смены трека | `classic` | да |
| `appearance.anim_like` | `classic` / `echo` / `signal` / `edge` / `tactile` / `monolith` / `pop` — анимация лайка | `classic` | да |
| `appearance.anim_nav` | `dot` / `capsule` / `plate` / `inset` — как отмечен выбранный раздел | `plate` | да |
| `appearance.progress_look` | `line` / `wave` / `groove` — как нарисован прогресс (место — `mini.progress`; вид из «Плеер → Вид» главнее) | `line` | да |
| `appearance.loading` | `color` (обложка из ч/б в цвет полосой) / `ring` (сектор в круге) — загрузка трека | `color` | да |
| `appearance.classic_switched` | `true` / `false` — «Классика» уже поставлена один раз при обновлении (2026-11-22), дальше стиль не трогаем (заодно один раз ставит скругления `soft`) | `false` | да |
| `appearance.custom_styles` | список `{ id, name, axes }` — свои сохранённые стили | `[]` | да |

Готовые стили:

| Стиль | surface | шрифт / заголовки | линия | смена трека | лайк | раздел | прогресс | загрузка |
|---|---|---|---|---|---|---|---|---|
| **Классика** | classic | Manrope / Manrope 800 | 1.75 | classic | classic | plate | line | color |
| Sonar | monolith | Golos Text / Unbounded | 2 | edge | signal | dot | line | color |
| Эхо | echo | Onest / Science Gothic (wdth 165) | 1.75 | echo | echo | dot | line | ring |
| Сигнал | signal | Golos Text / Unbounded | 2 | signal | signal | capsule | wave | ring |
| Грань | edge | Geist / Geist | 1.75 | edge | edge | plate | line | color |
| Тактиль | tactile | IBM Plex Sans / IBM Plex Sans (wdth 78) | 2 | tactile | tactile | inset | groove | ring |
| Монолит | monolith | Inter Tight / Inter Tight 900 | 2 | monolith | monolith | dot | line | color |

Каждый выбор с несколькими вариантами открывается **нижним листом** (`photo_20..25`): иконка,
название, галочка у выбранного. Тогглы и ползунки — прямо в списке.

**Шрифты** (`photo_26, 27`), лист сгруппирован:
- По умолчанию (системный SF Pro);
- Без засечек: Manrope, Golos Text, Onest, Roboto, Poppins, Montserrat, Nunito, Lato,
  Open Sans, Raleway, Ubuntu, DM Sans;
- С засечками: Playfair Display, Merriweather, PT Serif, Lora, Crimson Text, EB Garamond;
- Акцидентные: Oswald, Bebas Neue, Anton, Impact (Impact — только если есть в системе,
  иначе Anton);
- Моноширинные: JetBrains Mono, Fira Code, Roboto Mono.
Все шрифты — Google Fonts (OFL), лежат в `ios/Sonar/Resources/Fonts` (только с кириллицей —
у кого её нет, в списке помечаются «лат.»). Каждая строка списка нарисована своим шрифтом.

## Плеер — `player.*` (`photo_16, 17`, `pc/6, 7`)

**ПК (Интерфейс → Плеер, 2026-11-18, SETTINGS_NEXT «Плеер»)** — одна страница карточками: стиль плеера живым
примером (настоящая обложка, винил крутится), Визуализатор · Ползунок (плитки-превью, выбранная двигается) ·
Обложка · Очередь. Отдельного пункта «Очередь» больше нет, старые ссылки `queue` ведут сюда.

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `player.style` | `standard` / `vinyl` (винил крутится, игла) / `large` (обложка на всю колонку; на iPhone — на весь фон, `player.jpg`) | `standard` (PC), `large` (iOS) | да |
| `player.visualizer` (PC) | `off` / `bar` / `cover` (на обложке) / `slider` (на ползунке) | `bar` | да |
| `player.queue_view` | `normal` / `extended` | `extended` | да |
| `player.background` | `none` / `cover_blur` / `cover_color` (iPhone: для `standard` и `vinyl`; у `large` фон — сама обложка) | `none` (PC), `cover_blur` (iOS) | да |
| `player.title_align` | `left` / `center` / `right` | `center` | да |
| `player.slider` | `normal` / `thin` / `smooth` / `wave_bars` / `wavy` (на ПК подпись «Переливы» — бегущая волна) | `normal` | да |
| `player.play_button` | `circle` / `square` / `clean` | `circle` | да |
| `player.artist_avatars` | bool | `true` | да |

**iPhone** (Профиль → Вид плеера, `PlayerViewSettingsView`): стиль, фон, выравнивание, ползунок (все пять, `Features/Player/PlayerSlider.swift`),
кнопка и аватарки применяются в `FullPlayerView` сразу; сверху экрана — живой пример. Визуализатора и позиции
обложки на iPhone нет. Значения — rawValue в `ios/Sonar/Playback/PlayerPrefs.swift`, умолчания — `SettingsDefaults+Player.swift`.

Скорость воспроизведения — не настройка, а лист в плеере (`photo_30`); «Запомнить» пишет в
`track_prefs` (см. `DB.md`).

**Таймер сна (PC)** — тоже не настройка, а кнопка-луна рядом со скоростью на странице плеера
(`player/SleepButton.svelte`, `sleep.svelte.ts`): 15 / 30 / 45 / 60 / 90 минут или «До конца трека».
Последние 30 с (у «до конца трека» — 8 с) громкость плавно уходит в ноль, затем пауза и громкость
возвращается. На кнопке — остаток; «Выключить» снимает таймер.
| `player.visualizer` (PC) | `off` / `bar` / `cover` / `slider` | `bar` | да |
| `player.visualizer_style` (PC) | `wave` / `bars` | `wave` | да |
| `player.visualizer_full` (PC) | bool — спектр (AnalyserNode после эквалайзера) тихо на дне полноэкранного плеера, ≤30 кадров/с; с «Меньше движения» и в фоне не рисуется | `false` | да |
| `player.wave_why` (PC) | bool — строка «Почему этот трек» под артистом у треков «Моей волны» (`wave.rs` `why`: похож на лайк / на зашедшее сейчас / волна по треку / любимый артист / разведка / забытый лайк) | `true` | да |
| `player.sleep_button` | bool — таймер сна в плеере (ПК — кнопка с луной; iPhone — блок в листе скорости и «Таймер сна» в меню играющего трека, Вид плеера); выключено — кнопки нет, но уже запущенный таймер видно, чтобы отменить; на iPhone выключение отменяет запущенный таймер и прячет его везде (владелец 2026-11-22) (владелец 2026-11-22: нужна немногим, бросается в глаза) | `false` | да |
| `player.cover_position` (PC) | `left` / `right` | `left` | да |
| `player.cover_in_cover` (PC) | bool | `false` | да |
| `player.volume` (PC) | 0…1 | `0.8` | нет |
| `audio.eq` (PC) | 12 чисел, дБ ±12 (32 Гц … 20 кГц) — кривая эквалайзера, одна на все треки; правки звучат сразу, пишутся только кнопкой «Сохранить», закрыл без неё — вернулась сохранённая | все `0` | нет |
| `audio.eq_presets` (PC) | `[{name, gains}]` — свои пресеты («+»); встроенные: Нейтральный, Басы, Высокие, Вокал, Громче | `[]` | да |
| `player.tempo` (PC) | `{rate 0.5–2, pitch −12…+12 пт, linked, keep, reverb 0–1}` — меню у кнопки-часов: готовые ×0.8 … ×1.35, ползунки скорости и тона с −/+, «Связать тон со скоростью», «Сохранять между треками», реверб. Заменяет `player.speed_mode` (slowed / speed переносятся в 0.8 / 1.25) | `{1, 0, true, true, 0}` | нет |
| `player.pitch_linked`, `player.pitch`, `player.reverb` (iPhone) | общие тон (связан со скоростью — `.varispeed`, иначе свой, −12…+12 пт) и реверб 0–1 листа скорости; скорость на новом треке — 1× | `false`, `0`, `0` | нет |
| — «Для этого трека» (ПК и iPhone, 2026-11-22) | не настройка, а `track_prefs.sound_json` / `LibraryStore.sounds`: скорость, тон, реверб и кривая эквалайзера одного трека, едут синком `track_pref` (API.md §6). Включён — правки скорости, тона, реверба и «Сохранить» эквалайзера пишутся в трек | — | да (как `track_pref`) |

## Текст песни — `lyrics.*` (меню текста, `photo_6`; LYRICS.md §6)

Меняются в меню полноэкранного плеера — **правый клик в любом месте** (как в Dotify), отдельного экрана и кнопок нет.

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `lyrics.mode` | `words` / `lines` — «По словам» работает, только если у текста есть пословный тайминг | `words` | да |
| `lyrics.size` | `S` / `M` / `L` / `XL` (1.25 / 1.6 / 2 / 2.5 rem) | `L` | да |
| `lyrics.style` | `normal` / `scale` / `blur` / `cinema` / `shift` | `blur` | да |
| `lyrics.animation` | `normal` / `fade` / `blur` / `flip3d` / `bounce` / `wave` / `float` / `drift` / `zoom` / `ladder` («Лесенка» — прокрутка «магнитом», строки как в «Обычной») | `normal` | да |
| `lyrics.view` (PC) | `both` (обложка и текст) / `cover` (только обложка) / `lyrics` (только текст, сверху плашка с треком) — «глаза» в меню полноэкранного плеера | `both` | нет |

Сдвиг тайминга — не настройка, а `track_prefs.lyrics_offset_ms` на трек (LYRICS.md §5).
На iPhone те же ключи и значения (rawValue `LyricsMode` / `LyricsSize` / `LyricsTextStyle` / `LyricsAnimation` в `ios/Sonar/Core/Lyrics/LyricsModels.swift`, умолчания — `SettingsStore.defaults`); сдвиг — `lyrics-offsets.json` в Application Support, пока нет SQLite.

## Очередь — `queue.*` (PC `pc/7`, с 2026-11-18 — карточка «Очередь» в «Плеере»; на iOS — часть «Плеера»)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `queue.show` (PC) | bool | `true` | да |
| `queue.preview` | bool — карточка «Дальше» за 10 с до конца (мини-плеер и плеер) | `true` | да |
| `queue.view` | `normal` (компактно, без обложек) / `extended` | `extended` | да |
| `queue.position` (PC) | `bottom` / `left` / `right` | `bottom` | да |
| `queue.add_following` | bool — тап по треку ставит и следующие за ним (iPhone: `engine.play(…, tapped: true)` у строк треков; «Слушать» / «Перемешать» — всегда весь список) | `true` | да |

**iPhone** (Профиль → Очередь, `QueueSettingsView`): «Продолжить с прошлого раза» (`general.restore`: очередь —
`Application Support/Sonar/player-state.json`, до 50 прошлых и 300 следующих, на паузе с той же секунды),
`queue.view` (лист очереди без обложек / с обложками), `queue.preview` (мини-плеер: «Дальше · …» вместо
исполнителя, плеер: «через N с» у «Далее»), «Авто похожие» и `queue.add_following`. `queue.show` и
`queue.position` — только ПК.

### Моя волна (iPhone: Профиль → Очередь → «Моя волна»)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `wave.mode` | `own` / `fun` / `calm` / `sad` / `hard` / `night` / `sleep` / `popular` / `focus` — настроение Sonar Mix (Обычное · Весёлое · Спокойное · Грустное · Жёсткое · Ночное · Сон · Популярное · Концентрация; кнопка на Главной). Старое `new` («Незнакомое», убрано 2026-11-18) читается как `own` | `own` | да |
| `storage.wave_offline` | ключ общий с ПК (строка ПК — в «Хранилище»). iOS: на Wi‑Fi (сеть не «дорогая») следующие 15 треков волны качаются файлами в `Caches/Sonar/WaveCache` (`Playback/WaveCache.swift`, как «Скачать»: HLS без файла пропускается; кэша треков на лету у iPhone нет), без сети волна играет их и перескакивает несохранённые; сыгранное удаляется, выключение чистит кэш | `false` (PC), `true` (iOS) | нет |
| `player.wave_why` | ключ общий с ПК (строка ПК — в «Плеере»). iOS: строка под названием в полном плеере у треков волны — «Ты лайкал «…» — этот похож», «Похож на «…» — он зашёл сейчас», «Популярное у …», «Из твоих Любимых — давно не звучал», «Новый для тебя артист» (из `WaveOrigin.seedOf`, `WaveReason`) | `true` | да |

## Жесты — `gestures.*` (`photo_18..20`)

Действия: `off`, `like`, `enqueue`, `play_next`, `next`, `previous`, `delete`.

| Ключ | По умолч. |
|---|---|
| `gestures.library.left` | `play_next` |
| `gestures.library.right` | `play_next` |
| `gestures.queue.left` | `delete` |
| `gestures.queue.right` | `delete` |
| `gestures.mini.left` | `next` |
| `gestures.mini.right` | `previous` |
| `gestures.player.left` | `next` |
| `gestures.player.right` | `previous` |
| `gestures.cover.double_tap` | `like` |
| `gestures.cover.triple_tap` | `next` |

Все — sync. `delete` в Медиатеке = убрать из плейлиста/лайков (с «Отменить» 4 с — на iPhone пока без «Отменить»).

Что где можно выбрать (`GestureContext.allowed` в `ios/Sonar/Playback/Gestures.swift`; чужое значение — умолчание):
Медиатека — `off` / `play_next` / `enqueue` / `like` / `delete`; Очередь — `off` / `delete` / `play_next`
(переставить следующим) / `enqueue` (в конец) / `like`; Мини-плеер и Плеер — `off` / `next` / `previous` / `like`;
тапы по обложке — `off` / `like` / `next` / `previous`. «Влево» — палец едет влево. Двойной тап `like` только
ставит лайк (с большим сердцем), не снимает. iPhone (Профиль → Жесты, `GesturesSettingsView`): свайпы по
строкам треков (`TrackRow`), «Далее» в очереди, мини-плееру и обложке полного плеера; тапы — по обложке.

## Вкладки PC — `tabs.*` (Интерфейс → Вид → «Вкладки», с 2026-11-18; раньше — отдельный пункт)

| Ключ | Значения | По умолчанию | Синк |
|---|---|---|---|
| `tabs.position` | `left` / `right` / `top` (полоса, кнопки окна на её конце) / `bottom` | `left` | да |
| `tabs.style` | `default` / `compact` / `round` / `floating` (капсула над окном, тянется куда угодно; вдоль — при позиции сверху / снизу); `full` убран 2026-11-18 (не отличался от `default`), сохранённый читается как `default` (`settings-migrate.ts`) | `default` | да |
| `tabs.float_x`, `tabs.float_y` | центр плавающей панели в долях окна | `0.045`, `0.5` | да |
| `tabs.adapt` | bool — цвет панели от подкраски страницы | `false` | да |
| `tabs.autohide` | bool — мышь замерла 3 с: панель и мини-плеер гаснут | `false` | да |
| `tabs.collapse` (iOS) | bool — при прокрутке вниз вкладки и мини-плеер сворачиваются в одну строку | `true` | да |

На iPhone «Вкладки» — стиль нижней панели (`appearance.tab_style`), `tabs.adapt` (панель в цвет подкраски темы) и `tabs.collapse`; позиции нет — панель всегда снизу. Экраны iOS «Интерфейса» — `ios/Sonar/Features/Settings/Look/` (`LookSettingsView`, `TabsSettingsView`, `ProfileEditView`); на iPhone из осей стиля пока применяется только поверхность, остальные оси выбор стиля пишет как ПК — синк не превращает стиль в «Свой».

## Мини-плеер PC — `mini.*` (`pc/8, 9`)

| Ключ | Значения | По умолч. |
|---|---|---|
| `mini.style` | `off` / `full` / `rounded` / `hybrid` / `deck` — пресет, выставляет фон/прогресс/обложку/форму (`PLATFORMS.md`) | `hybrid` |
| `mini.position` | `top` / `bottom` / `bottom_full` (снизу во всю ширину: левая панель кончается над плеером) / `floating` (перетаскивается, `mini.float_x` / `mini.float_y` — доли окна). Старое `bottom_inset` → `floating` | `bottom` |
| `mini.background` | `theme` / `cover` / `cover_color` | `theme` (пресет «Гибрид») |
| `mini.progress` | список, можно несколько: `line` / `background` / `cover` (кольцо вокруг обложки); хотя бы один. Старое одно значение → список из него | `["background"]` |
| `mini.cover_shape` | `default` / `circle` — кнопками; выставляет `mini.cover_round` (20 / 100) | `default` |
| `mini.shape` | `default` / `capsule` — кнопками; выставляет `mini.shape_round` (0 / 100) | `default` |
| `mini.cover_round`, `mini.shape_round` | 0–100 % — тонкая подстройка в «Ещё настройки», по ним и рисуется мини-плеер | `100`, `100` |

Экран (2026-11-18): живой пример сверху; «Стиль» и «Фон» — карточки-превью с обложкой играющего трека,
«Позиция» — четыре значка окна, «Прогресс» — карточки с галочками (несколько сразу).

## Оверлей PC — `overlay.*` (`pc/10, 11`) — делаем (решение владельца 2026-11-18)

Интерфейс → Оверлей: плашка с треком поверх игр и других программ — отдельное окно `overlay`
(`mini.rs`), живёт рядом с мини-окном. Поверх игр в окне без рамки видна, поверх эксклюзивного
полного экрана — нет. Открывается горячей клавишей `hotkeys.map.overlay` (Ctrl+Alt+O), кнопкой
«Показать сейчас» или сама («Появляться само»).

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `overlay.mode` | `off` (Отключен) / `fullscreen` (Полноэкранный: затемнение и большая карточка, Esc или клик мимо — закрыть) / `island` (Остров: чёрная капсула) / `card` (Карточка) — карточки-превью | `card` | нет |
| `overlay.auto` | bool — Sonar свернули или спрятали в трей — оверлей открывается, окно вернули — закрывается (проверка раз в 1 с; если открыто мини-окно — не открывается) | `false` | нет |
| `overlay.shape` | `square` / `rounded` | `rounded` | нет |
| `overlay.position` | клетка сетки 3×3: `tl` `tc` `tr` · `ml` `mc` `mr` · `bl` `bc` `br` — плашку на схеме мониторов перетаскивают, она прилипает к ближайшей точке; отступ от края рабочей области 20 px (с DPI монитора) | `tc` | нет |
| `overlay.monitor` | `primary` (основной в Windows) или `monitorDevicePath` выбранного монитора. Схема рисует все мониторы, как они стоят в «Параметры → Дисплей» (номер, модель из EDID или «Монитор N», разрешение · частота, метка «Основной»); клик — выбрать монитор, плашку можно утащить на другой. Монитор отключили — оверлей встаёт на основной, **значение не стирается**: подключили — вернётся. Место считается от рабочей области (без панели задач) с масштабом этого монитора; подключение и отключение замечаются (окно — раз в 2 с, страница настроек — раз в 2,5 с) | `primary` | нет (у каждого ПК свои мониторы) |
| `overlay.opacity` | 30–100 % | `90` | нет |
| `overlay.scale` | 50–200 % | `100` | нет |
| `overlay.width` | 240–600 px | `340` | нет |
| `overlay.height` | 44–120 px (Остров — 70 % высоты, не ниже 34) | `58` | нет |

Логика места и размера — `windows/src/lib/overlay.ts` (тест `overlay.test.ts`), окно — `mini.rs` `overlay()`.
Мониторы — команда `list_monitors` (`monitors.rs`: расстановка Tauri + имя модели и частота из DisplayConfig, `cargo test`),
схема — `components/settings/MonitorScheme.svelte`, её математика — `lib/monitor-layout.ts` (тест `monitor-layout.test.ts`).

## Интеграции — `integrations.*` (`photo_3`, `pc/14, 15`)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `integrations.discord.enabled` (PC) | bool | `true` | да |
| `integrations.discord.cover` (PC) | bool | `true` | да |
| `integrations.discord.progress` (PC) | bool | `true` | да |

ID приложения Discord — **не настройка**: пользователь ничего не вписывает. До сервера он вшит
в сборку (`windows/src-tauri/src/discord.rs` `APP_ID`), потом приходит с сервера (`GET /config`).

Last.fm убран из ПК и iPhone 2026-11-18 (`docs/LASTFM_EXIT.md`): ключей `integrations.lastfm.*` больше нет,
сохранённый вход стирается при запуске один раз.

Ключ API (для selfbot и `GET /oauth/now`) — создать / перевыпустить / удалить, показывается
один раз. iOS: Безопасность, Приватность и Ключ API до сервера — честная заглушка `ServerOnlyView`. OBS-плашка (`pc/15`) — после MVP, тем же ключом.

## Система PC — `system.*` (`pc/16`)

`system.autostart` (true), `system.tray` (true), `system.power_saving`
(`off` / `minimized` / `background`, по умолч. `background`).

### Пульт с iPhone — `remote.*` (Система → Пульт, 2026-11-18)

Телефон управляет музыкой на этом ПК по Wi-Fi (`remote/`, протокол — API.md §10 «Пульт»). Включён —
WebSocket на порту 53120 (занят — любой свободный) и объявление `_sonar._tcp` в сети; кнопка «Привязать
iPhone» показывает 6-значный код и QR, ниже — привязанные телефоны с «Отвязать» (ключи — в keyring). Под
переключателем — подсказка про брандмауэр Windows (разрешить Sonar в частных сетях), mDNS не встал —
«привяжи по QR». На iPhone настроек
нет: «Где играть» в полноэкранном плеере (`DevicePickerSheet`), ключ к каждому ПК — в Связке ключей.

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `remote.enabled` (PC) | bool | `false` | нет — только это устройство (`LOCAL_PREFIXES` в `store/sync.rs`) |

### Клавиши PC — `hotkeys.*` (Приложение → Клавиши; горячие клавиши — решение владельца 2026-11-17, раскладка — SETTINGS_NEXT «Клавиши», 2026-11-18)

Сверху — **где действуют** (`hotkeys.scope`), ниже три карточки: **Плеер**, **Навигация** (с «Быстрым окном»),
**Окно и оверлей**. Клавиша — кнопка-колпачок: клик — «нажми новое», Esc — отмена, Backspace — без клавиши
(«—»); ↻ у изменённой строки — как с завода, «Вернуть все» — над карточкой «Плеер». Одно сочетание на два
действия не ставится. Сочетание занято другой программой — строка подсвечена «Не встало».
По всей системе сочетания ставит `tauri-plugin-global-shortcut` (`hotkeys.rs`, порядок действий — `ACTIONS`,
сверяется тестом с `HOTKEY_ACTIONS` в `lib/hotkeys-core.ts`); внутри окна их ловит `hotkeys.handleKey`
(в поле ввода — только с Ctrl, Alt или Win). Навигация (поиск, текст, очередь, настройки) — **только внутри
окна**, ей можно голую клавишу (`/`); «Показать / скрыть окно» — **только по всей системе**.

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `hotkeys.scope` | `app` (только в окне Sonar) · `top` (ещё и по всей системе, пока открыто мини-окно поверх окон) · `global` (всегда, даже из трея). Старое `hotkeys.enabled` переезжает: `true` → `global`, `false` → `app` (`settings-migrate.ts`) | `app` | нет |
| `hotkeys.map` | действие → сочетание (`KeyboardEvent.code`, `''` — без клавиши). Плеер: `toggle` Ctrl+Alt+Space, `next` Ctrl+Alt+→, `prev` Ctrl+Alt+←, `seek_back` / `seek_fwd` (±5 с) —, `volume_up` Ctrl+Alt+↑, `volume_down` Ctrl+Alt+↓ (±5 %), `mute` Ctrl+Alt+M, `shuffle` —, `repeat` —, `like` Ctrl+Alt+L. Навигация: `search` `/`, `lyrics` Ctrl+L, `queue` Ctrl+Q, `settings` Ctrl+, , `wave` (запустить Sonar Mix) —. Окно: `overlay` Ctrl+Alt+O, `mini` Ctrl+Alt+T, `window` Ctrl+Alt+S (показать / скрыть окно). Оверлей и мини-окно — с Ctrl+Alt, а не Ctrl+O / Ctrl+T из SETTINGS_NEXT: по всей системе те перехватили бы «Открыть» и «Новую вкладку» в других программах. Действия, которых нет в сохранённой карте, берутся по умолчанию | см. слева | нет |
| `hotkeys.quick` | сочетание быстрого окна (`KeyboardEvent.code`), `''` — выключено. Только **внутри окна** Sonar, от `hotkeys.scope` не зависит (строка в карточке «Навигация»); то же сочетание из `hotkeys.map` снимается и наоборот (и при «Вернуть по умолчанию») | `Ctrl+KeyK` | нет |

**Быстрое окно** (`app/QuickOpen.svelte`, `lib/quick*.ts`): по центру поверх всего — поле и список.
Сразу ищет действия (играть/пауза, следующий/предыдущий, лайк, перемешать, «Моя волна» и её настроения,
таймер сна, тёмная/светлая/системная тема, «Открыть настройки…», переход на Главную/Медиатеку/Поиск/Плеер),
разделы и строки настроек (только при вводе), свои плейлисты с Любимыми и историю; через 250 мс — треки и
артистов подключённых сервисов (`lib/services.ts`, у кого есть поиск). Поиск нечёткий: по началам слов
(«мв» → «Моя волна») и в другой раскладке (ghbdtn → привет). ↑↓ — строка, Tab / Shift+Tab — к следующей /
предыдущей группе, Enter — играть / открыть / выполнить, Shift+Enter — трек в очередь, плейлист играть;
подсказки — справа у выбранной строки. Esc или клик мимо — закрыть. Появление 0.98 → 1 с прозрачностью,
список каскадом; «меньше движения» — только прозрачность.

## Кэш / Хранилище — `storage.*` (`pc/18`, iOS «Кэш»)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `storage.cache_tracks` | bool — прослушанное на диск (`track_cache.rs`: файлы на лету, HLS — склейкой) | `false` | нет |
| `storage.cache_limit_mb` | 512 / 1024 / 2048 / 5120 / 10240 — сверх лимита вытесняются давно не игравшие | `2048` | нет |
| `storage.wave_offline` (PC) | bool — «Волна офлайн»: следующие 15 треков «Моей волны» фоном по одному качаются в кэш треков (`prefetch_tracks` → `stream.rs` `prefetch`); только при включённом кэше | `false` | нет |
| `storage.music_folders` (PC) | список путей — «Папки с музыкой»: сканируются (`local/scan.rs`, lofty: mp3, flac, m4a, ogg, opus, wav), за ними следит `notify` (`local/watch.rs`), найденное — в `local_files`, треки `local:<sha1 пути>` — в Медиатеке «На этом компьютере». «+» — выбор папки (`tauri-plugin-dialog`), «−» — убрать (её строки уходят из индекса), «Пересканировать» | `[]` | нет |

Экран: занято всего (полоса по типам), «Треки N, X МБ», «Обложки», «Тексты» — «Очистить» у
каждого и «Очистить всё»; «История поиска — Очистить»; «Настройки треков — Сбросить»
(сдвиг текста по треку). Скачанные вручную треки — отдельной строкой, «Очистить» с
подтверждением.

iOS (2026-11-17, Система → **Хранилище**, `StorageSettingsView`): кэша треков на лету нет — занято всего
(полоса: скачанные, обложки, тексты, история), Скачанные (N треков, размер, «Удалить все» с подтверждением),
Обложки (`URLCache`) и Тексты (`LyricsCache`, неделя / две у Любимых) — «Очистить», размер кэша обложек,
История прослушиваний (Недавнее, статистика и вкус волны — с подтверждением), История поиска.

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `storage.covers_limit_mb` (iOS) | 128 / 256 / 512 / 1024 — потолок кэша обложек на диске | `256` | нет |

## Автообновление — `update.*`

`update.auto_check` (true) — при запуске и раз в 6 ч, `update.auto_download` (true, Windows) —
скачивать найденное в фоне, ставить по кнопке «Установить», `update.channel` (`stable`; `beta` —
«Скоро»). Windows: `tauri-plugin-updater`, `latest.json` в релизе `windows-latest`, история версий —
`updates/changelog.json` (поле `platform`: `windows` / `ios` / нет — общая). iOS: Сертификат (`.p12`, пароль,
`.mobileprovision`) — только Keychain/файлы устройства, не sync.

iOS (2026-11-17, Профиль → Система → **Обновления**, бейдж, когда есть новая сборка): карточка версии
(«Sonar 0.1.0 (12)», статус проверки или «Доступно обновление» → экран «Обновление»), «Проверять
автоматически» (`update.auto_check`), Канал — плитки «Стабильный» / «Бета» (Скоро), **Сертификат для
подписи** (`.p12`, пароль, `.mobileprovision`: команда, App ID, срок — истёк красным, устройства, подходит ли
к установленному bundle id; «Пара подходит» / причина; «Удалить пару»), **Архив версий** (сборки из
`changelog.json` с «Скачать IPA»). Экран **«Обновление»** (из всплывашки и из «Обновлений»): «Текущая → Новая»,
«N новых функций · M исправлений · K выпусков», «Обновить до …» (есть пара) или «Скачать IPA» + «Добавь
сертификат — и Sonar будет обновляться сам», прогресс по стадиям (загрузка → распаковка → подпись →
упаковка → окно iOS → передача), строка диагностики, через 10 с без окна — причина, «Показать окно установки»,
«Поделиться подписанной IPA», «Отменить»; ниже — изменения каждой пропущенной сборки с метками НОВОЕ /
ИСПРАВЛЕНО. Всплывашка «Доступно обновление» — над таб-баром, один раз на сборку, закрывается только нажатием.
