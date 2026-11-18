//! Локальные файлы (Система → Хранилище → «Папки с музыкой», NEXT_PROMPT этап 10): папки
//! владельца сканируются (`scan.rs`, теги и обложки — `tags.rs` на lofty), за ними следит `notify`
//! (`watch.rs`), найденное лежит в таблице `local_files`. Трек — обычный `Track` с ref
//! `local:<sha1 пути>`: работает в Любимых, плейлистах, очереди, поиске и статистике.
//!
//! Безопасность: аудио-сервер отдаёт по `local:` **только** файлы из индекса (`Index` — копия
//! `local_files` в памяти), никаких путей из запроса; обложки — только `local-<sha1>.<ext>` из кэша
//! обложек.

pub mod commands;
mod scan;
mod tags;
mod watch;

pub use scan::{prune_covers, scan, Summary};

use crate::store::LocalFile;
use sha1::{Digest, Sha1};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::RwLock;

/// Какие файлы считаем музыкой (по расширению, без учёта регистра).
pub const AUDIO_EXTS: &[&str] = &["mp3", "flac", "m4a", "ogg", "opus", "wav"];
/// Префикс ref локального трека.
pub const PREFIX: &str = "local";
/// Схема адресов обложек локальных файлов (`lib.rs` регистрирует её у окна).
pub const COVER_SCHEME: &str = "sonarcover";
/// Обложки локальных файлов в кэше обложек: `local-<sha1 картинки>.<ext>`.
const COVER_PREFIX: &str = "local-";
const COVER_EXTS: &[&str] = &["jpg", "png", "gif", "bmp", "tiff"];

/// `local:<sha1 пути>` — один и тот же файл всегда даёт один ref (лайки и плейлисты не теряются
/// при пересканировании). Путь сначала собирается заново из частей: на Windows `C:\m/a.mp3` и
/// `C:\m\a.mp3` — один файл и один ref.
pub fn local_ref(path: &Path) -> String {
  let normalized: PathBuf = path.components().collect();
  format!("{PREFIX}:{}", sha1_hex(normalized.to_string_lossy().as_bytes()))
}

pub fn is_local_ref(r: &str) -> bool {
  r.strip_prefix(PREFIX).is_some_and(|rest| rest.starts_with(':'))
}

pub(crate) fn sha1_hex(bytes: &[u8]) -> String {
  Sha1::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

fn ext_lower(path: &Path) -> Option<String> {
  path.extension().and_then(|e| e.to_str()).map(str::to_ascii_lowercase)
}

pub fn is_audio(path: &Path) -> bool {
  ext_lower(path).is_some_and(|e| AUDIO_EXTS.contains(&e.as_str()))
}

/// MIME для `<audio>` по расширению.
pub fn audio_mime(path: &Path) -> &'static str {
  match ext_lower(path).as_deref() {
    Some("flac") => "audio/flac",
    Some("m4a") => "audio/mp4",
    Some("ogg" | "opus") => "audio/ogg",
    Some("wav") => "audio/wav",
    _ => "audio/mpeg",
  }
}

/// Плашка качества в плеере: «FLAC · файл».
pub fn quality_label(path: &Path) -> String {
  let kind = match ext_lower(path).as_deref() {
    Some("flac") => "FLAC",
    Some("m4a") => "AAC",
    Some("ogg") => "OGG",
    Some("opus") => "Opus",
    Some("wav") => "WAV",
    _ => "MP3",
  };
  format!("{kind} · файл")
}

/// Адрес обложки для `<img>`: у WebView2 своя схема — `http://<схема>.localhost/…`.
pub fn cover_url(name: &str) -> String {
  if cfg!(windows) {
    format!("http://{COVER_SCHEME}.localhost/{name}")
  } else {
    format!("{COVER_SCHEME}://localhost/{name}")
  }
}

/// Имя обложки из адреса `cover_url` (или None, если адрес чужой).
pub fn cover_name_from_url(url: &str) -> Option<&str> {
  let rest = url
    .strip_prefix(&format!("http://{COVER_SCHEME}.localhost/"))
    .or_else(|| url.strip_prefix(&format!("{COVER_SCHEME}://localhost/")))?;
  cover_name_valid(rest).then_some(rest)
}

/// Только `local-<40 hex>.<ext>` — ни слешей, ни `..`.
pub fn cover_name_valid(name: &str) -> bool {
  let Some(rest) = name.strip_prefix(COVER_PREFIX) else { return false };
  let Some((hash, ext)) = rest.split_once('.') else { return false };
  hash.len() == 40 && hash.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase()) && COVER_EXTS.contains(&ext)
}

pub(crate) fn is_cover_file(name: &str) -> bool {
  name.starts_with(COVER_PREFIX)
}

fn image_mime(name: &str) -> &'static str {
  match name.rsplit('.').next() {
    Some("png") => "image/png",
    Some("gif") => "image/gif",
    Some("bmp") => "image/bmp",
    Some("tiff") => "image/tiff",
    _ => "image/jpeg",
  }
}

/// Обложка локального файла из кэша обложек: байты и MIME. Чужое имя — None.
pub fn read_cover(dir: &Path, name: &str) -> Option<(Vec<u8>, &'static str)> {
  if !cover_name_valid(name) {
    return None;
  }
  std::fs::read(dir.join(name)).ok().map(|b| (b, image_mime(name)))
}

/// Индекс в памяти: ref → путь. Аудио-сервер играет только то, что здесь есть.
#[derive(Default)]
pub struct Index {
  map: RwLock<HashMap<String, PathBuf>>,
}

impl Index {
  pub fn replace(&self, files: &[LocalFile]) {
    let map = files.iter().map(|f| (f.ref_.clone(), PathBuf::from(&f.path))).collect();
    *self.map.write().unwrap_or_else(|e| e.into_inner()) = map;
  }

  pub fn get(&self, r: &str) -> Option<PathBuf> {
    self.map.read().unwrap_or_else(|e| e.into_inner()).get(r).cloned()
  }

  #[cfg(test)]
  pub fn len(&self) -> usize {
    self.map.read().unwrap_or_else(|e| e.into_inner()).len()
  }
}

#[cfg(test)]
pub(crate) mod fixtures;

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn ref_is_stable_sha1_of_path() {
    let p = Path::new("/music/a.mp3");
    let r = local_ref(p);
    assert_eq!(r, local_ref(Path::new("/music/a.mp3")));
    assert_ne!(r, local_ref(Path::new("/music/b.mp3")));
    assert!(r.starts_with("local:") && r.len() == "local:".len() + 40, "{r}");
    assert!(is_local_ref(&r));
    assert!(!is_local_ref("localx:1") && !is_local_ref("sc:1") && !is_local_ref("local"));
  }

  #[test]
  fn audio_kinds() {
    for (name, audio, mime) in [
      ("a.mp3", true, "audio/mpeg"),
      ("a.FLAC", true, "audio/flac"),
      ("a.m4a", true, "audio/mp4"),
      ("a.ogg", true, "audio/ogg"),
      ("a.opus", true, "audio/ogg"),
      ("a.wav", true, "audio/wav"),
      ("a.jpg", false, "audio/mpeg"),
      ("noext", false, "audio/mpeg"),
    ] {
      assert_eq!(is_audio(Path::new(name)), audio, "{name}");
      assert_eq!(audio_mime(Path::new(name)), mime, "{name}");
    }
    assert_eq!(quality_label(Path::new("x.flac")), "FLAC · файл");
    assert_eq!(quality_label(Path::new("x.mp3")), "MP3 · файл");
  }

  #[test]
  fn cover_names_are_strict() {
    let good = format!("local-{}.jpg", "a".repeat(40));
    assert!(cover_name_valid(&good));
    assert!(!cover_name_valid(&format!("local-{}.jpg", "A".repeat(40))));
    assert!(!cover_name_valid(&format!("local-{}.exe", "a".repeat(40))));
    assert!(!cover_name_valid(&format!("local-{}.jpg", "a".repeat(39))));
    assert!(!cover_name_valid("../sonar.db"));
    assert!(!cover_name_valid(&format!("local-../{}.jpg", "a".repeat(37))));
    assert!(!cover_name_valid("0123456789abcdef"));
    assert_eq!(cover_name_from_url(&cover_url(&good)), Some(good.as_str()));
    assert_eq!(cover_name_from_url("https://i1.sndcdn.com/x.jpg"), None);
    assert_eq!(cover_name_from_url(&cover_url("..%2Fsonar.db")), None);
  }

  #[test]
  fn read_cover_only_valid_names() {
    let dir = fixtures::temp_dir("cover-read");
    let name = format!("local-{}.png", "b".repeat(40));
    std::fs::write(dir.join(&name), b"png").unwrap();
    std::fs::write(dir.join("secret.txt"), b"x").unwrap();
    assert_eq!(read_cover(&dir, &name), Some((b"png".to_vec(), "image/png")));
    assert_eq!(read_cover(&dir, "secret.txt"), None);
    assert_eq!(read_cover(&dir, &format!("local-{}.jpg", "c".repeat(40))), None);
    let _ = std::fs::remove_dir_all(dir);
  }
}
