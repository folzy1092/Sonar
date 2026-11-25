# Sonar — схема базы (SQLite)

Файл `server/data/sonar.db`, режим WAL. Id — ULID-строки с префиксом (`u_`, `pl_`, `d_`…).
Время — `INTEGER` миллисекунды Unix. `rev` — значение глобального счётчика `sync_rev`
на момент изменения (для `/sync/pull`).

**Сервер на деле (2026-11-25, этап 3 `SERVER_PROMPT.md`):** таблиц `likes`, `playlists`, `playlist_items`,
`settings`, `dislikes`, `track_prefs` на сервере нет — он хранит синк как хаб ПК (`store/hub.rs`), не разбирая
значения: так новый тип клиента не требует правок сервера. Таблицы ниже — схема клиентов (ПК — локальный SQLite).

```sql
CREATE TABLE sync_rows (          -- строка синка: (тип, ключ) → JSON, value_json NULL — удалено
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,             -- like | playlist | playlist_item | setting | player_state | track_pref | dislike | wave_event
  key TEXT NOT NULL, value_json TEXT, rev INTEGER NOT NULL, client_ts INTEGER NOT NULL,
  PRIMARY KEY (user_id, type, key));
CREATE INDEX sync_rows_rev ON sync_rows(user_id, rev);
CREATE TABLE sync_ops (user_id TEXT NOT NULL, op_id TEXT NOT NULL, at INTEGER NOT NULL,  -- виденные op_id, 30 дней
  PRIMARY KEY (user_id, op_id));
CREATE TABLE sync_rev (id INTEGER PRIMARY KEY CHECK (id = 1), value INTEGER NOT NULL);   -- один счётчик на сервер
-- tracks сервера: + artists_json, url (карточки из /dotify); player_state: + device_id, state_json (PUT /player/state)
```

Префиксы `ref` — из реестра сервисов (полная таблица и правило разбора — `API.md` §2 «Префиксы ref»):

| id | key | трек | альбом | артист | плейлист |
|---|---|---|---|---|---|
| `sc` | `soundcloud` | `sc:` | `scalb:` | `sca:` | `scpl:` |
| `ym` | `yandex` | `ym:` | `ymalb:` | `yma:` | `ympl:` |
| `yt` | `youtube` | `yt:` | `ytalb:` | `yta:` | `ytpl:` |
| `vk` | `vk` | `vk:` | `vkalb:` | `vka:` | `vkpl:` |
| `sp` | `spotify` | `sp:` | `spalb:` | `spa:` | `sppl:` |
| `local` | `local` | `local:` | — | — | — |

Работают `sc`, `ym`, `yt`, `vk`, `sp` и `local` (Spotify — медиатека и ссылки; ключ `sp_dc` — только в keyring / Keychain под
key `spotify`, в базу не попадает, API.md §2 «Spotify»). Префикс — текст до первого `:`, сравнивается целиком. Не сервисы: `pl_…`, `similar:<ref>`.

```sql
CREATE TABLE users (
  id            TEXT PRIMARY KEY,
  number        INTEGER UNIQUE NOT NULL,        -- #104633, по порядку
  login         TEXT UNIQUE NOT NULL COLLATE NOCASE,  -- не меняется (только админ)
  username      TEXT UNIQUE NOT NULL COLLATE NOCASE,  -- @username, меняется
  display_name  TEXT NOT NULL,
  avatar_path   TEXT,                           -- data/avatars/<id>.jpg
  bg_path       TEXT,                           -- data/backgrounds/<id>.<jpg|mp4>
  bg_kind       TEXT,                           -- image | video
  password_hash TEXT,                           -- NULL, если вошёл только через Telegram
  tg_id         INTEGER UNIQUE,
  tg_username   TEXT,
  is_admin      INTEGER NOT NULL DEFAULT 0,
  banned        INTEGER NOT NULL DEFAULT 0,
  ban_reason    TEXT,                           -- причина бана из админки (миграция в server/sonar/db.py COLUMNS)
  banned_at     INTEGER,
  created_at    INTEGER NOT NULL
);

CREATE TABLE sessions (                         -- одна строка = одно устройство в «Устройствах» (API.md §1)
  id            TEXT PRIMARY KEY,               -- d_... (id сессии, в API — Device.id)
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash    TEXT UNIQUE NOT NULL,           -- sha256(session)
  device_id     TEXT NOT NULL,                  -- постоянный id от клиента: iPhone — UUID из Keychain, ПК — HWID
  device_name   TEXT NOT NULL,                  -- «iPhone 15 Pro», «Windows 10 (Folzy)»; пользователь может переименовать
  platform      TEXT NOT NULL,                  -- ios | windows | android
  os            TEXT,                           -- «iOS 18.1», «Windows 10 22H2»
  app_version   TEXT,                           -- последняя версия Sonar, о которой сообщило устройство
  build         INTEGER,
  created_at    INTEGER NOT NULL,               -- вход; моложе 24 ч — завершать другие сессии нельзя
  last_seen_at  INTEGER NOT NULL,               -- последний запрос (и PUT /me/device при запуске)
  UNIQUE (user_id, device_id)                   -- повторный вход с того же устройства заменяет строку
);

CREATE TABLE tg_requests (                      -- быстрый вход и привязка
  id            TEXT PRIMARY KEY,
  secret_hash   TEXT UNIQUE NOT NULL,
  purpose       TEXT NOT NULL,                  -- login | link
  user_id       TEXT REFERENCES users(id),      -- для link — кто привязывает; для login — кто вошёл
  device_json   TEXT,
  status        TEXT NOT NULL DEFAULT 'pending',-- pending | approved | rejected | expired
  session_plain TEXT,                           -- отдаётся один раз в poll, потом стирается
  created_at    INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL
);

CREATE TABLE service_accounts (
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service       TEXT NOT NULL,                  -- soundcloud | yandex | youtube | spotify (старые vk не отдаются)
  credentials   BLOB NOT NULL,                  -- Fernet(JSON полей, как в API.md «Сервисы»: client_id, oauth_token / token / cookie / sp_dc)
  ext_user_id   TEXT,
  ext_name      TEXT,
  ext_avatar    TEXT,
  connected_at  INTEGER NOT NULL,
  PRIMARY KEY (user_id, service)
);

CREATE TABLE tracks (                           -- кэш метаданных
  ref           TEXT PRIMARY KEY,               -- ref трека по таблице префиксов: sc:123 | ym:456
  title         TEXT NOT NULL,
  artist        TEXT NOT NULL,
  artists_json  TEXT,
  album_json    TEXT,
  duration_ms   INTEGER NOT NULL,
  cover_url     TEXT,
  url           TEXT,
  fetched_at    INTEGER NOT NULL,
  tags          TEXT                            -- жанр + теги SoundCloud / жанр Яндекса (миграция 6);
                                                -- пустое значение при upsert старые теги не затирает
);

CREATE TABLE likes (                            -- треки, альбомы, исполнители
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ref           TEXT NOT NULL,                  -- по таблице префиксов: sc:/ym: трек, scalb:/ymalb: альбом, sca:/yma: артист
  kind          TEXT NOT NULL,                  -- track | album | artist (вид по префиксу из таблицы, дублируется для индекса)
  added_at      INTEGER NOT NULL,
  deleted       INTEGER NOT NULL DEFAULT 0,     -- tombstone для синка
  rev           INTEGER NOT NULL,
  PRIMARY KEY (user_id, ref)
);

CREATE TABLE playlists (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  cover_path    TEXT,                           -- NULL → коллаж из 4 обложек
  hidden        INTEGER NOT NULL DEFAULT 0,
  source_ref    TEXT,                           -- scpl:… / ympl:… / ytpl:… если перенесён
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  deleted       INTEGER NOT NULL DEFAULT 0,
  rev           INTEGER NOT NULL
);

CREATE TABLE playlist_items (
  id            TEXT PRIMARY KEY,
  playlist_id   TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  ref           TEXT NOT NULL,
  position      REAL NOT NULL,                  -- дробные позиции: вставка без перенумерации
  added_at      INTEGER NOT NULL,
  added_by      TEXT REFERENCES users(id),      -- кто добавил; только в совместном плейлисте (API.md §4 «Совместные плейлисты»)
  deleted       INTEGER NOT NULL DEFAULT 0,
  rev           INTEGER NOT NULL
);
CREATE INDEX playlist_items_pl ON playlist_items(playlist_id, position);

-- Участники совместного плейлиста (2026-11-22). Владелец — playlists.user_id, сюда не пишется.
-- На клиенте (Windows, миграция № 15) таблицы нет: playlists.collab_json — {owner, collaborators}
-- из синка как есть (NULL — обычный плейлист), playlist_items.added_by — username.
CREATE TABLE playlist_collaborators (
  playlist_id   TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  added_at      INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, user_id)
);
CREATE INDEX playlist_collaborators_user ON playlist_collaborators(user_id);

CREATE TABLE settings (
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key           TEXT NOT NULL,                  -- appearance.cover_theme
  value_json    TEXT NOT NULL,
  client_ts     INTEGER NOT NULL,               -- для «побеждает позднее»
  rev           INTEGER NOT NULL,
  PRIMARY KEY (user_id, key)
);

CREATE TABLE player_state (
  user_id       TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  device_id     TEXT,
  ref           TEXT,
  context       TEXT,
  is_playing    INTEGER NOT NULL DEFAULT 0,
  position_ms   INTEGER NOT NULL DEFAULT 0,
  queue_json    TEXT,
  queue_index   INTEGER,
  shuffle       INTEGER NOT NULL DEFAULT 0,
  repeat        TEXT NOT NULL DEFAULT 'off',
  updated_at    INTEGER NOT NULL,               -- время сервера при приёме
  rev           INTEGER NOT NULL
);

CREATE TABLE plays (
  id            INTEGER PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ref           TEXT NOT NULL,
  artist        TEXT NOT NULL,                  -- денормализовано для быстрых топов
  context       TEXT,
  played_at     INTEGER NOT NULL,
  listened_ms   INTEGER NOT NULL,
  scrobbled     INTEGER NOT NULL DEFAULT 0,
  UNIQUE (user_id, ref, played_at)              -- повторная отправка пачки не дублирует
);
CREATE INDEX plays_user_time ON plays(user_id, played_at);

CREATE TABLE api_keys (
  user_id       TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  key_hash      TEXT UNIQUE NOT NULL,           -- sha256, для поиска по запросу
  key_enc       TEXT NOT NULL,                  -- Fernet: токен виден в боте всегда (BOT.md §2.6а)
  created_at    INTEGER NOT NULL
);

CREATE TABLE track_prefs (                      -- «Запомнить» скорость и т.п. для трека
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ref           TEXT NOT NULL,
  speed         REAL,                           -- 0.5 … 2.0
  lyrics_offset_ms INTEGER,
  eq_json       TEXT,                           -- эквалайзер трека (с 2026-11-16 не используется: кривая одна, audio.eq)
  sound_json    TEXT,                           -- «Для этого трека» (2026-11-22): {rate, pitch, linked, reverb 0…1 (0 — выкл), eq: [12]|null, space 0…16 (0 — выкл; нет поля — 0)}; speed = rate для старых клиентов
  source        TEXT,                           -- «Играть из» (2026-11-25; Windows — миграция № 19): sc | ym | yt, NULL — «Авто»
  deleted       INTEGER NOT NULL DEFAULT 0,
  rev           INTEGER NOT NULL,
  PRIMARY KEY (user_id, ref)
);

CREATE TABLE catalog (                          -- кэш альбомов и исполнителей (как tracks)
  ref           TEXT PRIMARY KEY,               -- scalb:/ymalb: | sca:/yma: (таблица префиксов) | similar:<ref трека>
  kind          TEXT NOT NULL,                  -- album | artist | similar (кэш «похожих» волны, 24 ч, только локально)
  json          TEXT NOT NULL,                  -- Album / Artist (API.md §3) | [Track] для similar
  fetched_at    INTEGER NOT NULL
);
CREATE INDEX likes_kind ON likes(user_id, kind, deleted, added_at);

CREATE TABLE lyrics_cache (                     -- только на клиенте (ПК/iOS), не на сервере
  ref           TEXT PRIMARY KEY,
  json          TEXT,                           -- Lyrics (docs/LYRICS.md §1); NULL = «не найдено»
  source        TEXT,                           -- lrclib | genius
  fetched_at    INTEGER NOT NULL,
  used_at       INTEGER                         -- последнее прослушивание; хранится 7 дней, у Любимых 14
);

CREATE TABLE dislikes (                         -- 👎 своей волны (SPEC §3.7): трек больше не ставится
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ref           TEXT NOT NULL,
  artist        TEXT NOT NULL,
  added_at      INTEGER NOT NULL,
  deleted       INTEGER NOT NULL DEFAULT 0,     -- снятый 👎 — tombstone для синка
  rev           INTEGER NOT NULL,
  PRIMARY KEY (user_id, ref)
);

CREATE TABLE search_history (                   -- история поиска (миграция 9), только локально, в синк не идёт
  id            INTEGER PRIMARY KEY,
  user_id       TEXT NOT NULL,
  kind          TEXT NOT NULL,                  -- query | track | artist | album | playlist
  query         TEXT NOT NULL DEFAULT '',       -- запрос (у результата — с которого открыли)
  ref           TEXT,                           -- открытый результат
  title         TEXT,
  subtitle      TEXT,
  cover_url     TEXT,
  at            INTEGER NOT NULL
);                                              -- повтор поднимает наверх, храним последние 100
CREATE INDEX search_history_time ON search_history(user_id, at);

CREATE TABLE skips (                            -- ручной пропуск в волне с оценкой < 0 (WAVE.md 1.3) — минус артисту и треку
  id            INTEGER PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ref           TEXT NOT NULL,
  artist        TEXT NOT NULL,
  played_ms     INTEGER NOT NULL,
  at            INTEGER NOT NULL
);
CREATE INDEX skips_user_time ON skips(user_id, at);

CREATE TABLE wave_events (                      -- журнал волны (WAVE.md, этап 6); едет в синк аккаунта (миграция № 8, WAVE.md §3а)
  id            TEXT PRIMARY KEY,               -- we_… (глобально уникальный); строки старше 180 дней удаляются при запуске
  user_id       TEXT NOT NULL,
  device_id     TEXT NOT NULL,                  -- d_… — откуда событие
  rev           INTEGER NOT NULL,               -- выдача и исход поднимают rev (синк)
  session_id    TEXT NOT NULL,                  -- сессия волны (создаёт клиент)
  ref           TEXT NOT NULL,
  artist        TEXT NOT NULL,                  -- главный артист, нижний регистр
  mode          TEXT NOT NULL,                  -- own | hard | calm | sad | fun | new
  source        TEXT NOT NULL,                  -- similar | hop2 | liked | artist | seed
  seed_ref      TEXT,                           -- от какого сида пришёл
  features_json TEXT,                           -- Features на момент выдачи (wave.rs), по ним подбирают веса
  served_at     INTEGER NOT NULL,
  reward        REAL,                           -- оценка исхода (WAVE.md 1.3); пусто, пока трек не сыгран
  listened_ms   INTEGER,
  ended_at      INTEGER
);
CREATE INDEX wave_events_time ON wave_events(user_id, served_at);
CREATE INDEX wave_events_ref ON wave_events(session_id, ref);

CREATE TABLE notifications (
  id            TEXT PRIMARY KEY,
  user_id       TEXT REFERENCES users(id) ON DELETE CASCADE,   -- NULL = всем (рассылка)
  title         TEXT,
  text          TEXT NOT NULL,
  created_at    INTEGER NOT NULL
);

CREATE TABLE notification_reads (
  user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  notification_id TEXT NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, notification_id)
);

CREATE TABLE sync_rev (id INTEGER PRIMARY KEY CHECK (id = 1), value INTEGER NOT NULL);

-- только клиент (Windows, миграция № 8): курсоры синка и id устройства
CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT NOT NULL);
-- device_id — d_…; pushed_rev — до какого локального rev всё отправлено (неотправленное = rev новее);
-- pulled_rev — до какого серверного rev получено; plays_uploaded_id — курсор POST /plays.
-- Пришедшее с сервера пишется с rev = 0 (обратно не едет); своё неотправленное изменение строки
-- пришедшее не перезаписывает.

-- только клиент (Windows, миграция № 10): локальные файлы — «Папки с музыкой» (NEXT_PROMPT этап 10).
-- Только на этом устройстве, в синк не идёт; лайки и плейлисты хранят обычный ref.
CREATE TABLE local_files (
  ref           TEXT PRIMARY KEY,               -- local:<sha1 пути> — стабилен, пока файл лежит на месте
  path          TEXT UNIQUE NOT NULL,           -- полный путь файла
  mtime         INTEGER NOT NULL,               -- время изменения, мс; вместе с size решает, читать ли теги заново
  size          INTEGER NOT NULL,
  title         TEXT NOT NULL,                  -- из тегов (lofty), иначе из имени «Исполнитель - Название»
  artist        TEXT NOT NULL,                  -- пусто — «Неизвестный исполнитель»
  album         TEXT,
  duration_ms   INTEGER NOT NULL,
  cover_path    TEXT                            -- кэш обложек: covers/local-<sha1 картинки>.<ext>
);
-- Скан пишет и метаданные в tracks (Любимые и плейлисты видят новые теги). Пропавший файл и папка,
-- которой сейчас нет (флешка), строк не теряют — трек приходит с available = false («Файл не найден» с
-- «Найти в сервисах»). Строка удаляется, только если её папку убрали из storage.music_folders или файл
-- переехал (в тех же папках есть файл того же размера с теми же названием и исполнителем); обход
-- остановлен на 50 000 файлах — непросмотренные строки не трогаются. Неиспользуемые обложки local-* чистятся.

-- только клиент (Windows, миграция № 11): резервный сервис (NEXT_PROMPT этап 4, services/fallback.rs).
-- Свой сервис трек не играет — ищем тот же в другом (порядок audio.fallback_order); найденное и
-- «не нашлось» запоминаются, чтобы не искать заново. Только на этом устройстве, в синк не идёт.
CREATE TABLE track_alias (
  source_ref    TEXT NOT NULL,                  -- трек, который не играет: sc:… / ym:… / sp:…
  service       TEXT NOT NULL,                  -- где искали: короткий id реестра (sc, ym, yt, vk)
  alias_ref     TEXT,                           -- найденный тот же трек; NULL — там его нет
  found_at      INTEGER NOT NULL,               -- мс
  PRIMARY KEY (source_ref, service)
);
-- Сверка строгая (providers/matching.rs): длительность ±3 с, исполнитель, название, те же «версии»
-- (remix, live, slowed…). Найденное живёт, пока не перестанет играть (тогда ищется заново); «не
-- нашлось» — 7 дней, старше чистится при запуске. Метаданные найденного трека пишутся в tracks.
-- iPhone до сервера — без таблицы: пары держатся в памяти на сеанс (Core/Providers/MusicCore+Fallback.swift).

-- Умные плейлисты (NEXT_PROMPT этап 6; Windows — миграция № 12). Треков не хранят: при каждом открытии
-- считаются заново по правилам из plays, likes и playlist_items. Формат rules_json — общий для ПК и iPhone,
-- docs/PLATFORMS.md «Умные плейлисты». Синк — позже (поля deleted и rev уже под него).
CREATE TABLE smart_playlists (
  id            TEXT PRIMARY KEY,               -- sm_<16 hex>
  user_id       TEXT NOT NULL,
  name          TEXT NOT NULL,
  rules_json    TEXT NOT NULL,                  -- {"v":1,"source":…,"match":…,"conditions":[…],"sort":…,"limit":…}
  created_at    INTEGER NOT NULL,               -- мс
  updated_at    INTEGER NOT NULL,               -- мс
  deleted       INTEGER NOT NULL DEFAULT 0,
  rev           INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX smart_playlists_user ON smart_playlists(user_id, deleted);
-- iPhone до сервера: Application Support/Sonar/smart.json — [{id, name, rules, created_at, updated_at}]
-- (rules — тот же объект, не строка); дата лайка — likedAt в library.json.

-- Карта исполнителей (Медиатека → Исполнители → Карта; Windows — миграция № 13). Граф считается на
-- лету из likes, playlist_items, plays и tracks (artist_graph/); здесь — только то, что пришлось скачать.
-- Подписки исполнителей SoundCloud: кто на кого подписан — связь «подписаны друг на друга» / «подписан».
-- Качается фоном пачками с паузами, живёт 7 дней; 404 — пустой список, 429 — пауза на 30 мин.
CREATE TABLE artist_follows (
  artist_ref    TEXT PRIMARY KEY,               -- sca:<id> — чьи подписки
  follows_json  TEXT NOT NULL,                  -- [Artist] (docs/API.md), до 200 штук
  fetched_at    INTEGER NOT NULL                -- мс
);
-- Треки «фантомных» плейлистов сервисов (лайки SoundCloud, «Мне нравится» Яндекса…), которые ещё не
-- перенесены в Sonar: только ref, метаданные — в tracks. Обновляются раз в сутки, целиком по source_ref.
CREATE TABLE artist_phantom_tracks (
  source_ref    TEXT NOT NULL,                  -- scpl:likes | ympl:likes | ytpl:likes | vkpl:likes | sppl:likes
  ref           TEXT NOT NULL,                  -- sc:… / ym:… — трек
  fetched_at    INTEGER NOT NULL,               -- мс
  PRIMARY KEY (source_ref, ref)
);
-- iPhone — карты пока нет.

-- только клиент (Windows, миграция № 16): что из сервисов лежит на диске и играет без сети (OFFLINE.md §7.1).
-- Пишет кэш треков (track_cache → offline_index.rs), при запуске сверяется с папкой кэша. В синк не идёт.
-- Доступно в офлайне (offline_refs) = offline_tracks ∪ local_files ∪ source_ref двойников (track_alias) из кэша.
CREATE TABLE offline_tracks (
  ref           TEXT PRIMARY KEY,               -- sc:… / ym:… — трек
  file          TEXT NOT NULL,                  -- имя файла в папке кэша (<key>.audio)
  mime          TEXT NOT NULL,
  bytes         INTEGER NOT NULL,
  quality       TEXT,                           -- пока не заполняется (этап 2)
  kind          TEXT NOT NULL,                  -- cache — лёг сам; pinned — «Скачать» (этап 2)
  added_at      INTEGER NOT NULL,               -- мс
  last_played   INTEGER,
  meta_json     TEXT NOT NULL                   -- снимок Track (API.md): офлайн-список показывает название, даже если tracks переписали
);
CREATE INDEX offline_tracks_file ON offline_tracks(file);

-- только клиент (Windows, миграция № 17): сведение (BLEND.md §5). В синк не идёт.
CREATE TABLE blend_analysis (                   -- анализ трека: темп, сетка, такты, фразы, тональность, громкость
  ref           TEXT PRIMARY KEY,
  version       INTEGER NOT NULL,               -- ANALYSIS_VERSION; другая — пересчёт при следующем проигрывании
  data_json     TEXT NOT NULL,                  -- BlendAnalysis (player/blend/analysis.ts)
  analyzed_at   INTEGER NOT NULL                -- мс
);
CREATE TABLE blend_ratings (                    -- 👍/👎 прошлому переходу (BLEND.md §8.6)
  id            INTEGER PRIMARY KEY,
  from_ref      TEXT NOT NULL,
  to_ref        TEXT NOT NULL,
  kind          TEXT NOT NULL,                  -- bass | filter | echo | smooth | drop
  score         INTEGER NOT NULL,               -- +1 / −1
  at            INTEGER NOT NULL                -- мс
);
CREATE INDEX blend_ratings_kind ON blend_ratings(kind, at);

-- только клиент (Windows, миграция № 18): хаб синка по Wi‑Fi, пока нет сервера (API.md §10 «Синк по Wi‑Fi»).
-- ПК отвечает привязанным телефонам как сервер; сам меняется с хабом через sync_once. На сервер не едет.
CREATE TABLE hub_rows (                         -- копия строк синка хаба: как server-side sync_rows
  kind          TEXT NOT NULL,                  -- like | playlist | playlist_item | setting | dislike | track_pref | wave_event
  key           TEXT NOT NULL,
  value_json    TEXT,                           -- NULL — удалено
  rev           INTEGER NOT NULL,               -- глобальный rev хаба
  client_ts     INTEGER NOT NULL,               -- для «побеждает позднее» у настроек
  PRIMARY KEY (kind, key)
);
CREATE INDEX hub_rows_rev ON hub_rows(rev);
CREATE TABLE hub_ops (op_id TEXT PRIMARY KEY);  -- виденные op_id: повтор не применяется
CREATE TABLE hub_peers (                        -- когда телефон последний раз синкался («Система → Пульт»)
  device_id     TEXT PRIMARY KEY,
  last_sync     INTEGER NOT NULL                -- секунды
);
-- sync_state.sync_target — с кем синкались: lan | server; сменилась сторона — pushed_rev и pulled_rev с нуля.

-- Быстрые ссылки входа и репорты — схема в BOT.md §6 (auth_links, reports)

-- Статус (SPEC §3.11), только на сервере
CREATE TABLE status_checks (                    -- сырые проверки раз в 5 мин, хранятся 7 дней
  at            INTEGER NOT NULL,               -- мс
  item          TEXT NOT NULL,                  -- api | bot | storage | site | soundcloud | yandex | lrclib | genius | telegram
  ok            INTEGER NOT NULL,
  ms            INTEGER,
  note          TEXT,                           -- текст ошибки
  PRIMARY KEY (item, at)
);
CREATE TABLE status_daily (                     -- свёртка по дням, хранится 90 дней
  day           TEXT NOT NULL,                  -- YYYY-MM-DD (UTC)
  item          TEXT NOT NULL,
  ok_count      INTEGER NOT NULL,
  total         INTEGER NOT NULL,
  PRIMARY KEY (item, day)
);
```

Объёмы: `plays` ≈ 100 строк × 10 пользователей × 365 дней ≈ 365 тыс. строк ≈ 40 МБ в год.
Старше 2 лет можно сворачивать в помесячные агрегаты — пока не нужно.

## releases — проверенные версии (бот, BOT.md §2.6г, 2026-11-17)

| Поле | Тип | Что |
|---|---|---|
| `id` | INTEGER PK | |
| `platform` | TEXT | `windows` / `ios` |
| `version` | TEXT | подпись: `0.1.42`, `ios-build-229` |
| `url` | TEXT | https-ссылка на сборку или страницу релиза |
| `notes` | TEXT | «Что нового» |
| `audience` | TEXT | `all` / `only` / `except` |
| `targets` | TEXT (JSON) | ключи аккаунтов: `u:<username>`, `l:<логин>`, `n:<номер>`, `tg:<id>` |
| `active` | INTEGER | 1 — закреплена, 0 — снята |
| `created_at` | INTEGER | мс |
| `alerted_at` | INTEGER NULL | когда разослан алерт |

## Админка и дашборд (сервер, 2026-11-22)

Таблицы в `server/sonar/db.py`; новые колонки старой базы добавляет `_migrate` (`COLUMNS`). Таблица `sessions` (выше)
на сервере уже создаётся — из неё карточка пользователя берёт устройства, а `POST /events` — пользователя и платформу.

```sql
CREATE TABLE events (                           -- события клиентов (API.md «POST /events»)
  id            INTEGER PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id     TEXT NOT NULL,                  -- из сессии
  platform      TEXT NOT NULL,                  -- windows | ios | android | other — из сессии
  kind          TEXT NOT NULL,                  -- open — открыл плеер, play — начал трек
  service       TEXT,                           -- soundcloud | yandex | youtube | vk | spotify | local — из префикса ref
  ref           TEXT, artist TEXT, title TEXT,  -- только у play
  at            INTEGER NOT NULL,               -- мс, время устройства
  day           TEXT NOT NULL,                  -- YYYY-MM-DD в поясе SONAR_ADMIN_TZ (Europe/Riga) — группировка без вычислений
  UNIQUE (device_id, kind, at)                  -- повтор пачки не удваивает
);
CREATE INDEX events_kind_day ON events(kind, day, user_id);   -- «слушали», топы
CREATE INDEX events_day_user ON events(day, user_id);         -- «открыли», DAU/WAU/MAU
CREATE INDEX events_user_at ON events(user_id, at);           -- карточка, последний заход

CREATE TABLE subscriptions (                    -- Sonar Deep: одна строка — один период
  id            INTEGER PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan          TEXT NOT NULL,                  -- ping | echo | pod | fleet (server/sonar/subs.py, зеркало lib/subscription.ts)
  kind          TEXT NOT NULL,                  -- new — первая у человека, renew — была раньше
  source        TEXT NOT NULL,                  -- manual (админка) | pay (платёжка, потом)
  started_at    INTEGER NOT NULL,               -- продление встаёт в конец текущего периода
  ends_at       INTEGER NOT NULL,
  amount        INTEGER NOT NULL DEFAULT 0,     -- ₽ целыми; 0 — подарок, в выручку не идёт
  currency      TEXT NOT NULL DEFAULT 'RUB',
  note          TEXT,
  created_at    INTEGER NOT NULL
);
CREATE INDEX subscriptions_user ON subscriptions(user_id, ends_at);
CREATE INDEX subscriptions_created ON subscriptions(created_at);
CREATE INDEX subscriptions_ends ON subscriptions(ends_at);

CREATE TABLE admins (                           -- свой вход админки, не аккаунт Sonar
  id            INTEGER PRIMARY KEY,
  login         TEXT UNIQUE NOT NULL COLLATE NOCASE,
  password_hash TEXT NOT NULL,                  -- argon2id; заводской folzy — случайный пароль, один раз в журнал
  must_change   INTEGER NOT NULL DEFAULT 1,     -- 1 — до смены пароля видна только форма смены
  created_at    INTEGER NOT NULL,
  changed_at    INTEGER
);
CREATE TABLE admin_sessions (
  token_hash    TEXT PRIMARY KEY,               -- sha256 cookie sonar_admin
  admin_id      INTEGER NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
  csrf          TEXT NOT NULL,                  -- токен форм этой сессии
  ip TEXT, user_agent TEXT,
  created_at    INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL                -- 12 ч
);
CREATE TABLE admin_audit (                      -- журнал действий админки
  id            INTEGER PRIMARY KEY,
  at            INTEGER NOT NULL,
  admin         TEXT NOT NULL,
  action        TEXT NOT NULL,                  -- login | password | ban | unban | set_login | grant_sub | settings
  target        TEXT,                           -- users.id, если про пользователя
  detail        TEXT                            -- JSON
);
-- Настройки без деплоя — в kv под ключами setting:<ключ> (admin/prefs.py), умолчания — в коде.
```

Объём `events`: ~30 открытий и ~1 000 треков в день на 10 человек ≈ 370 тыс. строк в год ≈ 60 МБ с индексами —
в 2 ГБ Velt помещается; когда станет тесно — сворачивать старше года в дневные агрегаты.


## Комнаты и личные сообщения (черновик, 2026-11-25; сервера нет)

Модель — `docs/ROOMS.md` §1 и `docs/DM.md` §1, ядра клиентов — `lib/rooms/`, `lib/dm/` (ПК), `Core/Rooms/`, `Core/DM/`
(iPhone). Схема — набросок под сервер, миграции нет.

```sql
CREATE TABLE rooms (
  id            TEXT PRIMARY KEY,
  host_id       TEXT NOT NULL REFERENCES users(id),
  leader_id     TEXT NOT NULL REFERENCES users(id),
  pos           INTEGER NOT NULL DEFAULT 0,
  playing       INTEGER NOT NULL DEFAULT 0,
  anchor_ts     INTEGER NOT NULL,               -- часы сервера, мс
  anchor_pos    INTEGER NOT NULL DEFAULT 0,     -- мс
  rev           INTEGER NOT NULL DEFAULT 1,
  closed_at     INTEGER,
  created_at    INTEGER NOT NULL
);
CREATE TABLE room_members (
  room_id       TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id       TEXT NOT NULL REFERENCES users(id),
  dj            INTEGER NOT NULL DEFAULT 0,
  joined_at     INTEGER NOT NULL,
  PRIMARY KEY (room_id, user_id)
);
CREATE TABLE room_queue (
  room_id       TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  idx           INTEGER NOT NULL,
  ref           TEXT NOT NULL,
  added_by      TEXT NOT NULL REFERENCES users(id),
  PRIMARY KEY (room_id, idx)
);
CREATE TABLE dm_threads (
  id            TEXT PRIMARY KEY,
  room_id       TEXT REFERENCES rooms(id) ON DELETE CASCADE,  -- чат комнаты; NULL — личный
  created_at    INTEGER NOT NULL
);
CREATE TABLE dm_members (                       -- двое в личном, участники — в чате комнаты
  thread_id     TEXT NOT NULL REFERENCES dm_threads(id) ON DELETE CASCADE,
  user_id       TEXT NOT NULL REFERENCES users(id),
  read_at       INTEGER NOT NULL DEFAULT 0,     -- до какого sent_at прочитал
  PRIMARY KEY (thread_id, user_id)
);
CREATE TABLE dm_messages (
  id            TEXT PRIMARY KEY,
  thread_id     TEXT NOT NULL REFERENCES dm_threads(id) ON DELETE CASCADE,
  from_id       TEXT NOT NULL REFERENCES users(id),
  text          TEXT NOT NULL DEFAULT '',       -- до 2000 символов; без сквозного шифрования
  reply_to      TEXT,
  sent_at       INTEGER NOT NULL,
  edited_at     INTEGER,
  deleted       INTEGER NOT NULL DEFAULT 0      -- удалённое: text = '', вложения стёрты
);
CREATE INDEX dm_messages_thread ON dm_messages(thread_id, sent_at);
CREATE TABLE dm_attachments (
  message_id    TEXT NOT NULL REFERENCES dm_messages(id) ON DELETE CASCADE,
  idx           INTEGER NOT NULL,               -- до 4 на сообщение
  kind          TEXT NOT NULL,                  -- track | playlist | room
  data          TEXT NOT NULL,                  -- JSON вложения (docs/DM.md §1)
  PRIMARY KEY (message_id, idx)
);
```
