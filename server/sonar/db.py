"""SQLite по DB.md (часть, нужная боту) + таблицы BOT.md §6. Один процесс, WAL."""
from __future__ import annotations

import sqlite3
import time
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  number        INTEGER UNIQUE NOT NULL,
  login         TEXT UNIQUE NOT NULL COLLATE NOCASE,
  username      TEXT UNIQUE NOT NULL COLLATE NOCASE,
  display_name  TEXT NOT NULL,
  password_hash TEXT,
  tg_id         INTEGER UNIQUE,
  tg_username   TEXT,
  is_admin      INTEGER NOT NULL DEFAULT 0,
  banned        INTEGER NOT NULL DEFAULT 0,
  referral_code TEXT UNIQUE,
  referred_by   TEXT REFERENCES users(id),
  created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS service_accounts (
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service       TEXT NOT NULL,
  credentials   BLOB NOT NULL,
  ext_user_id   TEXT, ext_name TEXT, ext_avatar TEXT,
  connected_at  INTEGER NOT NULL,
  PRIMARY KEY (user_id, service)
);
CREATE TABLE IF NOT EXISTS tracks (
  ref           TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  artist        TEXT NOT NULL,
  duration_ms   INTEGER,
  artwork_url   TEXT,
  updated_at    INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS likes (
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ref           TEXT NOT NULL,
  kind          TEXT NOT NULL,
  added_at      INTEGER NOT NULL,
  deleted       INTEGER NOT NULL DEFAULT 0,
  rev           INTEGER NOT NULL,
  PRIMARY KEY (user_id, ref)
);
CREATE INDEX IF NOT EXISTS likes_kind ON likes(user_id, kind, deleted, added_at);
CREATE INDEX IF NOT EXISTS likes_rev ON likes(user_id, rev);
CREATE TABLE IF NOT EXISTS sync_rev (id INTEGER PRIMARY KEY CHECK (id = 1), value INTEGER NOT NULL);
INSERT OR IGNORE INTO sync_rev (id, value) VALUES (1, 0);
CREATE TABLE IF NOT EXISTS plays (
  id            INTEGER PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ref           TEXT NOT NULL,
  artist        TEXT NOT NULL,
  context       TEXT,
  played_at     INTEGER NOT NULL,
  listened_ms   INTEGER NOT NULL,
  scrobbled     INTEGER NOT NULL DEFAULT 0,
  UNIQUE (user_id, ref, played_at)
);
CREATE INDEX IF NOT EXISTS plays_user_time ON plays(user_id, played_at);
CREATE TABLE IF NOT EXISTS player_state (
  user_id       TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  is_playing    INTEGER NOT NULL DEFAULT 0,
  heartbeat_at  INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS lastfm (
  user_id       TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  session_key   BLOB NOT NULL,
  name          TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS api_keys (
  user_id       TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  key_hash      TEXT UNIQUE NOT NULL,
  key_enc       TEXT NOT NULL,
  created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS auth_links (
  code_hash     TEXT PRIMARY KEY,
  for_kind      TEXT NOT NULL,
  for_json      TEXT NOT NULL,
  user_id       TEXT REFERENCES users(id),
  status        TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS tickets (
  id            TEXT PRIMARY KEY,
  user_id       TEXT REFERENCES users(id),
  tg_id         INTEGER NOT NULL,
  kind          TEXT NOT NULL,
  platform      TEXT NOT NULL,
  topic_id      INTEGER,
  status        TEXT NOT NULL,
  app_version   TEXT, os TEXT,
  created_at    INTEGER NOT NULL,
  closed_at     INTEGER
);
CREATE TABLE IF NOT EXISTS support_messages (
  id            INTEGER PRIMARY KEY,
  ticket_id     TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  author        TEXT NOT NULL,
  text          TEXT,
  file_id       TEXT, file_kind TEXT,
  created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS support_blocks (tg_id INTEGER PRIMARY KEY, reason TEXT, until INTEGER);
CREATE TABLE IF NOT EXISTS status_checks (
  ts            INTEGER NOT NULL,
  item          TEXT NOT NULL,
  state         TEXT NOT NULL,
  ms            INTEGER
);
CREATE INDEX IF NOT EXISTS status_checks_item ON status_checks(item, ts);
CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);
-- Устройства (DB.md «sessions»): одна строка = одно устройство; сессия клиента — Bearer в API.
CREATE TABLE IF NOT EXISTS sessions (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash    TEXT UNIQUE NOT NULL,
  device_id     TEXT NOT NULL,
  device_name   TEXT NOT NULL,
  platform      TEXT NOT NULL,
  os            TEXT,
  app_version   TEXT,
  build         INTEGER,
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL,
  UNIQUE (user_id, device_id)
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id, last_seen_at);
-- События клиентов для дашборда (API.md «POST /events», DB.md «events»): open — открыл плеер, play — включил трек.
CREATE TABLE IF NOT EXISTS events (
  id            INTEGER PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id     TEXT NOT NULL,
  platform      TEXT NOT NULL,
  kind          TEXT NOT NULL,
  service       TEXT,
  ref           TEXT,
  artist        TEXT,
  title         TEXT,
  at            INTEGER NOT NULL,
  day           TEXT NOT NULL,
  UNIQUE (device_id, kind, at)
);
CREATE INDEX IF NOT EXISTS events_kind_day ON events(kind, day, user_id);
CREATE INDEX IF NOT EXISTS events_day_user ON events(day, user_id);
CREATE INDEX IF NOT EXISTS events_user_at ON events(user_id, at);
-- Подписка Sonar Deep: одна строка = один оплаченный (или выданный) период.
CREATE TABLE IF NOT EXISTS subscriptions (
  id            INTEGER PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan          TEXT NOT NULL,
  kind          TEXT NOT NULL,
  source        TEXT NOT NULL,
  started_at    INTEGER NOT NULL,
  ends_at       INTEGER NOT NULL,
  amount        INTEGER NOT NULL DEFAULT 0,
  currency      TEXT NOT NULL DEFAULT 'RUB',
  note          TEXT,
  created_at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS subscriptions_user ON subscriptions(user_id, ends_at);
CREATE INDEX IF NOT EXISTS subscriptions_created ON subscriptions(created_at);
CREATE INDEX IF NOT EXISTS subscriptions_ends ON subscriptions(ends_at);
-- Админка (ADMIN.md): свой вход, отдельно от аккаунтов Sonar.
CREATE TABLE IF NOT EXISTS admins (
  id            INTEGER PRIMARY KEY,
  login         TEXT UNIQUE NOT NULL COLLATE NOCASE,
  password_hash TEXT NOT NULL,
  must_change   INTEGER NOT NULL DEFAULT 1,
  created_at    INTEGER NOT NULL,
  changed_at    INTEGER
);
CREATE TABLE IF NOT EXISTS admin_sessions (
  token_hash    TEXT PRIMARY KEY,
  admin_id      INTEGER NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
  csrf          TEXT NOT NULL,
  ip            TEXT,
  user_agent    TEXT,
  created_at    INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS admin_audit (
  id            INTEGER PRIMARY KEY,
  at            INTEGER NOT NULL,
  admin         TEXT NOT NULL,
  action        TEXT NOT NULL,
  target        TEXT,
  detail        TEXT
);
CREATE INDEX IF NOT EXISTS admin_audit_target ON admin_audit(target, at);
"""


def now_ms() -> int:
    return int(time.time() * 1000)


@contextmanager
def tx(con: sqlite3.Connection) -> Iterator[sqlite3.Connection]:
    """Явная транзакция: база открыта с isolation_level=None, а при нём `with con:` ничего не начинает.

    BEGIN IMMEDIATE сразу берёт запись — шаги действия (бан + выход + журнал) либо все, либо ни одного.
    Вложенный вызов входит во внешнюю транзакцию.
    """
    if con.in_transaction:
        yield con
        return
    con.execute("BEGIN IMMEDIATE")
    try:
        yield con
    except BaseException:
        con.execute("ROLLBACK")
        raise
    con.execute("COMMIT")


def connect(path: Path | str) -> sqlite3.Connection:
    con = sqlite3.connect(str(path), isolation_level=None, check_same_thread=False)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    if str(path) != ":memory:":
        con.execute("PRAGMA journal_mode = WAL")
    con.executescript(SCHEMA)
    _migrate(con)
    return con


# Колонки, добавленные после первого запуска: CREATE TABLE IF NOT EXISTS их в старую базу не добавит.
COLUMNS = [
    ("users", "ban_reason", "TEXT"),
    ("users", "banned_at", "INTEGER"),
    # метаданные трека для лайков из /dotify и синка (DB.md `tracks`)
    ("tracks", "artists_json", "TEXT"),
    ("tracks", "url", "TEXT"),
]


def _migrate(con: sqlite3.Connection) -> None:
    for table, col, decl in COLUMNS:
        have = {r["name"] for r in con.execute(f"PRAGMA table_info({table})")}
        if col not in have:
            con.execute(f"ALTER TABLE {table} ADD COLUMN {col} {decl}")


def kv_get(con: sqlite3.Connection, key: str) -> str | None:
    r = con.execute("SELECT value FROM kv WHERE key = ?", (key,)).fetchone()
    return r["value"] if r else None


def kv_set(con: sqlite3.Connection, key: str, value: str) -> None:
    con.execute("INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", (key, value))
