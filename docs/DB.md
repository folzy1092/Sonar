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
  avatar_path   TEXT,
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
  fetched_at    INTEGER NOT NULL
);

CREATE TABLE likes (
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ref           TEXT NOT NULL,
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
  key_hash      TEXT UNIQUE NOT NULL,
  created_at    INTEGER NOT NULL
);

CREATE TABLE sync_rev (id INTEGER PRIMARY KEY CHECK (id = 1), value INTEGER NOT NULL);
```

Объёмы: `plays` ≈ 100 строк × 10 пользователей × 365 дней ≈ 365 тыс. строк ≈ 40 МБ в год.
Старше 2 лет можно сворачивать в помесячные агрегаты — пока не нужно.
