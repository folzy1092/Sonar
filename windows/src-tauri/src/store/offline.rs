//! `offline_tracks` (миграция № 16, `docs/OFFLINE.md` §7.1): что из сервисов лежит на диске и играет без сети.
//! Только на этом устройстве, в синк не идёт. Пишет его кэш треков (`track_cache::Change` → `offline_index.rs`),
//! при запуске индекс сверяется с папкой кэша. Снимок `Track` хранится в строке: `tracks` могут обновить,
//! а офлайн-список обязан показать название.

use super::{now_ms, Store};
use crate::providers::Track;
use anyhow::Result;
use rusqlite::params;
use std::collections::{HashMap, HashSet};

/// Файл в кэше, который лёг сам (прослушан или подкачан).
pub const KIND_CACHE: &str = "cache";
/// Скачанное руками («Скачать», `downloads.rs`): лежит в `<кэш>/pinned`, не вытесняется.
pub const KIND_PINNED: &str = "pinned";

impl Store {
  /// Файл лёг в кэш: строка со снимком трека (если трек уже есть в `tracks`).
  /// Скачанное копией из автокэша не перезаписывается; снимка нет — остаётся прежний.
  pub fn offline_put(&self, track_ref: &str, file: &str, mime: &str, bytes: u64, kind: &str) -> Result<()> {
    let meta = self.tracks(&[track_ref.to_owned()])?.into_iter().next();
    let meta_json = serde_json::to_string(&meta)?;
    self.db.execute(
      "INSERT INTO offline_tracks (ref, file, mime, bytes, kind, added_at, meta_json) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
       ON CONFLICT(ref) DO UPDATE SET file = ?2, mime = ?3, bytes = ?4, kind = ?5,
         meta_json = CASE WHEN ?7 = 'null' THEN offline_tracks.meta_json ELSE ?7 END
       WHERE NOT (offline_tracks.kind = ?8 AND ?5 = ?9)",
      params![track_ref, file, mime, bytes as i64, kind, now_ms(), meta_json, KIND_PINNED, KIND_CACHE],
    )?;
    Ok(())
  }

  /// Файл ушёл (вытеснен из кэша или удалён из скачанного). `kind` — из какой папки: одноимённая строка
  /// другого вида (трек скачан, а из автокэша ушла старая копия) остаётся.
  pub fn offline_drop_file(&self, file: &str, kind: &str) -> Result<()> {
    self.db.execute("DELETE FROM offline_tracks WHERE file = ?1 AND kind = ?2", params![file, kind])?;
    Ok(())
  }

  /// Скачанные руками треки.
  pub fn offline_pinned_refs(&self) -> Result<Vec<String>> {
    let mut st = self.db.prepare("SELECT ref FROM offline_tracks WHERE kind = ?1")?;
    let rows = st.query_map([KIND_PINNED], |r| r.get::<_, String>(0))?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
  }

  /// Обложки скачанного: адреса из снимков (для чистки папки обложек скачанного).
  pub fn offline_pinned_covers(&self) -> Result<HashSet<String>> {
    let mut st = self.db.prepare(
      "SELECT json_extract(meta_json, '$.cover_url') FROM offline_tracks WHERE kind = ?1 AND json_extract(meta_json, '$.cover_url') IS NOT NULL",
    )?;
    let rows = st.query_map([KIND_PINNED], |r| r.get::<_, String>(0))?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
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

  /// Сверка с папкой кэша (`kind` — автокэш или скачанное) при запуске. `files` — имена `.audio` на диске
  /// с размером и типом. Строки без файла уходят; файл без строки (лёг до миграции или запись в базу не
  /// успела) находит свой ref по ключу среди `tracks`. Возвращает, поменялось ли что-то.
  pub fn offline_reconcile(&self, files: &HashMap<String, (u64, String)>, key: fn(&str) -> String, kind: &str) -> Result<bool> {
    let known: Vec<String> = {
      let mut st = self.db.prepare("SELECT file FROM offline_tracks WHERE kind = ?1")?;
      let rows = st.query_map([kind], |r| r.get::<_, String>(0))?;
      rows.collect::<rusqlite::Result<_>>()?
    };
    let mut changed = false;
    for f in known.iter().filter(|f| !files.contains_key(*f)) {
      self.offline_drop_file(f, kind)?;
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
        self.offline_put(&r, &file, mime, *bytes, kind)?;
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

    s.offline_drop_file("sc_1.audio", KIND_PINNED).unwrap();
    assert_eq!(s.offline_refs().unwrap().len(), 1, "чужой вид не трогаем");
    s.offline_drop_file("sc_1.audio", KIND_CACHE).unwrap();
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
    assert!(s.offline_reconcile(&disk, key, KIND_CACHE).unwrap());
    assert_eq!(s.offline_refs().unwrap(), vec!["sc:1".to_owned()]);
    assert!(!s.offline_reconcile(&disk, key, KIND_CACHE).unwrap(), "второй проход ничего не меняет");
    // сверка скачанного не трогает строки автокэша
    assert!(!s.offline_reconcile(&HashMap::new(), key, KIND_PINNED).unwrap());
    assert_eq!(s.offline_refs().unwrap(), vec!["sc:1".to_owned()]);
  }

  #[test]
  fn pinned_is_not_downgraded_by_cache_copy() {
    let mut s = Store::memory().unwrap();
    let mut t = track("sc:1", "Скачан");
    t.cover_url = Some("https://i1.sndcdn.com/a.jpg".into());
    s.upsert_tracks(&[t]).unwrap();
    s.offline_put("sc:1", "sc_1.audio", "audio/mpeg", 10, KIND_CACHE).unwrap();
    s.offline_put("sc:1", "sc_1.audio", "audio/mp4", 20, KIND_PINNED).unwrap();
    // старая копия автокэша легла позже — скачанное остаётся скачанным
    s.offline_put("sc:1", "sc_1.audio", "audio/mpeg", 10, KIND_CACHE).unwrap();
    assert_eq!(s.offline_pinned_refs().unwrap(), vec!["sc:1".to_owned()]);
    assert!(s.offline_pinned_covers().unwrap().contains("https://i1.sndcdn.com/a.jpg"));
    s.offline_drop_kind(KIND_CACHE).unwrap();
    assert_eq!(s.offline_pinned_refs().unwrap().len(), 1);
  }

  #[test]
  fn pinned_lyrics_survive_prune() {
    let s = Store::memory().unwrap();
    s.put_lyrics("sc:1", Some("{}"), Some("lrclib")).unwrap();
    s.put_lyrics("sc:2", Some("{}"), Some("lrclib")).unwrap();
    s.offline_put("sc:1", "sc_1.audio", "audio/mpeg", 10, KIND_PINNED).unwrap();
    let later = now_ms() + 60 * 86_400_000;
    assert_eq!(s.prune_lyrics(later).unwrap(), 1);
    assert!(s.lyrics_cached("sc:1").unwrap().is_some());
  }
}
