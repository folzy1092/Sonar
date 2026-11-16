# Sonar — схема базы (SQLite)

Файл `server/data/sonar.db`, режим WAL. Id — ULID-строки с префиксом (`u_`, `pl_`, `d_`…).
Время — `INTEGER` миллисекунды Unix. `rev` — значение глобального счётчика `sync_rev`
на момент изменения (для `/sync/pull`).

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
  created_at    INTEGER NOT NULL
);

CREATE TABLE sessions (
  id            TEXT PRIMARY KEY,               -- d_...
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash    TEXT UNIQUE NOT NULL,           -- sha256(session)
  device_name   TEXT NOT NULL,
  platform      TEXT NOT NULL,                  -- ios | windows
  app_version   TEXT,
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL
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
  service       TEXT NOT NULL,                  -- soundcloud | yandex
  credentials   BLOB NOT NULL,                  -- Fernet(JSON: client_id, oauth_token / token)
  ext_user_id   TEXT,
  ext_name      TEXT,
  ext_avatar    TEXT,
  connected_at  INTEGER NOT NULL,
  PRIMARY KEY (user_id, service)
);

CREATE TABLE tracks (                           -- кэш метаданных
  ref           TEXT PRIMARY KEY,               -- sc:123 | ym:456
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
  ref           TEXT NOT NULL,                  -- sc:/ym: трек, scalb:/ymalb: альбом, sca:/yma: артист
  kind          TEXT NOT NULL,                  -- track | album | artist (дублирует префикс для индекса)
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
  source_ref    TEXT,                           -- scpl:… / ympl:… если перенесён
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
  deleted       INTEGER NOT NULL DEFAULT 0,
  rev           INTEGER NOT NULL
);
CREATE INDEX playlist_items_pl ON playlist_items(playlist_id, position);

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

CREATE TABLE lastfm (
  user_id       TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  session_key   BLOB NOT NULL,                  -- Fernet
  name          TEXT NOT NULL,
  scrobble      INTEGER NOT NULL DEFAULT 1,
  now_playing   INTEGER NOT NULL DEFAULT 1
);

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
  deleted       INTEGER NOT NULL DEFAULT 0,
  rev           INTEGER NOT NULL,
  PRIMARY KEY (user_id, ref)
);

CREATE TABLE catalog (                          -- кэш альбомов и исполнителей (как tracks)
  ref           TEXT PRIMARY KEY,               -- scalb:/ymalb: | sca:/yma:
  kind          TEXT NOT NULL,                  -- album | artist
  json          TEXT NOT NULL,                  -- Album / Artist (API.md §3)
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

CREATE TABLE skips (                            -- ручной пропуск в волне с оценкой < 0 (WAVE.md 1.3) — минус артисту и треку
  id            INTEGER PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ref           TEXT NOT NULL,
  artist        TEXT NOT NULL,
  played_ms     INTEGER NOT NULL,
  at            INTEGER NOT NULL
);
CREATE INDEX skips_user_time ON skips(user_id, at);

CREATE TABLE wave_events (                      -- журнал волны (WAVE.md, этап 6). Сейчас локально; в синк аккаунта войдёт (WAVE.md §3а: id → текстовый, +device_id, +rev, миграция № 8);
  id            INTEGER PRIMARY KEY,            -- строки старше 180 дней удаляются при запуске
  user_id       TEXT NOT NULL,
  session_id    TEXT NOT NULL,                  -- сессия волны (создаёт клиент)
  ref           TEXT NOT NULL,
  artist        TEXT NOT NULL,                  -- главный артист, нижний регистр
  mode          TEXT NOT NULL,                  -- own | hard | calm | sad | fun | new
  source        TEXT NOT NULL,                  -- similar | hop2 | liked | seed
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

-- Быстрые ссылки входа и репорты — схема в BOT.md §6 (auth_links, reports)

-- Статус (SPEC §3.11), только на сервере
CREATE TABLE status_checks (                    -- сырые проверки раз в 5 мин, хранятся 7 дней
  at            INTEGER NOT NULL,               -- мс
  item          TEXT NOT NULL,                  -- api | bot | storage | site | soundcloud | yandex | lrclib | genius | lastfm | telegram
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
