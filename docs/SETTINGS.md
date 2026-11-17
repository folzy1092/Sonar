# Sonar — каталог настроек

Каждая настройка — ключ `раздел.имя`, хранится как JSON-значение. **sync** — уходит на сервер
и одинакова на всех устройствах. Ключи общие для iOS и Windows, если смысл совпадает.
Референс — файл в `reference/` (только локально).

## Меню настроек iOS (`mobile/photo_1..3`)

Порядок и названия разделов **те же, что вкладки на Windows** (`docs/PLATFORMS.md`):

```
[Шапка профиля: аватар, имя, @username, #номер, дата регистрации] [Поделиться] [✎]
Аккаунт:     Статистика · Безопасность · Приватность 🔒
Интерфейс:   Вид · Вкладки
Плеер:       Аудио · Вид плеера · Очередь · Мини-плеер · Жесты
Сервисы:     SoundCloud · Яндекс Музыка
Интеграции:  Last.fm · Ключ API
Система:     Общее (язык, платформа, медиатека, синхронизация; внизу — о приложении) · Горячие клавиши (PC) · Обновления · Хранилище
О приложении (низ «Общего»): знак, название, версия (двойной клик по знаку — проверка обновлений) ·
             Сайт (`sonar.folzy.ru`) · Телеграм (t.me/SonarUpdates) · Соглашение · Конфиденциальность ·
             Сбросить настройки · Выйти
```
Убрано: Подписка, Прокси, Кастомизация, Мастерская, Discord (только Windows).

## Основные — `general.*` (`photo_11`, `pc/16`)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `general.platform` | `soundcloud` / `yandex` | `soundcloud` | да |
| `general.restore` | `none` / `track` / `queue` | `queue` | да |
| `general.similar_autoplay` | bool | `true` | да |
| `general.add_position` | `start` / `end` | `start` | да |
| `general.language` | `ru` / `en` / `uk` — язык интерфейса, меняется на лету (Windows: `lib/i18n.svelte.ts`, ключ перевода — русская строка, словари `src/i18n/{en,uk}/*.ts`) | `ru` (iOS: язык системы, если ru / en / uk, иначе `ru`) | нет |

Кнопки «Отправить на сервер» / «Получить с сервера» — действия, не настройки.
`general.platform` — откуда главная берёт волну и рекомендации.

iOS (2026-11-17, Система → **Общее**, `Features/Settings/System/GeneralSettingsView.swift`): Язык (лист из
трёх, меняется сразу — `Core/I18n/`: `t("русская строка")`, `tn(n, …)`, словари `Strings+Windows.swift` из
`windows/src/i18n` генератором `ios/scripts/gen-i18n.mjs` + `Strings+iOS.swift`), Платформа, Медиатека →
Добавление, Синхронизация (две строки «С сервером»), внизу «О приложении» (знак — двойной тап проверяет
обновления, версия, Сайт · Телеграм · Соглашение · Конфиденциальность, «Сбросить настройки» с подтверждением).
«Авто похожие» — в Очереди.

### Виджет и Siri — `widget.*` (только iOS, 2026-11-17)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `widget.quick_playlist` | `liked` (Любимые) / `downloaded` (Скачанные) / ref плейлиста сервиса из Медиатеки (`scpl:<id>`, `scpl:likes`, `ympl:<uid>:<kind>`, `ympl:likes`); пусто или непонятное — Любимые (`Core/Shortcuts/PlayTarget.swift` `QuickPlaylist`) | `liked` | нет |
| `widget.quick_playlist_title` | название выбранного плейлиста сервиса — показать строку без сети | `""` | нет |

iOS: Система → **Общее** → «Виджет и Siri» → «Быстрый плейлист» (лист `QuickPlaylistSheet`: Любимые, Скачанные,
плейлисты SoundCloud и Яндекса). Его играют кнопка «Быстрый плейлист» виджета (`sonar://play/quick`) и команда
Siri / «Команд» «Быстрый плейлист». Другие ссылки виджета — `sonar://play/liked` и `sonar://play/wave`
(`App/DeepLink.swift` → `Playback/QuickPlay.swift`). Виджет — цель `SonarWidget` (`ios/SonarWidget/`): средний —
три кнопки, маленький — одна на выбор («Изменить виджет» → «Что включать»). Он статичный: App Groups сторонняя
подпись не даёт, данных приложения виджет не видит. Команды Siri (`App/SonarIntents.swift`, App Intents, без
entitlement): «Моя волна», «Любимые», «Быстрый плейлист», «Пауза», «Продолжить», «Следующий трек» — играют в
фоне, Sonar не открывается. У Siri нет русского: голосом — английские фразы (`Resources/en.lproj/AppShortcuts.strings`,
«Play My Wave in Sonar»), по-русски команды — в приложении «Команды» и в Spotlight.

## Статистика — `stats.*` (Аккаунт → Статистика, TZ photo_7, 8 без друзей)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `stats.period` (iOS) | `week` / `month` / `year` / `all` — открытый период | `month` | нет |

iOS (2026-11-17, `StatsView`): по журналу прослушиваний на телефоне (`Core/Stats/PlayLog.swift`,
`plays.json`; пишет `PlayHistory`, старая история переносится один раз) — время (часы / минуты со счётом),
прослушивания, треки, артисты, «к прошлому периоду», столбики по дням / месяцам (тап — время дня), кольцо по
часам суток с пиком, дни недели, серия дней, треков в день, любимый день, топ-10 артистов (страница артиста)
и треков (играть с него). Подсчёт — `ListeningStats.swift`, как Windows `store/stats.rs`.

## Аудио — `audio.*` (`photo_12`, `pc/4,5`)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `audio.quality` | `low`(192) / `medium`(256) / `high`(320) / `max`(от 1411, FLAC Яндекса; нет FLAC — 320). SoundCloud отдаёт максимум сам (AAC 160, с Go+ — 256) | `max` | нет |
| `audio.sc_via_yandex` | bool — трек SoundCloud играть с Яндекса, если там есть тот же (исполнитель, название ±0.9, длительность ±3 с, одинаковые «версии»); нет — SoundCloud. По умолчанию выключено: на Яндексе треки бывают заблюрены (решение владельца 2026-11-17) | `false` | нет |
| `audio.gapless` | bool | `true` | да |
| `audio.normalize` | bool | `false` | да |
| `audio.on_interruption` (iOS) | `duck` / `pause` / `none` — что после звонка, Siri, будильника (паузу ставит сама iOS): вернуть плавно (с 20 % громкости за 2 с) / оставить на паузе / вернуть сразу; возвращает, только если до звонка играло и iOS разрешила (`shouldResume`) | `duck` | да |
| `audio.crossfade` | число, секунды 0…12 (0 — выкл; включение ставит 6). ПК — наложение двух дек; iPhone — затухание конца и нарастание следующего без наложения (AVQueuePlayer играет по одному) | `0` | да |
| `audio.output_device` (PC) | id устройства | системное | нет |

Качество — пожелание: сервер выбирает ближайшее доступное (SC выше 256 не даёт). На iPhone старое
значение `lossless` читается как `max`.

**iPhone** (Профиль → Аудио, `ios/Sonar/Features/Settings/Player/AudioSettingsView.swift`): всё применяется
сразу — `PlaybackEngine` следит за настройками. Эквалайзер (`audio.eq`, `audio.eq_enabled` — на iPhone
`audio.eq` строкой «12 чисел через запятую», пусто — ровно) и нормализация — `MTAudioProcessingTap`
(`Playback/AudioTap.swift`, формулы `Playback/PlayerDSP.swift`): звучат только на **файлах** (Яндекс mp3 / FLAC,
SoundCloud через Яндекс, прогрессивный mp3 SoundCloud, скачанные). Поток **HLS** (почти весь SoundCloud) AVPlayer
проигрывает мимо `audioMix` — там без эквалайзера и нормализации, в настройках так и написано. Свои пресеты
(`audio.eq_presets`) на iPhone пока нет — только встроенные; правка кривой сохраняется сразу (без «Сохранить»).
`audio.gapless` выключен (и нет кроссфейда) — следующий трек не подгружается заранее.

## Профиль — `profile.*` (Аккаунт → Профиль, Windows 2026-11-16)

До сервера профиль хранится в настройках (синхронизируется как остальные); с сервером — `GET /me`
и `PATCH /me` (`API.md`). Пусто — имя и аватар из подключённого сервиса.

| Ключ | Значения | По умолчанию | Синк |
|---|---|---|---|
| `profile.name` | отображаемое имя (приветствие на главной), до 40 знаков | `''` | да |
| `profile.username` | `@username`: латиница, цифры, `_`, 3–32 | `''` | да |
| `profile.avatar` | WebP data URL 256×256, обрезан в круг (iPhone — JPEG data URL 256×256 из галереи, `ProfileEditView`) | `''` | да |

## Вид — `appearance.*` (`photo_13..15`, `pc/1..3`)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `appearance.mode` | `system` / `dark` / `light` — светлая: формулы `palette.ts SURFACES_LIGHT`, «как в системе» — `prefers-color-scheme` на лету | `dark` | да |
| `appearance.cover_theme` | bool — тема под обложку | `true` | да |
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
| `appearance.scale_fullscreen` (PC) | 75–125 % — когда окно развёрнуто | `100` | нет |

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
| `appearance.style` | `sonar` / `echo` / `signal` / `edge` / `tactile` / `monolith` / `custom:<id>` (сохранённый) / `custom` (несохранённый «Свой») | `sonar` | да |
| `appearance.surface` | `echo` / `signal` / `edge` / `tactile` / `monolith` — формулы фона, поверхностей, границ (OKLCH), тени и блики, вид кнопок | `monolith` | да |
| `appearance.font_display` | имя шрифта — заголовки («Моя волна», страницы, разделы) со своей шириной / жирностью | `Unbounded Variable` | да |
| `appearance.title_style` | `plain` / `editorial` (капсом, крупно, номера разделов «02», линейка над разделом) | `plain` | да |
| `appearance.icon_stroke` | `1.5` / `1.75` / `2` — толщина линий иконок панели и кнопок плеера | `2` | да |
| `appearance.anim_track` | `echo` / `signal` / `edge` / `tactile` / `monolith` / `fade` — анимация смены трека | `edge` | да |
| `appearance.anim_like` | `echo` / `signal` / `edge` / `tactile` / `monolith` / `pop` — анимация лайка | `signal` | да |
| `appearance.anim_nav` | `dot` / `capsule` / `plate` / `inset` — как отмечен выбранный раздел | `dot` | да |
| `appearance.progress_look` | `line` / `wave` / `groove` — как нарисован прогресс (место — `mini.progress`; вид из «Плеер → Вид» главнее) | `line` | да |
| `appearance.loading` | `color` (обложка из ч/б в цвет полосой) / `ring` (сектор в круге) — загрузка трека | `color` | да |
| `appearance.custom_styles` | список `{ id, name, axes }` — свои сохранённые стили | `[]` | да |

Готовые стили:

| Стиль | surface | шрифт / заголовки | линия | смена трека | лайк | раздел | прогресс | загрузка |
|---|---|---|---|---|---|---|---|---|
| **Sonar** | monolith | Golos Text / Unbounded | 2 | edge | signal | dot | line | color |
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

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `player.style` | `standard` / `vinyl` (винил крутится, игла) / `large` (обложка на всю колонку; на iPhone — на весь фон, `player.jpg`) | `standard` (PC), `large` (iOS) | да |
| `player.visualizer` (PC) | `off` / `bar` / `cover` (на обложке) / `slider` (на ползунке) | `bar` | да |
| `player.queue_view` | `normal` / `extended` | `extended` | да |
| `player.background` | `none` / `cover_blur` / `cover_color` (iPhone: для `standard` и `vinyl`; у `large` фон — сама обложка) | `none` (PC), `cover_blur` (iOS) | да |
| `player.title_align` | `left` / `center` / `right` | `center` | да |
| `player.slider` | `normal` / `thin` / `smooth` / `wave_bars` / `wavy` | `normal` | да |
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
| `player.cover_position` (PC) | `left` / `right` | `left` | да |
| `player.cover_in_cover` (PC) | bool | `false` | да |
| `player.volume` (PC) | 0…1 | `0.8` | нет |
| `audio.eq` (PC) | 12 чисел, дБ ±12 (32 Гц … 20 кГц) — кривая эквалайзера, одна на все треки; правки звучат сразу, пишутся только кнопкой «Сохранить», закрыл без неё — вернулась сохранённая | все `0` | нет |
| `audio.eq_presets` (PC) | `[{name, gains}]` — свои пресеты («+»); встроенные: Нейтральный, Басы, Высокие, Вокал, Громче | `[]` | да |
| `player.tempo` (PC) | `{rate 0.5–2, pitch −12…+12 пт, linked, keep, reverb 0–1}` — меню у кнопки-часов: готовые ×0.8 … ×1.35, ползунки скорости и тона с −/+, «Связать тон со скоростью», «Сохранять между треками», реверб. Заменяет `player.speed_mode` (slowed / speed переносятся в 0.8 / 1.25) | `{1, 0, true, true, 0}` | нет |

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

## Очередь — `queue.*` (PC `pc/7`; на iOS — часть «Плеера»)

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

## Вкладки PC — `tabs.*` (Интерфейс → Вкладки, 2026-11-16)

| Ключ | Значения | По умолчанию | Синк |
|---|---|---|---|
| `tabs.position` | `left` / `right` / `top` (полоса, кнопки окна на её конце) / `bottom` | `left` | да |
| `tabs.style` | `default` / `compact` / `full` (во всю высоту, у края) / `round` / `floating` (капсула над окном, тянется куда угодно; вдоль — при позиции сверху / снизу) | `default` | да |
| `tabs.float_x`, `tabs.float_y` | центр плавающей панели в долях окна | `0.045`, `0.5` | да |
| `tabs.adapt` | bool — цвет панели от подкраски страницы | `false` | да |
| `tabs.autohide` | bool — мышь замерла 3 с: панель и мини-плеер гаснут | `false` | да |
| `tabs.collapse` (iOS) | bool — при прокрутке вниз вкладки и мини-плеер сворачиваются в одну строку | `true` | да |

На iPhone «Вкладки» — стиль нижней панели (`appearance.tab_style`), `tabs.adapt` (панель в цвет подкраски темы) и `tabs.collapse`; позиции нет — панель всегда снизу. Экраны iOS «Интерфейса» — `ios/Sonar/Features/Settings/Look/` (`LookSettingsView`, `TabsSettingsView`, `ProfileEditView`); на iPhone из осей стиля пока применяется только поверхность, остальные оси выбор стиля пишет как ПК — синк не превращает стиль в «Свой».

## Мини-плеер PC — `mini.*` (`pc/8, 9`)

| Ключ | Значения | По умолч. |
|---|---|---|
| `mini.style` | `off` / `full` / `rounded` / `hybrid` / `deck` — пресет, выставляет фон/прогресс/обложку/форму (`PLATFORMS.md`) | `hybrid` |
| `mini.position` | `top` / `bottom` / `bottom_inset` / `floating` (перетаскивается, `mini.float_x` / `mini.float_y` — доли окна) | `bottom` |
| `mini.background` | `theme` / `cover` / `cover_color` | `theme` (пресет «Гибрид») |
| `mini.progress` | `line` / `background` (без `around_cover`) | `background` |
| `mini.cover_shape` | `default` / `circle` | `circle` |
| `mini.shape` | `default` / `capsule` | `capsule` |

## Оверлей PC — `overlay.*` (`pc/10, 11`) — **не делаем** (решение 2026-11-14)

`overlay.mode` (`off` / `fullscreen` / `island` / `card` / `sticky`), `overlay.shape`
(`square` / `rounded`), `overlay.position`, `overlay.opacity` (90), `overlay.scale` (100),
`overlay.width` (340), `overlay.height` (58).

## Интеграции — `integrations.*` (`photo_3`, `pc/14, 15`)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `integrations.lastfm.scrobble` | bool | `true` | сервер |
| `integrations.lastfm.now_playing` | bool | `true` | сервер |
| `integrations.discord.enabled` (PC) | bool | `true` | да |
| `integrations.discord.cover` (PC) | bool | `true` | да |
| `integrations.discord.progress` (PC) | bool | `true` | да |

ID приложения Discord — **не настройка**: пользователь ничего не вписывает. До сервера он вшит
в сборку (`windows/src-tauri/src/discord.rs` `APP_ID`), потом приходит с сервера (`GET /config`).

iOS Last.fm (2026-11-17, `LastfmSettingsView`, `Core/Integrations/`): вход в один клик — `auth.getToken` →
страница «Разрешить доступ» в окне входа iOS (`ASWebAuthenticationSession`, возврат `sonar://lastfm` + опрос
`auth.getSession`), ключ сессии — Keychain. Скроббл — трек > 30 с, прослушана половина или 4 мин; «Сейчас
играет» — на старт трека; не ушло — очередь до 14 дней. Ключ приложения — Info.plist `SonarLastfmKey` /
`SonarLastfmSecret` из секретов CI; нет — «Last.fm появится в сборке с ключом».

Ключ API (для selfbot и `GET /oauth/now`) — создать / перевыпустить / удалить, показывается
один раз. iOS: Безопасность, Приватность и Ключ API до сервера — честная заглушка `ServerOnlyView`. OBS-плашка (`pc/15`) — после MVP, тем же ключом.

## Система PC — `system.*` (`pc/16`)

`system.autostart` (true), `system.tray` (true), `system.power_saving`
(`off` / `minimized` / `background`, по умолч. `background`).

### Горячие клавиши PC — `hotkeys.*` (Система → Горячие клавиши, решение владельца 2026-11-17)

По всей системе (`tauri-plugin-global-shortcut`, `hotkeys.rs`), работают и в трее. Клик по сочетанию —
«нажми новое», Esc — отмена, Backspace — без клавиши; нужен модификатор. Сочетание занято другой
программой — строка подсвечена «Не встало». Одно сочетание на два действия не ставится.

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `hotkeys.enabled` | bool | `false` | нет |
| `hotkeys.map` | действие → сочетание (`KeyboardEvent.code`): `toggle` Ctrl+Alt+Space, `next` Ctrl+Alt+→, `prev` Ctrl+Alt+←, `like` Ctrl+Alt+L, `volume_up` Ctrl+Alt+↑, `volume_down` Ctrl+Alt+↓ (±5 %), `window` Ctrl+Alt+S (показать / скрыть окно) | см. слева | нет |

## Кэш / Хранилище — `storage.*` (`pc/18`, iOS «Кэш»)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `storage.cache_tracks` | bool — прослушанное на диск (`track_cache.rs`: файлы на лету, HLS — склейкой) | `false` | нет |
| `storage.cache_limit_mb` | 512 / 1024 / 2048 / 5120 / 10240 — сверх лимита вытесняются давно не игравшие | `2048` | нет |
| `storage.wave_offline` (PC) | bool — «Волна офлайн»: следующие 15 треков «Моей волны» фоном по одному качаются в кэш треков (`prefetch_tracks` → `stream.rs` `prefetch`); только при включённом кэше | `false` | нет |

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
