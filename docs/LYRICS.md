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
- **Откуда слова:** lrclib обычно отдаёт только строки. Слова — из enhanced-LRC
  (`<mm:ss.xx>` внутри строки), если есть. Нет — в режиме `words` строка подсвечивается
  целиком по `progress` строки (без придуманных таймингов слов); пункт «По словам» в меню
  показывает подсказку «для этого трека только по строкам».
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

- Размер `lyrics.size`: **S / M / L / XL** → CSS-переменная `--lyrics-size`
  (1.25 / 1.6 / 2 / 2.5 rem). Все размеры внутри — em. Прокрутка к строке считает
  **реальную высоту** узлов (`getBoundingClientRect`), длинные строки переносятся.
- Анимация `lyrics.animation`: размытие · масштаб · появление · сдвиг · без анимации.
- Стиль `lyrics.style`: Кино · Центр · Минимал · Караоке (PLATFORMS.md).
- Длинное слово (`d >= 1.2 с`): лёгкая пульсация яркости/масштаба
  `k = sin(π·progress)²` (масштаб `1 + 0.04k`).
- `prefers-reduced-motion` или общий выключатель анимаций (`appearance.animations`) →
  только смена цвета, без размытия, масштаба и пульсации; прокрутка без плавности.

## 7. Кэш и подгрузка

- Память (LRU ~100 треков) → локальный SQLite (`lyrics_cache`: ref, json, source, fetched_at)
  → источник. «Не найдено» тоже кэшируется, перепроверка через 30 мин (`RECHECK_TTL`).
- При старте трека — предзагрузка текста **следующего** трека в очереди.
- Нет текста → пустое состояние «Текст не найден», без ошибок и тостов.

## 8. Архитектура и где код

- **Rust** (`windows/src-tauri/src/lyrics/`): трейт `LyricsProvider { fetch(meta) -> Option<Lyrics> }`;
  реализации `LocalProvider` (lrclib → Genius, по названию, артисту, длительности) и потом
  `ServerProvider`. Кэш (память + SQLite), парсер LRC. На выходе всегда `Lyrics` из §1.
- **TypeScript** (`windows/src/lyrics/core/`): **чистые функции без UI** — `clock.ts`
  (§2), `find.ts` (§3), `progress.ts` (§4), `offset.ts` (§5). Тесты — vitest
  (`windows/src/lyrics/core/*.test.ts`).
- **UI** (`windows/src/lyrics/`): `LyricsView.svelte` (rAF-цикл, прокрутка, маски),
  `LyricsMenu.svelte` (режим, размер, стиль, анимация, оффсет, перевод).

Обязательные тесты ядра: seek назад и вперёд, пауза/плей, скорость 0.5× и 2×, редкий
`timeupdate` (раз в 250–500 мс), пустой текст, текст без таймкодов, слова нулевой
длительности, оффсет ±15 с, время до первой строки и после последней.
