"""SQLite по DB.md (часть, нужная боту) + таблицы BOT.md §6. Один процесс, WAL."""
from __future__ import annotations

import sqlite3
import time
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
"""


def now_ms() -> int:
    return int(time.time() * 1000)


def connect(path: Path | str) -> sqlite3.Connection:
    con = sqlite3.connect(str(path), isolation_level=None, check_same_thread=False)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    if str(path) != ":memory:":
        con.execute("PRAGMA journal_mode = WAL")
    con.executescript(SCHEMA)
    return con


def kv_get(con: sqlite3.Connection, key: str) -> str | None:
    r = con.execute("SELECT value FROM kv WHERE key = ?", (key,)).fetchone()
    return r["value"] if r else None


def kv_set(con: sqlite3.Connection, key: str, value: str) -> None:
    con.execute("INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", (key, value))
