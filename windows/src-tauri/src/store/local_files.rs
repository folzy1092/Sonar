//! Локальные файлы (`local_files`, docs/DB.md): что нашёл скан папок с музыкой. Только на этом
//! устройстве — в синк не идёт; лайки и плейлисты хранят обычный ref `local:<sha1 пути>`.

use super::Store;
use crate::providers::{AlbumRef, Track};
use anyhow::Result;
use rusqlite::{params, OptionalExtension, Row};
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LocalFile {
  #[serde(rename = "ref")]
  pub ref_: String,
  pub path: String,
  /// Время изменения файла, мс.
  pub mtime: i64,
  pub size: i64,
  pub title: String,
  pub artist: String,
  pub album: Option<String>,
  pub duration_ms: i64,
  /// Обложка в кэше обложек: `<кэш>/covers/local-<sha1>.<ext>`.
  pub cover_path: Option<String>,
}

impl LocalFile {
  fn from_row(r: &Row<'_>) -> rusqlite::Result<Self> {
    Ok(Self {
      ref_: r.get(0)?,
      path: r.get(1)?,
      mtime: r.get(2)?,
      size: r.get(3)?,
      title: r.get(4)?,
      artist: r.get(5)?,
      album: r.get(6)?,
      duration_ms: r.get(7)?,
      cover_path: r.get(8)?,
    })
  }

  /// Файл на месте (иначе строка серая: «Файл не найден»).
  pub fn exists(&self) -> bool {
    Path::new(&self.path).is_file()
  }

  /// Обычный трек Sonar. Альбом — без ref (страницы у локального альбома нет).
  pub fn to_track(&self, available: bool) -> Track {
    let cover_name = self.cover_path.as_deref().and_then(|p| Path::new(p).file_name()).map(|n| n.to_string_lossy().into_owned());
    Track {
      ref_: self.ref_.clone(),
      title: self.title.clone(),
      artist: self.artist.clone(),
      artists: vec![],
      album: self.album.as_ref().map(|t| AlbumRef { ref_: String::new(), title: t.clone() }),
      duration_ms: self.duration_ms.max(0) as u64,
      cover_url: cover_name.map(|n| crate::local::cover_url(&n)),
      url: None,
      explicit: false,
      available,
      plays: None,
      tags: None,
    }
  }
}

const COLS: &str = "ref, path, mtime, size, title, artist, album, duration_ms, cover_path";

impl Store {
  /// Все найденные файлы: по исполнителю, потом по названию.
  pub fn local_files(&self) -> Result<Vec<LocalFile>> {
    let mut st = self.db.prepare(&format!(
      "SELECT {COLS} FROM local_files ORDER BY artist COLLATE NOCASE, title COLLATE NOCASE, path"
    ))?;
    let rows = st.query_map([], LocalFile::from_row)?.collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
  }

  /// Итог скана одной транзакцией: новые и изменённые строки, удалённые ref. Метаданные треков
  /// (`tracks`) обновляются тоже — Любимые и плейлисты сразу видят новые теги.
  pub fn apply_local_scan(&mut self, upserts: &[LocalFile], removed: &[String]) -> Result<()> {
    let tx = self.db.transaction()?;
    {
      let mut up = tx.prepare(&format!(
        "INSERT INTO local_files ({COLS}) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
         ON CONFLICT(ref) DO UPDATE SET path = ?2, mtime = ?3, size = ?4, title = ?5, artist = ?6, album = ?7,
           duration_ms = ?8, cover_path = ?9"
      ))?;
      for f in upserts {
        up.execute(params![f.ref_, f.path, f.mtime, f.size, f.title, f.artist, f.album, f.duration_ms, f.cover_path])?;
      }
      let mut del = tx.prepare("DELETE FROM local_files WHERE ref = ?1")?;
      for r in removed {
        del.execute([r])?;
      }
    }
    tx.commit()?;
    let tracks: Vec<Track> = upserts.iter().map(|f| f.to_track(true)).collect();
    self.upsert_tracks(&tracks)
  }

  /// Путь файла по ref, если он есть в индексе.
  pub fn local_file(&self, r: &str) -> Result<Option<LocalFile>> {
    Ok(self
      .db
      .query_row(&format!("SELECT {COLS} FROM local_files WHERE ref = ?1"), [r], LocalFile::from_row)
      .optional()?)
  }

  /// Поиск по названию, исполнителю и альбому (без учёта регистра, для кириллицы тоже).
  pub fn search_local(&self, q: &str, limit: usize) -> Result<Vec<LocalFile>> {
    let words: Vec<String> = q.split_whitespace().map(str::to_lowercase).collect();
    if words.is_empty() {
      return Ok(vec![]);
    }
    // SQLite `lower` и `LIKE` без ICU не знают кириллицу — фильтруем в Rust, файлов немного
    let all = self.local_files()?;
    Ok(
      all
        .into_iter()
        .filter(|f| {
          let hay = format!("{} {} {}", f.title, f.artist, f.album.as_deref().unwrap_or("")).to_lowercase();
          words.iter().all(|w| hay.contains(w.as_str()))
        })
        .take(limit)
        .collect(),
    )
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  pub fn file(r: &str, path: &str, title: &str, artist: &str) -> LocalFile {
    LocalFile {
      ref_: r.into(),
      path: path.into(),
      mtime: 1,
      size: 10,
      title: title.into(),
      artist: artist.into(),
      album: Some("Альбом".into()),
      duration_ms: 1000,
      cover_path: Some(format!("/c/local-{}.jpg", "a".repeat(40))),
    }
  }

  #[test]
  fn scan_applies_upserts_and_removals() {
    let mut s = Store::memory().unwrap();
    let a = file("local:a", "/m/a.mp3", "One", "Zed");
    let b = file("local:b", "/m/b.mp3", "Two", "alpha");
    s.apply_local_scan(&[a.clone(), b.clone()], &[]).unwrap();
    // по исполнителю без регистра, потом по названию
    let refs: Vec<String> = s.local_files().unwrap().into_iter().map(|f| f.ref_).collect();
    assert_eq!(refs, ["local:b", "local:a"]);
    let mut a2 = a.clone();
    a2.title = "Новое".into();
    s.apply_local_scan(&[a2.clone()], &["local:b".into()]).unwrap();
    assert_eq!(s.local_files().unwrap(), vec![a2]);
    assert_eq!(s.local_file("local:a").unwrap().unwrap().title, "Новое");
    assert_eq!(s.local_file("local:b").unwrap(), None);
    // метаданные трека тоже обновились (Любимые, плейлисты)
    assert_eq!(s.tracks(&["local:a".into()]).unwrap()[0].title, "Новое");
  }

  #[test]
  fn search_matches_cyrillic_any_case() {
    let mut s = Store::memory().unwrap();
    s.apply_local_scan(&[file("local:a", "/m/a.mp3", "Звезда", "Кино"), file("local:b", "/m/b.mp3", "Other", "Band")], &[]).unwrap();
    let hit = |q: &str| s.search_local(q, 10).unwrap().into_iter().map(|f| f.ref_).collect::<Vec<_>>();
    assert_eq!(hit("кино звЕзда"), ["local:a"]);
    assert_eq!(hit("альбом"), ["local:b", "local:a"]);
    assert_eq!(hit("band"), ["local:b"]);
    assert!(hit("  ").is_empty());
    assert!(hit("нет такого").is_empty());
  }

  #[test]
  fn to_track_shape() {
    let t = file("local:a", "/m/a.mp3", "T", "A").to_track(false);
    assert_eq!(t.ref_, "local:a");
    assert!(!t.available);
    assert_eq!(t.album.unwrap().title, "Альбом");
    assert_eq!(t.cover_url, Some(crate::local::cover_url(&format!("local-{}.jpg", "a".repeat(40)))));
    assert!(t.artists.is_empty() && t.url.is_none());
  }
}
