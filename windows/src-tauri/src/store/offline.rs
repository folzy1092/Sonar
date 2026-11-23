//! `offline_tracks` (миграция № 16, `docs/OFFLINE.md` §7.1): что из сервисов лежит на диске и играет без сети.
//! Только на этом устройстве, в синк не идёт. Пишет его кэш треков (`track_cache::Change` → `offline_index.rs`),
//! при запуске индекс сверяется с папкой кэша. Снимок `Track` хранится в строке: `tracks` могут обновить,
//! а офлайн-список обязан показать название.

use super::{now_ms, Store};
use crate::providers::Track;
use anyhow::Result;
use rusqlite::params;
use std::collections::{HashMap, HashSet};

/// Файл в кэше, который лёг сам (прослушан или подкачан). Скачанное руками (`pinned`) — этап 2.
pub const KIND_CACHE: &str = "cache";

impl Store {
  /// Файл лёг в кэш: строка со снимком трека (если трек уже есть в `tracks`).
  pub fn offline_put(&self, track_ref: &str, file: &str, mime: &str, bytes: u64, kind: &str) -> Result<()> {
    let meta = self.tracks(&[track_ref.to_owned()])?.into_iter().next();
    let meta_json = serde_json::to_string(&meta)?;
    self.db.execute(
      "INSERT INTO offline_tracks (ref, file, mime, bytes, kind, added_at, meta_json) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
       ON CONFLICT(ref) DO UPDATE SET file = ?2, mime = ?3, bytes = ?4, kind = ?5, meta_json = ?7",
      params![track_ref, file, mime, bytes as i64, kind, now_ms(), meta_json],
    )?;
    Ok(())
  }

  /// Файл ушёл из кэша (вытеснен).
  pub fn offline_drop_file(&self, file: &str) -> Result<()> {
    self.db.execute("DELETE FROM offline_tracks WHERE file = ?1", [file])?;
    Ok(())
  }

  /// Кэш очищен целиком.
  pub fn offline_drop_kind(&self, kind: &str) -> Result<()> {
    self.db.execute("DELETE FROM offline_tracks WHERE kind = ?1", [kind])?;
    Ok(())
  }

  /// Что играет без сети: файлы кэша, локальные файлы и треки, чей двойник (`track_alias`) лежит в кэше.
  pub fn offline_refs(&self) -> Result<Vec<String>> {
    let mut st = self.db.prepare(
      "SELECT ref FROM offline_tracks
       UNION SELECT ref FROM local_files
       UNION SELECT source_ref FROM track_alias WHERE alias_ref IN (SELECT ref FROM offline_tracks)",
    )?;
    let rows = st.query_map([], |r| r.get::<_, String>(0))?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
  }

  /// Треки из кэша для офлайн-списков (новые сверху). Снимка нет — берём из `tracks`, нет и там — пропускаем.
  pub fn offline_cached_tracks(&self) -> Result<Vec<Track>> {
    let mut st = self.db.prepare("SELECT ref, meta_json FROM offline_tracks ORDER BY added_at DESC")?;
    let rows: Vec<(String, String)> =
      st.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<rusqlite::Result<_>>()?;
    let mut out = Vec::with_capacity(rows.len());
    for (r, meta) in rows {
      match serde_json::from_str::<Option<Track>>(&meta).ok().flatten() {
        Some(t) => out.push(t),
        None => out.extend(self.tracks(&[r])?),
      }
    }
    Ok(out)
  }

  /// Сверка с папкой кэша при запуске. `files` — имена `.audio` на диске с размером и типом.
  /// Строки без файла уходят; файл без строки (лёг до миграции) находит свой ref по ключу среди `tracks`.
  /// Возвращает, поменялось ли что-то.
  pub fn offline_reconcile(&self, files: &HashMap<String, (u64, String)>, key: fn(&str) -> String) -> Result<bool> {
    let known: Vec<String> = {
      let mut st = self.db.prepare("SELECT file FROM offline_tracks WHERE kind = ?1")?;
      let rows = st.query_map([KIND_CACHE], |r| r.get::<_, String>(0))?;
      rows.collect::<rusqlite::Result<_>>()?
    };
    let mut changed = false;
    for f in known.iter().filter(|f| !files.contains_key(*f)) {
      self.offline_drop_file(f)?;
      changed = true;
    }
    let known: HashSet<&String> = known.iter().collect();
    let orphans: HashSet<&String> = files.keys().filter(|f| !known.contains(f)).collect();
    if orphans.is_empty() {
      return Ok(changed);
    }
    let refs: Vec<String> = {
      let mut st = self.db.prepare("SELECT ref FROM tracks")?;
      let rows = st.query_map([], |r| r.get::<_, String>(0))?;
      rows.collect::<rusqlite::Result<_>>()?
    };
    for r in refs {
      let file = format!("{}.audio", key(&r));
      if let Some((bytes, mime)) = orphans.get(&file).and_then(|f| files.get(*f)) {
        self.offline_put(&r, &file, mime, *bytes, KIND_CACHE)?;
        changed = true;
      }
    }
    Ok(changed)
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn track(r: &str, title: &str) -> Track {
    Track {
      ref_: r.into(),
      title: title.into(),
      artist: "a".into(),
      artists: vec![],
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

  fn key(r: &str) -> String {
    crate::track_cache::key(r)
  }

  #[test]
  fn index_keeps_snapshot_and_follows_cache() {
    let mut s = Store::memory().unwrap();
    s.upsert_tracks(&[track("sc:1", "Первый")]).unwrap();
    s.offline_put("sc:1", "sc_1.audio", "audio/mpeg", 10, KIND_CACHE).unwrap();
    // трек в `tracks` переписали — офлайн-список показывает снимок
    s.upsert_tracks(&[track("sc:1", "Другое")]).unwrap();
    assert_eq!(s.offline_cached_tracks().unwrap()[0].title, "Первый");
    assert_eq!(s.offline_refs().unwrap(), vec!["sc:1".to_owned()]);

    s.offline_drop_file("sc_1.audio").unwrap();
    assert!(s.offline_refs().unwrap().is_empty());
  }

  #[test]
  fn alias_in_cache_makes_source_available() {
    let s = Store::memory().unwrap();
    s.db
      .execute("INSERT INTO track_alias (source_ref, service, alias_ref, found_at) VALUES ('sc:1', 'ym', 'ym:9', 0)", [])
      .unwrap();
    s.offline_put("ym:9", "ym_9.audio", "audio/mpeg", 10, KIND_CACHE).unwrap();
    let refs: HashSet<String> = s.offline_refs().unwrap().into_iter().collect();
    assert_eq!(refs, HashSet::from(["sc:1".to_owned(), "ym:9".to_owned()]));
  }

  #[test]
  fn reconcile_drops_missing_and_adopts_old_files() {
    let mut s = Store::memory().unwrap();
    s.upsert_tracks(&[track("sc:1", "старый файл"), track("sc:2", "пропал")]).unwrap();
    s.offline_put("sc:2", "sc_2.audio", "audio/mpeg", 10, KIND_CACHE).unwrap();
    let disk = HashMap::from([
      ("sc_1.audio".to_owned(), (42, "audio/mp4".to_owned())),
      ("chuzhoy.audio".to_owned(), (1, "audio/mpeg".to_owned())),
    ]);
    assert!(s.offline_reconcile(&disk, key).unwrap());
    assert_eq!(s.offline_refs().unwrap(), vec!["sc:1".to_owned()]);
    assert!(!s.offline_reconcile(&disk, key).unwrap(), "второй проход ничего не меняет");
  }
}
