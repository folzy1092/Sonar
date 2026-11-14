//! Локальная база `%APPDATA%/com.folzy.sonar/sonar.db` — те же таблицы и поля, что в docs/DB.md
//! (кроме чисто серверных: сессии, Telegram, ключи API), чтобы потом перенести на сервер без
//! переделок (SPEC §9.3). Пользователь в автономном режиме один — `u_local`.

use crate::providers::Track;
use anyhow::Result;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::Path;

pub const LOCAL_USER: &str = "u_local";

/// Миграции по порядку; номер = `PRAGMA user_version`.
const MIGRATIONS: &[&str] = &[r#"
CREATE TABLE users (
  id TEXT PRIMARY KEY, number INTEGER UNIQUE NOT NULL, login TEXT UNIQUE NOT NULL COLLATE NOCASE,
  username TEXT UNIQUE NOT NULL COLLATE NOCASE, display_name TEXT NOT NULL, avatar_path TEXT,
  bg_path TEXT, bg_kind TEXT, password_hash TEXT, tg_id INTEGER UNIQUE, tg_username TEXT,
  is_admin INTEGER NOT NULL DEFAULT 0, banned INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL
);
CREATE TABLE tracks (
  ref TEXT PRIMARY KEY, title TEXT NOT NULL, artist TEXT NOT NULL, artists_json TEXT, album_json TEXT,
  duration_ms INTEGER NOT NULL, cover_url TEXT, url TEXT, fetched_at INTEGER NOT NULL
);
CREATE TABLE likes (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, ref TEXT NOT NULL, kind TEXT NOT NULL,
  added_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, rev INTEGER NOT NULL,
  PRIMARY KEY (user_id, ref)
);
CREATE TABLE playlists (
  id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, name TEXT NOT NULL,
  cover_path TEXT, hidden INTEGER NOT NULL DEFAULT 0, source_ref TEXT, created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, rev INTEGER NOT NULL
);
CREATE TABLE playlist_items (
  id TEXT PRIMARY KEY, playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  ref TEXT NOT NULL, position REAL NOT NULL, added_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0, rev INTEGER NOT NULL
);
CREATE INDEX playlist_items_pl ON playlist_items(playlist_id, position);
CREATE TABLE settings (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, key TEXT NOT NULL,
  value_json TEXT NOT NULL, client_ts INTEGER NOT NULL, rev INTEGER NOT NULL, PRIMARY KEY (user_id, key)
);
CREATE TABLE player_state (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE, device_id TEXT, ref TEXT, context TEXT,
  is_playing INTEGER NOT NULL DEFAULT 0, position_ms INTEGER NOT NULL DEFAULT 0, queue_json TEXT,
  queue_index INTEGER, shuffle INTEGER NOT NULL DEFAULT 0, repeat TEXT NOT NULL DEFAULT 'off',
  updated_at INTEGER NOT NULL, rev INTEGER NOT NULL
);
CREATE TABLE plays (
  id INTEGER PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, ref TEXT NOT NULL,
  artist TEXT NOT NULL, context TEXT, played_at INTEGER NOT NULL, listened_ms INTEGER NOT NULL,
  scrobbled INTEGER NOT NULL DEFAULT 0, UNIQUE (user_id, ref, played_at)
);
CREATE INDEX plays_user_time ON plays(user_id, played_at);
CREATE TABLE track_prefs (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, ref TEXT NOT NULL, speed REAL,
  lyrics_offset_ms INTEGER, deleted INTEGER NOT NULL DEFAULT 0, rev INTEGER NOT NULL,
  PRIMARY KEY (user_id, ref)
);
CREATE TABLE lyrics_cache (ref TEXT PRIMARY KEY, json TEXT, source TEXT, fetched_at INTEGER NOT NULL);
CREATE TABLE sync_rev (id INTEGER PRIMARY KEY CHECK (id = 1), value INTEGER NOT NULL);
INSERT INTO sync_rev (id, value) VALUES (1, 0);
INSERT INTO users (id, number, login, username, display_name, created_at)
  VALUES ('u_local', 0, 'local', 'local', 'Я', CAST(strftime('%s','now') AS INTEGER) * 1000);
"#];

pub fn now_ms() -> i64 {
  std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

/// Состояние плеера — `PlayerState` из docs/API.md §5.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PlayerState {
  pub device_id: Option<String>,
  #[serde(rename = "ref")]
  pub ref_: Option<String>,
  pub context: Option<String>,
  pub is_playing: bool,
  pub position_ms: i64,
  pub queue: Vec<String>,
  pub queue_index: Option<i64>,
  pub shuffle: bool,
  pub repeat: String,
  pub client_ts: i64,
}

/// Одно засчитанное прослушивание (`POST /plays` в API.md §5).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Play {
  #[serde(rename = "ref")]
  pub ref_: String,
  pub artist: String,
  pub context: Option<String>,
  pub played_at: i64,
  pub listened_ms: i64,
}

pub struct Store {
  db: Connection,
}

impl Store {
  pub fn open(path: &Path) -> Result<Self> {
    Self::init(Connection::open(path)?)
  }

  #[cfg(test)]
  pub fn memory() -> Result<Self> {
    Self::init(Connection::open_in_memory()?)
  }

  fn init(db: Connection) -> Result<Self> {
    db.execute_batch("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")?;
    let version: i64 = db.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    for (i, sql) in MIGRATIONS.iter().enumerate().skip(version as usize) {
      db.execute_batch(&format!("BEGIN; {sql} PRAGMA user_version = {}; COMMIT;", i + 1))?;
    }
    Ok(Self { db })
  }

  /// Следующее значение глобального счётчика синхронизации (`sync_rev`).
  fn next_rev(&self) -> Result<i64> {
    Ok(self.db.query_row("UPDATE sync_rev SET value = value + 1 WHERE id = 1 RETURNING value", [], |r| r.get(0))?)
  }

  pub fn upsert_tracks(&mut self, tracks: &[Track]) -> Result<()> {
    let tx = self.db.transaction()?;
    {
      let mut st = tx.prepare(
        "INSERT INTO tracks (ref, title, artist, artists_json, album_json, duration_ms, cover_url, url, fetched_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
         ON CONFLICT(ref) DO UPDATE SET title = ?2, artist = ?3, artists_json = ?4, album_json = ?5,
           duration_ms = ?6, cover_url = ?7, url = ?8, fetched_at = ?9",
      )?;
      let now = now_ms();
      for t in tracks {
        st.execute(params![
          t.ref_,
          t.title,
          t.artist,
          serde_json::to_string(&t.artists)?,
          t.album.as_ref().map(serde_json::to_string).transpose()?,
          t.duration_ms as i64,
          t.cover_url,
          t.url,
          now
        ])?;
      }
    }
    tx.commit()?;
    Ok(())
  }

  /// Треки из кэша в том же порядке, что `refs`; которых нет — пропускаются.
  pub fn tracks(&self, refs: &[String]) -> Result<Vec<Track>> {
    let mut st = self.db.prepare(
      "SELECT ref, title, artist, artists_json, album_json, duration_ms, cover_url, url FROM tracks WHERE ref = ?1",
    )?;
    let mut out = Vec::with_capacity(refs.len());
    for r in refs {
      let row = st
        .query_row([r], |row| {
          Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, Option<String>>(3)?,
            row.get::<_, Option<String>>(4)?,
            row.get::<_, i64>(5)?,
            row.get::<_, Option<String>>(6)?,
            row.get::<_, Option<String>>(7)?,
          ))
        })
        .optional()?;
      if let Some((ref_, title, artist, artists, album, dur, cover_url, url)) = row {
        out.push(Track {
          ref_,
          title,
          artist,
          artists: artists.and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default(),
          album: album.and_then(|s| serde_json::from_str(&s).ok()),
          duration_ms: dur.max(0) as u64,
          cover_url,
          url,
          explicit: false,
          available: true,
        });
      }
    }
    Ok(out)
  }

  pub fn save_player_state(&self, s: &PlayerState) -> Result<()> {
    let rev = self.next_rev()?;
    self.db.execute(
      "INSERT INTO player_state (user_id, device_id, ref, context, is_playing, position_ms, queue_json,
         queue_index, shuffle, repeat, updated_at, rev)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
       ON CONFLICT(user_id) DO UPDATE SET device_id = ?2, ref = ?3, context = ?4, is_playing = ?5,
         position_ms = ?6, queue_json = ?7, queue_index = ?8, shuffle = ?9, repeat = ?10,
         updated_at = ?11, rev = ?12",
      params![
        LOCAL_USER,
        s.device_id,
        s.ref_,
        s.context,
        s.is_playing,
        s.position_ms,
        serde_json::to_string(&s.queue)?,
        s.queue_index,
        s.shuffle,
        s.repeat,
        now_ms(),
        rev
      ],
    )?;
    Ok(())
  }

  pub fn player_state(&self) -> Result<Option<PlayerState>> {
    Ok(self
      .db
      .query_row(
        "SELECT device_id, ref, context, is_playing, position_ms, queue_json, queue_index, shuffle, repeat,
           updated_at FROM player_state WHERE user_id = ?1",
        [LOCAL_USER],
        |r| {
          Ok(PlayerState {
            device_id: r.get(0)?,
            ref_: r.get(1)?,
            context: r.get(2)?,
            is_playing: r.get(3)?,
            position_ms: r.get(4)?,
            queue: r.get::<_, Option<String>>(5)?.and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default(),
            queue_index: r.get(6)?,
            shuffle: r.get(7)?,
            repeat: r.get(8)?,
            client_ts: r.get(9)?,
          })
        },
      )
      .optional()?)
  }

  /// Повторная запись того же прослушивания (ref + played_at) не дублирует строку.
  pub fn add_play(&self, p: &Play) -> Result<()> {
    self.db.execute(
      "INSERT OR IGNORE INTO plays (user_id, ref, artist, context, played_at, listened_ms)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
      params![LOCAL_USER, p.ref_, p.artist, p.context, p.played_at, p.listened_ms],
    )?;
    Ok(())
  }

  #[cfg(test)]
  pub fn plays_count(&self) -> Result<i64> {
    Ok(self.db.query_row("SELECT COUNT(*) FROM plays WHERE user_id = ?1", [LOCAL_USER], |r| r.get(0))?)
  }

  pub fn setting(&self, key: &str) -> Result<Option<serde_json::Value>> {
    let raw: Option<String> = self
      .db
      .query_row("SELECT value_json FROM settings WHERE user_id = ?1 AND key = ?2", [LOCAL_USER, key], |r| r.get(0))
      .optional()?;
    Ok(raw.and_then(|s| serde_json::from_str(&s).ok()))
  }

  pub fn set_setting(&self, key: &str, value: &serde_json::Value) -> Result<()> {
    let rev = self.next_rev()?;
    self.db.execute(
      "INSERT INTO settings (user_id, key, value_json, client_ts, rev) VALUES (?1, ?2, ?3, ?4, ?5)
       ON CONFLICT(user_id, key) DO UPDATE SET value_json = ?3, client_ts = ?4, rev = ?5",
      params![LOCAL_USER, key, value.to_string(), now_ms(), rev],
    )?;
    Ok(())
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::providers::ArtistRef;

  fn track(r: &str) -> Track {
    Track {
      ref_: r.into(),
      title: "t".into(),
      artist: "a".into(),
      artists: vec![ArtistRef { ref_: "sca:1".into(), name: "a".into(), avatar_url: None }],
      album: None,
      duration_ms: 1000,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
    }
  }

  #[test]
  fn tracks_roundtrip_keeps_order() {
    let mut s = Store::memory().unwrap();
    s.upsert_tracks(&[track("sc:1"), track("ym:2")]).unwrap();
    let got = s.tracks(&["ym:2".into(), "nope".into(), "sc:1".into()]).unwrap();
    assert_eq!(got.iter().map(|t| t.ref_.as_str()).collect::<Vec<_>>(), ["ym:2", "sc:1"]);
    assert_eq!(got[1].artists[0].name, "a");
  }

  #[test]
  fn player_state_roundtrip() {
    let s = Store::memory().unwrap();
    assert!(s.player_state().unwrap().is_none());
    let st = PlayerState {
      device_id: None,
      ref_: Some("sc:1".into()),
      context: Some("search".into()),
      is_playing: true,
      position_ms: 41000,
      queue: vec!["sc:1".into(), "ym:2".into()],
      queue_index: Some(0),
      shuffle: false,
      repeat: "all".into(),
      client_ts: 0,
    };
    s.save_player_state(&st).unwrap();
    s.save_player_state(&st).unwrap();
    let got = s.player_state().unwrap().unwrap();
    assert_eq!(got.queue, st.queue);
    assert_eq!(got.repeat, "all");
    assert!(got.is_playing);
  }

  #[test]
  fn plays_are_not_duplicated() {
    let s = Store::memory().unwrap();
    let p = Play { ref_: "sc:1".into(), artist: "a".into(), context: None, played_at: 5, listened_ms: 31000 };
    s.add_play(&p).unwrap();
    s.add_play(&p).unwrap();
    assert_eq!(s.plays_count().unwrap(), 1);
  }

  #[test]
  fn settings_roundtrip() {
    let s = Store::memory().unwrap();
    s.set_setting("player.volume", &serde_json::json!(0.5)).unwrap();
    s.set_setting("player.volume", &serde_json::json!(0.7)).unwrap();
    assert_eq!(s.setting("player.volume").unwrap(), Some(serde_json::json!(0.7)));
  }
}
