# Sonar — модуль синхронизации текстов (ПК, Tauri)

Берёт позицию трека и строки с таймкодами, говорит интерфейсу, какая строка и какое слово
сейчас активны и насколько (0..1) они пропеты. Источник текстов — SPEC §3.7б
(lrclib → Genius, на устройстве). Тот же модуль потом переносится в iOS.

## 1. Данные

```ts
type Lyrics = { isSynced: boolean; source: "lrclib" | "genius" | "server"; lines: Line[] }
type Line = {
  time: number; duration: number;          // секунды
  text: string; translation?: string;
  agent?: string;                          // кто поёт
  isBackground: boolean;                   // бэк-вокал
  words?: Word[];                          // нет → построчный режим для этой строки
}
type Word = { time: number; duration: number; text: string; isBackground: boolean; hasSpaceAfter: boolean }
```

- `isSynced = false` (Genius, plain из lrclib) → обычный текст: без подсветки и автопрокрутки.
- `duration` строки = `next.time - time` (у последней — до конца трека, но не больше 10 с).
- Режим подсветки `lyrics.mode`: `lines` | `words` (настройка, sync).
- **Откуда слова (разобрано по фронтенду Dotify, 2026-11-14):** у Dotify тексты приходят
  **с их собственного сервера** (`GET /lyrics?title&artist&duration&source&track_id`,
  protobuf `LyricLine{time, duration, text, translation, agent, is_background, words[]}`) —
  твоё ТЗ повторяет именно этот формат. Откуда их сервер берёт пословные тайминги, из
  фронтенда не видно (так выглядят данные Apple Music / Musixmatch richsync). Их API закрытый
  и не наш — не используем. У нас:
  1. lrclib: обычно только строки; иногда enhanced-LRC (`<mm:ss.xx>` у слов) — разбираем.
  2. **Позже, по желанию:** провайдер пословных текстов за тем же трейтом
     (`LyricsProvider`) — кандидаты Musixmatch richsync (нужен токен) или NetEase (YRC,
     в основном азиатская музыка). Формат на выходе тот же — интерфейс не меняется.
  3. Нет слов у строки → строка подсвечивается целиком по её `progress`; в меню у «По словам»
     подсказка «для этого трека — только по строкам». Слова **не придумываем** равномерно.
- **Заметка владельца про Dotify (2026-11-14, запомнить на будущее, сейчас не делаем):**
  фронт Dotify не ходит в lrclib / Genius / Musixmatch — только один `GET /lyrics?title&artist&
  duration&source&track_id` на свой сервер, ответ protobuf `LyricsResponse` (`lines`, `isSynced`,
  аннотации). Базовый адрес API в бандле не найден (виден только `dotify.fun`). Фронт вырезает из
  LRC водяные знаки `lrcgenerator`, `rentanadviser`, `megalobiz`, `lyricsify`, `syair.info`,
  `minilyrics`, `viewlyrics`, `crintsoft` → их сервер собирает тексты из нескольких LRC-сайтов и,
  вероятно, ищет по `track_id` сервиса (у lrclib — только название/исполнитель/длительность),
  поэтому покрытие шире. Плюс у них перевод (`translateLyrics`), слова (`words`) и сдвиг
  (`lyricsOffset`). Для Sonar это кандидат в `ServerProvider` (§8): свой сервер-агрегатор
  с тем же форматом `Lyrics` — когда появится сервер.
- Парсер LRC: `[mm:ss.xx]`, несколько таймкодов на строку, `[offset:±ms]` из файла,
  пустые строки = паузы (проигрыш → индикатор «•••»), строки в `( )` → `isBackground`.

## 2. Часы плеера (главное)

`currentTime` напрямую не используем. Состояние часов:

```ts
type Clock = { anchorTime: number; anchorTs: number; rate: number; last: number; mode: "running" | "raw" }
```

- `now(ts)` (ts = `performance.now()`):
  `mode == "raw"` (пауза, seek, загрузка) → `audio.currentTime` как есть;
  иначе `anchorTime + (ts - anchorTs)/1000 * rate`.
- `sample(audioTime, ts)` — на каждом `timeupdate`:
  `diff = audioTime - now(ts)`; `|diff| > 0.35` → жёстко `anchor = (audioTime, ts)`;
  иначе мягко: `anchorTime = now(ts) + diff * 0.25`, `anchorTs = ts`.
- Монотонность: `t = max(t, last)` между кадрами, **кроме** явного seek (seek сбрасывает
  `last`). `t = clamp(t, 0, duration)`.
- События `pause`, `seeking`, `waiting` → `mode = "raw"`; `playing` → новый якорь,
  `mode = "running"`; `ratechange` → новый якорь с новым `rate` (скорость 0.5–2×, SPEC §4.3).
- Рисуем по `requestAnimationFrame`; окно свёрнуто или экран текста скрыт
  (`document.hidden`, событие Tauri `minimize`) → цикл стоит.

## 3. Текущая строка

- `t' = t + offset` (§5). Активна строка с `time <= t'`, у которой следующая ещё не началась.
- До первой строки `index = -1`.
- Поиск: от прошлого индекса ±2 шага (обычный случай), иначе бинарный поиск по `time`.

## 4. Прогресс слова (режим `words`)

```ts
d = max(word.duration, 0.05)
isPast    = t' >= word.time + d
isCurrent = word.time <= t' && t' < word.time + d
progress  = isPast ? 1 : isCurrent ? clamp((t' - word.time) / d, 0, 1) : 0
```

- Подсветка: CSS-маска `linear-gradient` слева направо, край `progress ± 7%`
  (`--p` на элементе слова). Будущие слова — 35 % яркости, прошедшие — 100 %.
- Бэк-вокал и слова в скобках — 0.8em и 60 % яркости.
- Прогресс строки (для режима `lines` и строк без слов) — та же формула по строке.

## 5. Смещение

- `offset` в секундах, `-15..+15`, шаг 0.001 (округлять до 3 знаков), **на каждый трек**.
- Хранение: локальный SQLite, таблица `track_prefs` (DB.md), поле `lyrics_offset_ms`
  (= `round(offset*1000)`). `0` → поле `NULL`, пустая запись удаляется. После появления
  сервера синхронизируется (тип `track_pref`).
- В меню текста (PLATFORMS.md): кнопки −0.1 / −0.01 / +0.01 / +0.1 с, значение «±0.000 с»,
  «Сброс». Прибавляется к `t` до поиска строки и слова.

## 6. Эффекты и настройки (после ядра)

- Размер `lyrics.size`: **S / M / L / XL** (у Dotify тоже sm/md/lg/xl) → CSS-переменная `--lyrics-size`
  (1.25 / 1.6 / 2 / 2.5 rem). Все размеры внутри — em. Прокрутка к строке считает
  **реальную высоту** узлов (`getBoundingClientRect`), длинные строки переносятся.
- Анимация смены строк `lyrics.animation`: Обычная · Фейд · Размытие · 3D-переворот ·
  Отскок · Волна · Всплытие · Дрифт · Глубина (названия как в Dotify, реализация своя;
  в MVP — Обычная, Фейд, Размытие, остальные потом).
- Стиль подсветки `lyrics.style`: Обычный · Масштаб · Размытие · Кино · Сдвиг (как в Dotify).
- Длинное слово (`d >= 1.2 с`): лёгкая пульсация яркости/масштаба
  `k = sin(π·progress)²` (масштаб `1 + 0.04k`).
- `prefers-reduced-motion` или общий выключатель анимаций (`appearance.animations`) →
  только смена цвета, без размытия, масштаба и пульсации; прокрутка без плавности.

## 7. Кэш и подгрузка

- Память (LRU ~100 треков) → локальный SQLite (`lyrics_cache`: ref, json, source, fetched_at,
  used_at) → источник. **Срок хранения на компьютере** (решение владельца 2026-11-15): неделя с
  последнего прослушивания, у треков из Любимых — две недели; прослушивание продлевает срок,
  старое удаляется при запуске (`Store::prune_lyrics`). «Не найдено» тоже кэшируется, перепроверка через 30 мин (`RECHECK_TTL`).
- При старте трека — предзагрузка текста **следующего** трека в очереди.
- Нет текста → пустое состояние «Текст не найден», без ошибок и тостов.

## 8. Архитектура и где код

- **Rust** (`windows/src-tauri/src/lyrics/`, сделано в W4): `mod.rs` — типы §1, парсер LRC
  (enhanced-LRC со словами, `[offset]`, паузы, бэк-вокал), `fetch_any` (lrclib как есть →
  ядро названия без мусора → «АРТИСТ - ТРЕК» из перезалива → Genius → plain из lrclib);
  `lrclib.rs`, `genius.rs`. Кэш — SQLite `lyrics_cache` («нет» перепроверяется через 30 мин),
  в памяти — LRU на 100 треков в `lyrics.svelte.ts`. Команды `lyrics`, `lyrics_offset`,
  `set_lyrics_offset`. Трейт `LyricsProvider` и `ServerProvider` — когда появится сервер.
- **Genius и Cloudflare (проверено 2026-11-14):** на запросы из Rust (reqwest — и rustls,
  и schannel) Genius отвечает проверкой «я не робот» по TLS-отпечатку, а системный
  `C:\Windows\System32\curl.exe` (есть в Windows 10 1803+) и Python-requests пропускает.
  Поэтому Genius запрашивается через `curl.exe` скрытым процессом, reqwest — запасной путь.
- **TypeScript** (`windows/src/lyrics/core/`): **чистые функции без UI** — `clock.ts`
  (§2), `find.ts` (§3), `progress.ts` (§4), `offset.ts` (§5). Тесты — vitest
  (`windows/src/lyrics/core/*.test.ts`).
- **UI** (`windows/src/lyrics/`): `LyricsView.svelte` (rAF-цикл, прокрутка, заливка слов —
  градиент `background-clip: text` по `--p`), `LyricsMenu.svelte` (режим, размер, стиль,
  анимация, оффсет, «Найти заново», перевод — неактивен), `lyrics.svelte.ts` (загрузка,
  предзагрузка следующего, настройки). Полноэкранный плеер — `windows/src/player/FullPlayer.svelte`.

Обязательные тесты ядра: seek назад и вперёд, пауза/плей, скорость 0.5× и 2×, редкий
`timeupdate` (раз в 250–500 мс), пустой текст, текст без таймкодов, слова нулевой
длительности, оффсет ±15 с, время до первой строки и после последней.


## NetEase (2026-11-16)

Порядок поиска: lrclib (как есть → упрощённо → перезалив) → **NetEase** → Genius → plain из lrclib.
NetEase спрашивается, только если lrclib синхронного текста не нашёл: сначала пословный YRC
(`[начало,длит](начало_слова,длит,0)слово…`), нет его — построчный LRC. Совпадение строгое: название
≥ 0.75, артист ≥ 0.6, длительность ±3 с; титры («作词: …») выбрасываются. Код —
`windows/src-tauri/src/lyrics/netease.rs`, живой тест — `cargo test live_netease -- --ignored`.
