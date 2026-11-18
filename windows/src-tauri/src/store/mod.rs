//! Локальная база `%APPDATA%/com.folzy.sonar/sonar.db` — те же таблицы и поля, что в docs/DB.md
//! (кроме чисто серверных: сессии, Telegram, ключи API), чтобы потом перенести на сервер без
//! переделок (SPEC §9.3). Пользователь в автономном режиме один — `u_local`.

use crate::providers::Track;
use anyhow::Result;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::Path;

mod local_files;
mod search;
mod smart;
mod smart_rules;
mod stats;
mod sync;
mod system;
mod wave;
mod wave_events;
pub use local_files::LocalFile;
pub use stats::Stats;
pub use sync::{Change, Op, PlayUpload};
pub use search::SearchEntry;
pub use smart::{SmartPlaylist, SmartPreview};
pub use smart_rules::Rules as SmartRules;
pub use wave::Taste;
pub use wave_events::{ServedEvent, WaveStats};

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
"#, r#"
CREATE TABLE catalog (ref TEXT PRIMARY KEY, kind TEXT NOT NULL, json TEXT NOT NULL, fetched_at INTEGER NOT NULL);
CREATE INDEX likes_kind ON likes(user_id, kind, deleted, added_at);
"#, r#"
ALTER TABLE track_prefs ADD COLUMN eq_json TEXT;
"#, r#"
ALTER TABLE lyrics_cache ADD COLUMN used_at INTEGER;
UPDATE lyrics_cache SET used_at = fetched_at;
"#, r#"
CREATE TABLE dislikes (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, ref TEXT NOT NULL, artist TEXT NOT NULL,
  added_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, rev INTEGER NOT NULL, PRIMARY KEY (user_id, ref)
);
CREATE TABLE skips (
  id INTEGER PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, ref TEXT NOT NULL,
  artist TEXT NOT NULL, played_ms INTEGER NOT NULL, at INTEGER NOT NULL
);
CREATE INDEX skips_user_time ON skips(user_id, at);
"#, r#"
ALTER TABLE tracks ADD COLUMN tags TEXT;
"#, r#"
CREATE TABLE wave_events (
  id INTEGER PRIMARY KEY, user_id TEXT NOT NULL, session_id TEXT NOT NULL, ref TEXT NOT NULL,
  artist TEXT NOT NULL, mode TEXT NOT NULL, source TEXT NOT NULL, seed_ref TEXT, features_json TEXT,
  served_at INTEGER NOT NULL, reward REAL, listened_ms INTEGER, ended_at INTEGER
);
CREATE INDEX wave_events_time ON wave_events(user_id, served_at);
CREATE INDEX wave_events_ref ON wave_events(session_id, ref);
"#, r#"
CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT NOT NULL);
UPDATE sync_rev SET value = value + 1 WHERE id = 1;
CREATE TABLE wave_events_v8 (
  id TEXT PRIMARY KEY NOT NULL DEFAULT ('we_' || lower(hex(randomblob(12)))),
  user_id TEXT NOT NULL, device_id TEXT NOT NULL DEFAULT '', session_id TEXT NOT NULL, ref TEXT NOT NULL,
  artist TEXT NOT NULL, mode TEXT NOT NULL, source TEXT NOT NULL, seed_ref TEXT, features_json TEXT,
  served_at INTEGER NOT NULL, reward REAL, listened_ms INTEGER, ended_at INTEGER, rev INTEGER NOT NULL DEFAULT 0
);
INSERT INTO wave_events_v8 (id, user_id, session_id, ref, artist, mode, source, seed_ref, features_json, served_at,
  reward, listened_ms, ended_at, rev)
  SELECT 'we_' || id || '_' || lower(hex(randomblob(6))), user_id, session_id, ref, artist, mode, source, seed_ref,
    features_json, served_at, reward, listened_ms, ended_at, (SELECT value FROM sync_rev WHERE id = 1)
  FROM wave_events ORDER BY id;
DROP TABLE wave_events;
ALTER TABLE wave_events_v8 RENAME TO wave_events;
CREATE INDEX wave_events_time ON wave_events(user_id, served_at);
CREATE INDEX wave_events_ref ON wave_events(session_id, ref);
"#, r#"
CREATE TABLE search_history (
  id INTEGER PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, query TEXT NOT NULL DEFAULT '',
  ref TEXT, title TEXT, subtitle TEXT, cover_url TEXT, at INTEGER NOT NULL
);
CREATE INDEX search_history_time ON search_history(user_id, at);
"#, r#"
CREATE TABLE local_files (
  ref TEXT PRIMARY KEY, path TEXT UNIQUE NOT NULL, mtime INTEGER NOT NULL, size INTEGER NOT NULL,
  title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT, duration_ms INTEGER NOT NULL, cover_path TEXT
);
"#, r#"
CREATE TABLE smart_playlists (
  id TEXT PRIMARY KEY, user_id TEXT NOT NULL, name TEXT NOT NULL, rules_json TEXT NOT NULL,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
  rev INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX smart_playlists_user ON smart_playlists(user_id, deleted);
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

/// Трек в списке (Любимые или плейлист): сам трек + id строки и время добавления.
/// В JSON поля трека лежат на верхнем уровне — интерфейс работает с ним как с обычным `Track`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ListTrack {
  pub item_id: String,
  pub added_at: i64,
  #[serde(flatten)]
  pub track: Track,
}

/// Плейлист Sonar (`Playlist` в docs/API.md §4). `tracks` — только при открытии плейлиста.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Playlist {
  pub id: String,
  pub name: String,
  pub hidden: bool,
  pub source_ref: Option<String>,
  pub created_at: i64,
  pub updated_at: i64,
  pub track_count: i64,
  pub duration_ms: i64,
  /// До 4 обложек первых треков — для коллажа.
  pub covers: Vec<String>,
  pub tracks: Option<Vec<ListTrack>>,
}

/// Вид лайка по префиксу ref (реестр сервисов, только работающие): `sc:`/`ym:` трек,
/// `scalb:`/`ymalb:` альбом, `sca:`/`yma:` артист. Плейлисты и прочее — None.
pub fn like_kind(r: &str) -> Option<&'static str> {
  use crate::providers::registry::{parse_ref, RefKind};
  match parse_ref(r).filter(|(s, _)| s.implemented)?.1 {
    RefKind::Track => Some("track"),
    RefKind::Album => Some("album"),
    RefKind::Artist => Some("artist"),
    RefKind::Playlist => None,
  }
}

/// Id вида `pl_<26 символов>`: время в мс + случайная часть, сортируется по времени (как ULID).
pub fn new_id(prefix: &str) -> String {
  use std::hash::{BuildHasher, Hasher};
  const ABC: &[u8] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";
  let mut h = std::collections::hash_map::RandomState::new().build_hasher();
  h.write_u128(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0));
  let rnd = (h.finish() as u128) << 16;
  let v = ((now_ms() as u128) << 80) | (rnd & ((1u128 << 80) - 1));
  let s: String = (0..26).rev().map(|i| ABC[((v >> (i * 5)) & 31) as usize] as char).collect();
  format!("{prefix}_{s}")
}

pub struct Store {
  db: Connection,
  /// Копия настроек рядом с базой (`settings-backup.json`): таблица настроек оказалась пустой —
  /// настройки восстанавливаются из неё (жалоба владельца 2026-11-16: «после обновления слетели»).
  backup: Option<std::path::PathBuf>,
}

impl Store {
  pub fn open(path: &Path) -> Result<Self> {
    let mut store = Self::init(Connection::open(path)?)?;
    store.backup = Some(path.with_file_name("settings-backup.json"));
    match store.restore_settings_if_empty() {
      Ok(n) if n > 0 => log::warn!("настройки были пустыми — восстановлено из копии: {n}"),
      Ok(_) => store.backup_settings(),
      Err(e) => log::warn!("копия настроек не читается: {e}"),
    }
    Ok(store)
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
    let store = Self { db, backup: None };
    // у устройства свой id (журнал волны и синк знают, откуда событие); старые события — с него же
    let device = store.device_id()?;
    store.db.execute("UPDATE wave_events SET device_id = ?1 WHERE device_id = ''", [&device])?;
    // журнал волны хранится полгода
    store.prune_wave_events()?;
    store.prune_similar()?;
    Ok(store)
  }

  /// Следующее значение глобального счётчика синхронизации (`sync_rev`).
  pub(crate) fn next_rev(&self) -> Result<i64> {
    Ok(self.db.query_row("UPDATE sync_rev SET value = value + 1 WHERE id = 1 RETURNING value", [], |r| r.get(0))?)
  }

  pub fn upsert_tracks(&mut self, tracks: &[Track]) -> Result<()> {
    let tx = self.db.transaction()?;
    {
      let mut st = tx.prepare(
        // теги: пустое значение старые не затирает (трек из кэша или очереди приходит без тегов)
        "INSERT INTO tracks (ref, title, artist, artists_json, album_json, duration_ms, cover_url, url, fetched_at, tags)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, NULLIF(?10, ''))
         ON CONFLICT(ref) DO UPDATE SET title = ?2, artist = ?3, artists_json = ?4, album_json = ?5,
           duration_ms = ?6, cover_url = ?7, url = ?8, fetched_at = ?9, tags = COALESCE(NULLIF(?10, ''), tags)",
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
          now,
          t.tags.as_deref().map(str::trim)
        ])?;
      }
    }
    tx.commit()?;
    Ok(())
  }

  /// Треки из кэша в том же порядке, что `refs`; которых нет — пропускаются.
  pub fn tracks(&self, refs: &[String]) -> Result<Vec<Track>> {
    let mut st = self.db.prepare(
      "SELECT ref, title, artist, artists_json, album_json, duration_ms, cover_url, url, tags FROM tracks WHERE ref = ?1",
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
            row.get::<_, Option<String>>(8)?,
          ))
        })
        .optional()?;
      if let Some((ref_, title, artist, artists, album, dur, cover_url, url, tags)) = row {
        // локальный файл: серый, если его нет в индексе или на диске («Файл не найден»)
        let available = !crate::local::is_local_ref(&ref_) || self.local_file(&ref_)?.is_some_and(|f| f.exists());
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
          available,
          plays: None,
          tags,
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
    self.backup_settings();
    Ok(())
  }

  // ——— лайки ———

  /// Поставить или снять лайк (снятый остаётся строкой с `deleted = 1` — для синка).
  pub fn set_like(&self, r: &str, on: bool) -> Result<()> {
    let kind = like_kind(r).ok_or_else(|| anyhow::anyhow!("нельзя лайкнуть {r}"))?;
    let rev = self.next_rev()?;
    if on {
      self.db.execute(
        "INSERT INTO likes (user_id, ref, kind, added_at, deleted, rev) VALUES (?1, ?2, ?3, ?4, 0, ?5)
         ON CONFLICT(user_id, ref) DO UPDATE SET added_at = CASE WHEN deleted = 1 THEN ?4 ELSE added_at END,
           deleted = 0, rev = ?5",
        params![LOCAL_USER, r, kind, now_ms(), rev],
      )?;
    } else {
      self.db.execute(
        "UPDATE likes SET deleted = 1, rev = ?3 WHERE user_id = ?1 AND ref = ?2",
        params![LOCAL_USER, r, rev],
      )?;
    }
    Ok(())
  }

  /// Снять все лайки треков разом («Очистить Любимые»): строки остаются с `deleted = 1` для синка.
  /// Вернёт, сколько треков убрано.
  pub fn clear_track_likes(&self) -> Result<usize> {
    let rev = self.next_rev()?;
    Ok(self.db.execute(
      "UPDATE likes SET deleted = 1, rev = ?2 WHERE user_id = ?1 AND kind = 'track' AND deleted = 0",
      params![LOCAL_USER, rev],
    )?)
  }

  /// Лайкнутое одного вида: (ref, added_at), новые первыми.
  pub fn likes(&self, kind: &str) -> Result<Vec<(String, i64)>> {
    let mut st = self.db.prepare(
      "SELECT ref, added_at FROM likes WHERE user_id = ?1 AND kind = ?2 AND deleted = 0 ORDER BY added_at DESC",
    )?;
    let rows = st.query_map([LOCAL_USER, kind], |r| Ok((r.get(0)?, r.get(1)?)))?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
  }

  /// Любимые треки с данными из кэша `tracks`.
  pub fn favorites(&self) -> Result<Vec<ListTrack>> {
    let likes = self.likes("track")?;
    let refs: Vec<String> = likes.iter().map(|(r, _)| r.clone()).collect();
    let by_ref: std::collections::HashMap<String, Track> =
      self.tracks(&refs)?.into_iter().map(|t| (t.ref_.clone(), t)).collect();
    Ok(likes
      .into_iter()
      .filter_map(|(r, added_at)| by_ref.get(&r).map(|t| ListTrack { item_id: r, added_at, track: t.clone() }))
      .collect())
  }

  // ——— кэш альбомов и исполнителей (для вкладок медиатеки) ———

  pub fn put_catalog(&self, r: &str, kind: &str, json: &serde_json::Value) -> Result<()> {
    self.db.execute(
      "INSERT INTO catalog (ref, kind, json, fetched_at) VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT(ref) DO UPDATE SET json = ?3, fetched_at = ?4",
      params![r, kind, json.to_string(), now_ms()],
    )?;
    Ok(())
  }

  /// Лайкнутые альбомы или исполнители — сохранённый JSON, новые первыми.
  pub fn liked_catalog(&self, kind: &str) -> Result<Vec<serde_json::Value>> {
    let mut st = self.db.prepare(
      "SELECT c.json FROM likes l JOIN catalog c ON c.ref = l.ref
       WHERE l.user_id = ?1 AND l.kind = ?2 AND l.deleted = 0 ORDER BY l.added_at DESC",
    )?;
    let rows = st.query_map([LOCAL_USER, kind], |r| r.get::<_, String>(0))?;
    Ok(rows.filter_map(|r| r.ok().and_then(|s| serde_json::from_str(&s).ok())).collect())
  }

  // ——— плейлисты ———

  pub fn create_playlist(&mut self, name: &str, refs: &[String], source_ref: Option<&str>) -> Result<String> {
    let id = new_id("pl");
    let rev = self.next_rev()?;
    let now = now_ms();
    self.db.execute(
      "INSERT INTO playlists (id, user_id, name, source_ref, created_at, updated_at, rev) VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6)",
      params![id, LOCAL_USER, name.trim(), source_ref, now, rev],
    )?;
    self.add_to_playlist(&id, refs, false)?;
    Ok(id)
  }

  /// Плейлист, перенесённый из сервиса (`scpl:…` / `ympl:…`), если он уже есть.
  pub fn playlist_by_source(&self, source_ref: &str) -> Result<Option<String>> {
    Ok(self
      .db
      .query_row(
        "SELECT id FROM playlists WHERE user_id = ?1 AND source_ref = ?2 AND deleted = 0",
        [LOCAL_USER, source_ref],
        |r| r.get(0),
      )
      .optional()?)
  }

  fn summary(&self, row: &rusqlite::Row) -> rusqlite::Result<Playlist> {
    Ok(Playlist {
      id: row.get(0)?,
      name: row.get(1)?,
      hidden: row.get(2)?,
      source_ref: row.get(3)?,
      created_at: row.get(4)?,
      updated_at: row.get(5)?,
      track_count: 0,
      duration_ms: 0,
      covers: vec![],
      tracks: None,
    })
  }

  fn fill_stats(&self, p: &mut Playlist) -> Result<()> {
    let (count, dur): (i64, i64) = self.db.query_row(
      "SELECT COUNT(*), COALESCE(SUM(t.duration_ms), 0) FROM playlist_items i LEFT JOIN tracks t ON t.ref = i.ref
       WHERE i.playlist_id = ?1 AND i.deleted = 0",
      [&p.id],
      |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    let mut st = self.db.prepare(
      "SELECT t.cover_url FROM playlist_items i JOIN tracks t ON t.ref = i.ref
       WHERE i.playlist_id = ?1 AND i.deleted = 0 AND t.cover_url IS NOT NULL ORDER BY i.position LIMIT 4",
    )?;
    p.covers = st.query_map([&p.id], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?;
    p.track_count = count;
    p.duration_ms = dur;
    Ok(())
  }

  /// Все плейлисты без треков, новые сверху.
  pub fn playlists(&self) -> Result<Vec<Playlist>> {
    let mut st = self.db.prepare(
      "SELECT id, name, hidden, source_ref, created_at, updated_at FROM playlists
       WHERE user_id = ?1 AND deleted = 0 ORDER BY created_at DESC",
    )?;
    let mut list: Vec<Playlist> = st.query_map([LOCAL_USER], |r| self.summary(r))?.collect::<rusqlite::Result<_>>()?;
    for p in &mut list {
      self.fill_stats(p)?;
    }
    Ok(list)
  }

  pub fn playlist(&self, id: &str) -> Result<Option<Playlist>> {
    let p = self
      .db
      .query_row(
        "SELECT id, name, hidden, source_ref, created_at, updated_at FROM playlists
         WHERE user_id = ?1 AND id = ?2 AND deleted = 0",
        [LOCAL_USER, id],
        |r| self.summary(r),
      )
      .optional()?;
    let Some(mut p) = p else { return Ok(None) };
    self.fill_stats(&mut p)?;
    let mut st = self.db.prepare(
      "SELECT id, ref, added_at FROM playlist_items WHERE playlist_id = ?1 AND deleted = 0 ORDER BY position",
    )?;
    let items: Vec<(String, String, i64)> =
      st.query_map([id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?.collect::<rusqlite::Result<_>>()?;
    let refs: Vec<String> = items.iter().map(|i| i.1.clone()).collect();
    let by_ref: std::collections::HashMap<String, Track> =
      self.tracks(&refs)?.into_iter().map(|t| (t.ref_.clone(), t)).collect();
    p.tracks = Some(
      items
        .into_iter()
        .filter_map(|(item_id, r, added_at)| by_ref.get(&r).map(|t| ListTrack { item_id, added_at, track: t.clone() }))
        .collect(),
    );
    Ok(Some(p))
  }

  fn touch(&self, id: &str) -> Result<()> {
    let rev = self.next_rev()?;
    let n = self.db.execute(
      "UPDATE playlists SET updated_at = ?3, rev = ?4 WHERE user_id = ?1 AND id = ?2 AND deleted = 0",
      params![LOCAL_USER, id, now_ms(), rev],
    )?;
    if n == 0 {
      anyhow::bail!("плейлист не найден");
    }
    Ok(())
  }

  pub fn update_playlist(&self, id: &str, name: Option<&str>, hidden: Option<bool>) -> Result<()> {
    self.touch(id)?;
    if let Some(n) = name.map(str::trim).filter(|n| !n.is_empty()) {
      self.db.execute("UPDATE playlists SET name = ?2 WHERE id = ?1", params![id, n])?;
    }
    if let Some(h) = hidden {
      self.db.execute("UPDATE playlists SET hidden = ?2 WHERE id = ?1", params![id, h])?;
    }
    Ok(())
  }

  pub fn delete_playlist(&self, id: &str) -> Result<()> {
    self.touch(id)?;
    self.db.execute("UPDATE playlists SET deleted = 1 WHERE id = ?1", [id])?;
    Ok(())
  }

  /// Добавить треки в начало или в конец (дробные позиции — без перенумерации).
  pub fn add_to_playlist(&mut self, id: &str, refs: &[String], at_start: bool) -> Result<()> {
    self.touch(id)?;
    let rev = self.next_rev()?;
    let tx = self.db.transaction()?;
    {
      let (lo, hi): (Option<f64>, Option<f64>) = tx.query_row(
        "SELECT MIN(position), MAX(position) FROM playlist_items WHERE playlist_id = ?1 AND deleted = 0",
        [id],
        |r| Ok((r.get(0)?, r.get(1)?)),
      )?;
      let n = refs.len() as f64;
      let first = if at_start { lo.unwrap_or(0.0) - n } else { hi.map_or(0.0, |h| h + 1.0) };
      let mut st = tx.prepare(
        "INSERT INTO playlist_items (id, playlist_id, ref, position, added_at, rev) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
      )?;
      let now = now_ms();
      for (i, r) in refs.iter().enumerate() {
        st.execute(params![new_id("pi"), id, r, first + i as f64, now, rev])?;
      }
    }
    tx.commit()?;
    Ok(())
  }

  pub fn remove_from_playlist(&self, id: &str, item_ids: &[String]) -> Result<()> {
    self.touch(id)?;
    let rev = self.next_rev()?;
    for item in item_ids {
      self.db.execute(
        "UPDATE playlist_items SET deleted = 1, rev = ?3 WHERE playlist_id = ?1 AND id = ?2",
        params![id, item, rev],
      )?;
    }
    Ok(())
  }

  /// Полный новый порядок строк.
  pub fn reorder_playlist(&mut self, id: &str, item_ids: &[String]) -> Result<()> {
    self.touch(id)?;
    let rev = self.next_rev()?;
    let tx = self.db.transaction()?;
    for (i, item) in item_ids.iter().enumerate() {
      tx.execute(
        "UPDATE playlist_items SET position = ?3, rev = ?4 WHERE playlist_id = ?1 AND id = ?2",
        params![id, item, i as f64, rev],
      )?;
    }
    tx.commit()?;
    Ok(())
  }

  // ——— тексты: кэш и сдвиг на трек (LYRICS.md §5, §7) ———

  /// Кэш текста: `Some((json, fetched_at))`, json `None` — «не найдено». Попадание продлевает
  /// срок хранения (`used_at`, см. `prune_lyrics`).
  pub fn lyrics_cached(&self, r: &str) -> Result<Option<(Option<String>, i64)>> {
    let hit: Option<(Option<String>, i64)> = self
      .db
      .query_row("SELECT json, fetched_at FROM lyrics_cache WHERE ref = ?1", [r], |row| Ok((row.get(0)?, row.get(1)?)))
      .optional()?;
    if hit.is_some() {
      self.db.execute("UPDATE lyrics_cache SET used_at = ?2 WHERE ref = ?1", params![r, now_ms()])?;
    }
    Ok(hit)
  }

  /// Тексты хранятся на компьютере **неделю** с последнего прослушивания, у треков из Любимых —
  /// **две недели** (решение владельца 2026-11-15). Вызывается при запуске; возвращает, сколько удалено.
  pub fn prune_lyrics(&self, now: i64) -> Result<usize> {
    const DAY: i64 = 86_400_000;
    Ok(self.db.execute(
      "DELETE FROM lyrics_cache WHERE COALESCE(used_at, fetched_at) < ?1
         OR (COALESCE(used_at, fetched_at) < ?2
             AND ref NOT IN (SELECT ref FROM likes WHERE user_id = ?3 AND deleted = 0))",
      params![now - 14 * DAY, now - 7 * DAY, LOCAL_USER],
    )?)
  }

  pub fn put_lyrics(&self, r: &str, json: Option<&str>, source: Option<&str>) -> Result<()> {
    self.db.execute(
      "INSERT INTO lyrics_cache (ref, json, source, fetched_at, used_at) VALUES (?1, ?2, ?3, ?4, ?4)
       ON CONFLICT(ref) DO UPDATE SET json = ?2, source = ?3, fetched_at = ?4, used_at = ?4",
      params![r, json, source, now_ms()],
    )?;
    Ok(())
  }

  pub fn clear_lyrics(&self, r: &str) -> Result<()> {
    self.db.execute("DELETE FROM lyrics_cache WHERE ref = ?1", [r])?;
    Ok(())
  }

  /// Сдвиг текста для трека в мс (0 — нет).
  pub fn lyrics_offset(&self, r: &str) -> Result<i64> {
    let v: Option<Option<i64>> = self
      .db
      .query_row(
        "SELECT lyrics_offset_ms FROM track_prefs WHERE user_id = ?1 AND ref = ?2 AND deleted = 0",
        [LOCAL_USER, r],
        |row| row.get(0),
      )
      .optional()?;
    Ok(v.flatten().unwrap_or(0))
  }

  /// Записать сдвиг; 0 → поле `NULL`, пустая запись помечается удалённой (для синка).
  pub fn set_lyrics_offset(&self, r: &str, ms: i64) -> Result<()> {
    let ms = ms.clamp(-15_000, 15_000);
    let value = (ms != 0).then_some(ms);
    let rev = self.next_rev()?;
    self.db.execute(
      "INSERT INTO track_prefs (user_id, ref, lyrics_offset_ms, deleted, rev) VALUES (?1, ?2, ?3, 0, ?4)
       ON CONFLICT(user_id, ref) DO UPDATE SET lyrics_offset_ms = ?3, deleted = 0, rev = ?4",
      params![LOCAL_USER, r, value, rev],
    )?;
    self.db.execute(
      "UPDATE track_prefs SET deleted = 1 WHERE user_id = ?1 AND ref = ?2 AND speed IS NULL AND lyrics_offset_ms IS NULL AND eq_json IS NULL",
      [LOCAL_USER, r],
    )?;
    Ok(())
  }

  /// Кривая эквалайзера, запомненная для трека («Запомнить»), — 12 значений в дБ.
  pub fn track_eq(&self, r: &str) -> Result<Option<Vec<f64>>> {
    let v: Option<Option<String>> = self
      .db
      .query_row("SELECT eq_json FROM track_prefs WHERE user_id = ?1 AND ref = ?2 AND deleted = 0", [LOCAL_USER, r], |row| row.get(0))
      .optional()?;
    Ok(v.flatten().and_then(|j| serde_json::from_str(&j).ok()))
  }

  pub fn set_track_eq(&self, r: &str, gains: Option<&[f64]>) -> Result<()> {
    let json = gains.map(serde_json::to_string).transpose()?;
    let rev = self.next_rev()?;
    self.db.execute(
      "INSERT INTO track_prefs (user_id, ref, eq_json, deleted, rev) VALUES (?1, ?2, ?3, 0, ?4)
       ON CONFLICT(user_id, ref) DO UPDATE SET eq_json = ?3, deleted = 0, rev = ?4",
      params![LOCAL_USER, r, json, rev],
    )?;
    self.db.execute(
      "UPDATE track_prefs SET deleted = 1 WHERE user_id = ?1 AND ref = ?2 AND speed IS NULL AND lyrics_offset_ms IS NULL AND eq_json IS NULL",
      [LOCAL_USER, r],
    )?;
    Ok(())
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::providers::ArtistRef;

  #[test]
  fn like_kind_unchanged() {
    for (r, want) in [
      ("sc:1", Some("track")),
      ("ym:1", Some("track")),
      ("scalb:1", Some("album")),
      ("ymalb:1", Some("album")),
      ("sca:1", Some("artist")),
      ("yma:1", Some("artist")),
      ("scpl:likes", None),
      ("ympl:42:3", None),
      ("yt:1", Some("track")),
      ("yta:1", Some("artist")),
      ("ytalb:1", Some("album")),
      ("ytpl:likes", None),
      ("vk:1", Some("track")),
      ("sp:1", Some("track")),
      ("local:1", Some("track")),
      ("pl_x", None),
      ("similar:sc:1", None),
      ("sc", None),
      ("", None),
    ] {
      assert_eq!(like_kind(r), want, "{r}");
    }
  }

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
      plays: None,
      tags: None,
    }
  }

  #[test]
  fn tags_saved_and_not_wiped_by_empty() {
    let mut s = Store::memory().unwrap();
    let mut t = track("sc:1");
    t.tags = Some("\"drift phonk\" trap".into());
    s.upsert_tracks(&[t.clone()]).unwrap();
    t.tags = None;
    s.upsert_tracks(&[t.clone()]).unwrap();
    t.tags = Some("  ".into());
    s.upsert_tracks(&[t]).unwrap();
    assert_eq!(s.tracks(&["sc:1".into()]).unwrap()[0].tags.as_deref(), Some("\"drift phonk\" trap"));
  }

  #[test]
  fn migration_from_old_schema_adds_tags() {
    // база со схемой до колонки тегов (5 миграций): трек сохраняется, теги появляются пустыми
    let db = Connection::open_in_memory().unwrap();
    for (i, sql) in MIGRATIONS.iter().take(5).enumerate() {
      db.execute_batch(&format!("BEGIN; {sql} PRAGMA user_version = {}; COMMIT;", i + 1)).unwrap();
    }
    db.execute(
      "INSERT INTO tracks (ref, title, artist, duration_ms, fetched_at) VALUES ('sc:1', 't', 'a', 1000, 0)",
      [],
    )
    .unwrap();
    let mut s = Store::init(db).unwrap();
    let old = s.tracks(&["sc:1".into()]).unwrap();
    assert_eq!(old.len(), 1);
    assert_eq!(old[0].tags, None);
    let mut t = track("sc:1");
    t.tags = Some("lofi".into());
    s.upsert_tracks(&[t]).unwrap();
    assert_eq!(s.tracks(&["sc:1".into()]).unwrap()[0].tags.as_deref(), Some("lofi"));
  }

  #[test]
  fn migration_from_tags_schema_adds_wave_events() {
    // база на схеме с тегами (6 миграций): журнал волны появляется пустым, старые данные целы
    let db = Connection::open_in_memory().unwrap();
    for (i, sql) in MIGRATIONS.iter().take(6).enumerate() {
      db.execute_batch(&format!("BEGIN; {sql} PRAGMA user_version = {}; COMMIT;", i + 1)).unwrap();
    }
    db.execute(
      "INSERT INTO tracks (ref, title, artist, duration_ms, fetched_at, tags) VALUES ('sc:1', 't', 'a', 1000, 0, 'lofi')",
      [],
    )
    .unwrap();
    let mut s = Store::init(db).unwrap();
    assert_eq!(s.tracks(&["sc:1".into()]).unwrap()[0].tags.as_deref(), Some("lofi"));
    let version: i64 = s.db.query_row("PRAGMA user_version", [], |r| r.get(0)).unwrap();
    assert_eq!(version as usize, MIGRATIONS.len());
    assert!(s.wave_stats(30).unwrap().by_mode.is_empty());
    s.log_wave_served(
      "s",
      "own",
      &[ServedEvent { ref_: "sc:1".into(), artist: "a".into(), source: "similar".into(), seed_ref: None, features_json: None }],
    )
    .unwrap();
    assert_eq!(s.wave_stats(30).unwrap().by_mode[0].served, 1);
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
  fn likes_toggle_and_favorites_order() {
    let mut s = Store::memory().unwrap();
    s.upsert_tracks(&[track("sc:1"), track("ym:2")]).unwrap();
    s.set_like("sc:1", true).unwrap();
    std::thread::sleep(std::time::Duration::from_millis(3));
    s.set_like("ym:2", true).unwrap();
    s.set_like("scalb:9", true).unwrap();
    let fav = s.favorites().unwrap();
    assert_eq!(fav.iter().map(|t| t.track.ref_.as_str()).collect::<Vec<_>>(), ["ym:2", "sc:1"]);
    s.set_like("ym:2", false).unwrap();
    assert_eq!(s.favorites().unwrap().len(), 1);
    // «Очистить Любимые» снимает только треки, лайки альбомов и артистов остаются
    s.set_like("scalb:9", true).unwrap();
    assert_eq!(s.clear_track_likes().unwrap(), 1);
    assert!(s.favorites().unwrap().is_empty());
    assert_eq!(s.likes("album").unwrap().len(), 1);
    assert_eq!(s.likes("album").unwrap().len(), 1);
    assert!(s.set_like("pl_x", true).is_err());
  }

  #[test]
  fn liked_albums_come_from_catalog() {
    let s = Store::memory().unwrap();
    s.put_catalog("ymalb:9", "album", &serde_json::json!({"ref": "ymalb:9", "title": "Come Over"})).unwrap();
    s.set_like("ymalb:9", true).unwrap();
    assert_eq!(s.liked_catalog("album").unwrap()[0]["title"], "Come Over");
  }

  #[test]
  fn playlist_lifecycle() {
    let mut s = Store::memory().unwrap();
    s.upsert_tracks(&[track("sc:1"), track("ym:2"), track("sc:3")]).unwrap();
    let id = s.create_playlist(" Микс ", &["sc:1".into(), "ym:2".into()], Some("scpl:5")).unwrap();
    assert!(id.starts_with("pl_") && id.len() == 29);
    assert_eq!(s.playlist_by_source("scpl:5").unwrap().as_deref(), Some(id.as_str()));

    s.add_to_playlist(&id, &["sc:3".into()], true).unwrap();
    let p = s.playlist(&id).unwrap().unwrap();
    let refs = |p: &Playlist| p.tracks.as_ref().unwrap().iter().map(|t| t.track.ref_.clone()).collect::<Vec<_>>();
    assert_eq!(p.name, "Микс");
    assert_eq!(refs(&p), ["sc:3", "sc:1", "ym:2"]);
    assert_eq!((p.track_count, p.duration_ms), (3, 3000));

    let items: Vec<String> = p.tracks.unwrap().iter().map(|t| t.item_id.clone()).collect();
    s.reorder_playlist(&id, &[items[2].clone(), items[1].clone(), items[0].clone()]).unwrap();
    s.remove_from_playlist(&id, &[items[1].clone()]).unwrap();
    assert_eq!(refs(&s.playlist(&id).unwrap().unwrap()), ["ym:2", "sc:3"]);

    s.update_playlist(&id, Some("Новое"), Some(true)).unwrap();
    let list = s.playlists().unwrap();
    assert_eq!((list[0].name.as_str(), list[0].hidden, list[0].track_count), ("Новое", true, 2));
    s.delete_playlist(&id).unwrap();
    assert!(s.playlists().unwrap().is_empty());
    assert!(s.playlist(&id).unwrap().is_none());
  }

  #[test]
  fn ids_are_unique_and_sorted() {
    let a = new_id("pl");
    std::thread::sleep(std::time::Duration::from_millis(2));
    let b = new_id("pl");
    assert!(a < b);
  }

  #[test]
  fn settings_roundtrip() {
    let s = Store::memory().unwrap();
    s.set_setting("player.volume", &serde_json::json!(0.5)).unwrap();
    s.set_setting("player.volume", &serde_json::json!(0.7)).unwrap();
    assert_eq!(s.setting("player.volume").unwrap(), Some(serde_json::json!(0.7)));
  }

  #[test]
  fn lyrics_cache_and_offset() {
    let s = Store::memory().unwrap();
    assert!(s.lyrics_cached("sc:1").unwrap().is_none());
    s.put_lyrics("sc:1", None, None).unwrap();
    assert_eq!(s.lyrics_cached("sc:1").unwrap().unwrap().0, None);
    s.put_lyrics("sc:1", Some("{}"), Some("lrclib")).unwrap();
    assert_eq!(s.lyrics_cached("sc:1").unwrap().unwrap().0.as_deref(), Some("{}"));
    assert_eq!(s.lyrics_offset("sc:1").unwrap(), 0);
    s.set_lyrics_offset("sc:1", 250).unwrap();
    assert_eq!(s.lyrics_offset("sc:1").unwrap(), 250);
    s.set_lyrics_offset("sc:1", 99_999).unwrap();
    assert_eq!(s.lyrics_offset("sc:1").unwrap(), 15_000);
    s.set_lyrics_offset("sc:1", 0).unwrap();
    assert_eq!(s.lyrics_offset("sc:1").unwrap(), 0);
    s.set_track_eq("sc:1", Some(&[1.0, -2.5])).unwrap();
    assert_eq!(s.track_eq("sc:1").unwrap(), Some(vec![1.0, -2.5]));
    s.set_track_eq("sc:1", None).unwrap();
    assert_eq!(s.track_eq("sc:1").unwrap(), None);
  }

  #[test]
  fn lyrics_kept_week_or_two_for_likes() {
    let s = Store::memory().unwrap();
    const DAY: i64 = 86_400_000;
    let now = now_ms();
    s.put_lyrics("sc:old", Some("{}"), Some("lrclib")).unwrap();
    s.put_lyrics("sc:liked", Some("{}"), Some("lrclib")).unwrap();
    s.put_lyrics("sc:fresh", Some("{}"), Some("lrclib")).unwrap();
    s.set_like("sc:liked", true).unwrap();
    // через 8 дней: обычный удалён, лайкнутый живёт
    assert_eq!(s.prune_lyrics(now + 8 * DAY).unwrap(), 2);
    assert!(s.lyrics_cached("sc:liked").unwrap().is_some());
    // прослушивание продлевает срок: через 15 дней от записи, но 1 день от прослушивания — живёт
    s.db.execute("UPDATE lyrics_cache SET used_at = ?1 WHERE ref = 'sc:liked'", [now + 14 * DAY]).unwrap();
    assert_eq!(s.prune_lyrics(now + 15 * DAY).unwrap(), 0);
    assert_eq!(s.prune_lyrics(now + 29 * DAY).unwrap(), 1);
  }

  #[test]
  fn migration_8_turns_wave_events_into_sync_rows() {
    // база на схеме 7: журнал с числовыми id — после миграции текстовые id, свой device_id, rev
    let db = Connection::open_in_memory().unwrap();
    for (i, sql) in MIGRATIONS.iter().take(7).enumerate() {
      db.execute_batch(&format!("BEGIN; {sql} PRAGMA user_version = {}; COMMIT;", i + 1)).unwrap();
    }
    db.execute(
      "INSERT INTO wave_events (user_id, session_id, ref, artist, mode, source, served_at, reward, ended_at)
       VALUES ('u_local', 's', 'sc:1', 'a', 'own', 'similar', ?1, 1.0, ?1)",
      [now_ms()],
    )
    .unwrap();
    let s = Store::init(db).unwrap();
    let (id, device): (String, String) = s.db.query_row("SELECT id, device_id FROM wave_events", [], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
    assert!(id.starts_with("we_1_"), "{id}");
    assert_eq!(device, s.device_id().unwrap());
    // старое событие ждёт отправки
    let plan = s.pending_ops(10).unwrap();
    assert!(plan.ops.iter().any(|o| o.kind == "wave_event" && o.key == id));
    assert!(plan.ops.iter().all(|o| o.value.as_ref().is_none_or(|v| v.get("features_json").is_none())));
  }
}
