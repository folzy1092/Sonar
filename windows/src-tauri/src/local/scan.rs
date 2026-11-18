//! Скан папок с музыкой. Без базы и без окна — только файлы: на входе папки и то, что уже лежит в
//! `local_files`, на выходе — что добавить/обновить и что удалить. Повторный скан читает теги
//! только у новых и изменённых файлов (время изменения или размер).
//!
//! Пропавший файл (удалили, вынули флешку) строку не теряет — она серая «Файл не найден» с «Найти в
//! сервисах», пока папка в списке. Уходит строка, только если папку убрали из списка или файл явно
//! переехал: в тех же папках нашёлся файл того же размера с теми же названием и исполнителем.

use super::{is_audio, is_cover_file, local_ref, sha1_hex, tags};
use crate::store::LocalFile;
use serde::Serialize;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

/// Больше файлов не берём — защита от «папкой выбран весь диск».
const MAX_FILES: usize = 50_000;

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Summary {
  /// Файлов в индексе после скана (вместе с пропавшими).
  pub total: usize,
  pub added: usize,
  pub updated: usize,
  pub removed: usize,
  /// Строк, чьих файлов сейчас нет на диске (серые «Файл не найден»).
  pub missing: usize,
  /// Файлов больше `MAX_FILES` — обход остановлен, непросмотренные строки не тронуты.
  pub truncated: bool,
}

#[derive(Debug, Default)]
pub struct ScanResult {
  pub upserts: Vec<LocalFile>,
  pub removed: Vec<String>,
  pub summary: Summary,
}

fn hidden(path: &Path) -> bool {
  path.file_name().is_some_and(|n| n.to_string_lossy().starts_with('.'))
}

/// Аудиофайлы папки и подпапок. По ссылкам на папки не ходим (петли), скрытое пропускаем.
/// `false` — упёрлись в `limit` и обошли не всё.
fn collect(root: &Path, out: &mut Vec<PathBuf>, limit: usize) -> bool {
  let mut stack = vec![root.to_path_buf()];
  while let Some(dir) = stack.pop() {
    let Ok(rd) = std::fs::read_dir(&dir) else { continue };
    for entry in rd.flatten() {
      if out.len() >= limit {
        return false;
      }
      let path = entry.path();
      if hidden(&path) {
        continue;
      }
      let Ok(kind) = entry.file_type() else { continue };
      if kind.is_dir() {
        stack.push(path);
      } else if is_audio(&path) && (kind.is_file() || path.is_file()) {
        out.push(path);
      }
    }
  }
  true
}

fn stat(path: &Path) -> Option<(i64, i64)> {
  let meta = std::fs::metadata(path).ok()?;
  let mtime = meta.modified().ok()?.duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0);
  Some((mtime, meta.len() as i64))
}

/// Обложку — в кэш обложек под именем по содержимому (одинаковые обложки альбома — один файл).
fn save_cover(cover_dir: &Path, bytes: &[u8], ext: &str) -> Option<String> {
  let name = format!("local-{}.{ext}", sha1_hex(bytes));
  let path = cover_dir.join(&name);
  if !path.is_file() {
    std::fs::create_dir_all(cover_dir).ok()?;
    std::fs::write(&path, bytes).ok()?;
  }
  Some(path.to_string_lossy().into_owned())
}

fn read_file(path: &Path, mtime: i64, size: i64, cover_dir: Option<&Path>) -> LocalFile {
  let meta = tags::read(path);
  let cover_path = match (meta.cover, cover_dir) {
    (Some((bytes, ext)), Some(dir)) => save_cover(dir, &bytes, ext),
    _ => None,
  };
  LocalFile {
    ref_: local_ref(path),
    path: path.to_string_lossy().into_owned(),
    mtime,
    size,
    title: meta.title,
    artist: meta.artist,
    album: meta.album,
    duration_ms: meta.duration_ms,
    cover_path,
  }
}

/// Строка не изменилась: тот же файл и его обложка на месте.
fn unchanged(known: &LocalFile, mtime: i64, size: i64) -> bool {
  known.mtime == mtime && known.size == size && known.cover_path.as_deref().is_none_or(|c| Path::new(c).is_file())
}

/// Тот же трек по содержимому: размер, название и исполнитель (переименовали или переложили).
type Twin = (i64, String, String);

fn twin(f: &LocalFile) -> Twin {
  (f.size, f.title.clone(), f.artist.clone())
}

/// Скан папок. Пропавший файл в папке из списка (и вся папка, которой сейчас нет: флешка, сетевой
/// диск) — строка остаётся серой «Файл не найден»; убранная из списка папка — строки удаляются.
pub fn scan(folders: &[PathBuf], known: &[LocalFile], cover_dir: Option<&Path>) -> ScanResult {
  scan_with_limit(folders, known, cover_dir, MAX_FILES)
}

fn scan_with_limit(folders: &[PathBuf], known: &[LocalFile], cover_dir: Option<&Path>, limit: usize) -> ScanResult {
  let by_path: HashMap<&str, &LocalFile> = known.iter().map(|f| (f.path.as_str(), f)).collect();
  // ref → лежит ли файл на диске (по итогам этого скана)
  let mut seen: HashMap<String, bool> = HashMap::new();
  let mut present: HashSet<Twin> = HashSet::new();
  let mut result = ScanResult::default();
  let mut files = Vec::new();
  let mut complete = true;
  for folder in folders.iter().filter(|f| f.is_dir()) {
    complete &= collect(folder, &mut files, limit);
  }
  files.sort();
  files.dedup();
  for path in files {
    let Some((mtime, size)) = stat(&path) else { continue };
    let key = path.to_string_lossy();
    let f = match by_path.get(key.as_ref()) {
      Some(k) if unchanged(k, mtime, size) => (*k).clone(),
      Some(_) => {
        result.summary.updated += 1;
        read_file(&path, mtime, size, cover_dir)
      }
      None => {
        result.summary.added += 1;
        read_file(&path, mtime, size, cover_dir)
      }
    };
    present.insert(twin(&f));
    seen.insert(f.ref_.clone(), true);
    if by_path.get(key.as_ref()).is_none_or(|k| **k != f) {
      result.upserts.push(f);
    }
  }
  let unseen: Vec<&LocalFile> = known.iter().filter(|f| !seen.contains_key(&f.ref_)).collect();
  for f in unseen {
    let in_list = folders.iter().any(|d| Path::new(&f.path).starts_with(d));
    // обход не полный — непросмотренное не трогаем: файл, скорее всего, на месте
    let moved = complete && present.contains(&twin(f)) && !Path::new(&f.path).is_file();
    if in_list && !moved {
      seen.insert(f.ref_.clone(), !complete && Path::new(&f.path).is_file());
    } else {
      result.removed.push(f.ref_.clone());
    }
  }
  result.summary.removed = result.removed.len();
  result.summary.total = seen.len();
  result.summary.missing = seen.values().filter(|on_disk| !**on_disk).count();
  result.summary.truncated = !complete;
  result
}

/// Убрать из кэша обложки локальных файлов, на которые больше никто не ссылается.
pub fn prune_covers(cover_dir: &Path, files: &[LocalFile]) -> usize {
  let used: HashSet<String> = files
    .iter()
    .filter_map(|f| f.cover_path.as_deref())
    .filter_map(|p| Path::new(p).file_name().map(|n| n.to_string_lossy().into_owned()))
    .collect();
  let Ok(rd) = std::fs::read_dir(cover_dir) else { return 0 };
  let mut n = 0;
  for e in rd.flatten() {
    let name = e.file_name().to_string_lossy().into_owned();
    if is_cover_file(&name) && !used.contains(&name) && std::fs::remove_file(e.path()).is_ok() {
      n += 1;
    }
  }
  n
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::local::fixtures::{tag_wav, temp_dir, write_wav, PNG};

  fn apply(known: &mut Vec<LocalFile>, r: &ScanResult) {
    known.retain(|f| !r.removed.contains(&f.ref_) && !r.upserts.iter().any(|u| u.ref_ == f.ref_));
    known.extend(r.upserts.iter().cloned());
  }

  #[test]
  fn finds_audio_recursively_and_skips_others() {
    let music = temp_dir("scan-music");
    let covers = temp_dir("scan-covers");
    write_wav(&music.join("A - One.wav"), 200);
    write_wav(&music.join("sub/deeper/Two.WAV"), 200);
    tag_wav(&music.join("sub/deeper/Two.WAV"), "Два", "Б", Some("Альбом"), Some(PNG));
    std::fs::write(music.join("notes.txt"), b"x").unwrap();
    write_wav(&music.join(".hidden/Three.wav"), 200);
    write_wav(&music.join("._junk.wav"), 200);

    let r = scan(std::slice::from_ref(&music), &[], Some(&covers));
    assert_eq!(r.summary, Summary { total: 2, added: 2, ..Summary::default() });
    let mut titles: Vec<&str> = r.upserts.iter().map(|f| f.title.as_str()).collect();
    titles.sort_unstable();
    assert_eq!(titles, ["One", "Два"]);
    let two = r.upserts.iter().find(|f| f.title == "Два").unwrap();
    assert_eq!(two.ref_, local_ref(&music.join("sub/deeper/Two.WAV")));
    assert_eq!(two.album.as_deref(), Some("Альбом"));
    let cover = two.cover_path.as_deref().unwrap();
    assert_eq!(std::fs::read(cover).unwrap(), PNG);
    assert!(super::super::cover_name_valid(&Path::new(cover).file_name().unwrap().to_string_lossy()));
    let _ = std::fs::remove_dir_all(music);
    let _ = std::fs::remove_dir_all(covers);
  }

  #[test]
  fn rescan_is_incremental() {
    let music = temp_dir("scan-inc");
    let a = music.join("a.wav");
    let b = music.join("b.wav");
    write_wav(&a, 200);
    write_wav(&b, 200);
    let mut known = vec![];
    let r = scan(std::slice::from_ref(&music), &known, None);
    apply(&mut known, &r);
    assert_eq!(r.summary.added, 2);

    // ничего не менялось — теги не читаются, строк на запись нет
    let r = scan(std::slice::from_ref(&music), &known, None);
    assert!(r.upserts.is_empty() && r.removed.is_empty());
    assert_eq!(r.summary, Summary { total: 2, ..Summary::default() });

    // изменился размер одного (новые теги) и удалён другой — его строка остаётся серой
    tag_wav(&a, "Новое", "Кто-то", None, None);
    std::fs::remove_file(&b).unwrap();
    let r = scan(std::slice::from_ref(&music), &known, None);
    assert_eq!(r.summary, Summary { total: 2, updated: 1, missing: 1, ..Summary::default() });
    assert_eq!(r.upserts.len(), 1);
    assert_eq!(r.upserts[0].title, "Новое");
    assert!(r.removed.is_empty());
    let _ = std::fs::remove_dir_all(music);
  }

  #[test]
  fn moved_file_replaces_its_old_row() {
    let music = temp_dir("scan-moved");
    let old = music.join("old.wav");
    write_wav(&old, 200);
    tag_wav(&old, "Песня", "Кто", None, None);
    let other = music.join("other.wav");
    write_wav(&other, 300);
    let mut known = vec![];
    let r = scan(std::slice::from_ref(&music), &known, None);
    apply(&mut known, &r);

    let new = music.join("sub/new.wav");
    std::fs::create_dir_all(new.parent().unwrap()).unwrap();
    std::fs::rename(&old, &new).unwrap();
    std::fs::remove_file(&other).unwrap();
    let r = scan(std::slice::from_ref(&music), &known, None);
    // переложенный — старая строка уходит, новая появляется; просто удалённый — серый
    assert_eq!(r.removed, [local_ref(&old)]);
    assert_eq!(r.upserts.len(), 1);
    assert_eq!(r.upserts[0].ref_, local_ref(&new));
    assert_eq!(r.summary, Summary { total: 2, added: 1, removed: 1, missing: 1, ..Summary::default() });
    let _ = std::fs::remove_dir_all(music);
  }

  #[test]
  fn truncated_walk_keeps_unvisited_rows() {
    let music = temp_dir("scan-limit");
    for name in ["a.wav", "b.wav", "c.wav"] {
      write_wav(&music.join(name), 200);
    }
    let mut known = vec![];
    let r = scan(std::slice::from_ref(&music), &known, None);
    apply(&mut known, &r);
    let r = scan_with_limit(std::slice::from_ref(&music), &known, None, 2);
    assert!(r.summary.truncated);
    assert!(r.removed.is_empty() && r.upserts.is_empty());
    // непросмотренный файл на месте — не пропавший
    assert_eq!(r.summary, Summary { total: 3, truncated: true, ..Summary::default() });
    let _ = std::fs::remove_dir_all(music);
  }

  #[test]
  fn missing_folder_keeps_rows_removed_folder_drops_them() {
    let music = temp_dir("scan-missing");
    write_wav(&music.join("a.wav"), 200);
    let mut known = vec![];
    let r = scan(std::slice::from_ref(&music), &known, None);
    apply(&mut known, &r);
    std::fs::remove_dir_all(&music).unwrap();
    // папки нет (флешка вынута) — строка остаётся, станет серой
    let r = scan(std::slice::from_ref(&music), &known, None);
    assert!(r.removed.is_empty() && r.upserts.is_empty());
    assert_eq!(r.summary.total, 1);
    assert_eq!(r.summary.missing, 1);
    // папку убрали из списка — строки уходят
    let r = scan(&[], &known, None);
    assert_eq!(r.removed, [known[0].ref_.clone()]);
  }

  #[test]
  fn deleted_cover_is_restored_and_orphans_pruned() {
    let music = temp_dir("scan-cover");
    let covers = temp_dir("scan-cover-dir");
    let a = music.join("a.wav");
    write_wav(&a, 200);
    tag_wav(&a, "T", "A", None, Some(PNG));
    let mut known = vec![];
    let r = scan(std::slice::from_ref(&music), &known, Some(&covers));
    apply(&mut known, &r);
    let cover = PathBuf::from(known[0].cover_path.clone().unwrap());
    std::fs::remove_file(&cover).unwrap();
    let r = scan(std::slice::from_ref(&music), &known, Some(&covers));
    assert_eq!(r.summary.updated, 1);
    assert!(cover.is_file());

    let orphan = covers.join(format!("local-{}.jpg", "d".repeat(40)));
    std::fs::write(&orphan, b"x").unwrap();
    let foreign = covers.join("0123abcd");
    std::fs::write(&foreign, b"x").unwrap();
    assert_eq!(prune_covers(&covers, &known), 1);
    assert!(!orphan.exists() && foreign.exists() && cover.exists());
    let _ = std::fs::remove_dir_all(music);
    let _ = std::fs::remove_dir_all(covers);
  }
}
