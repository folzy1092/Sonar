//! Кэш треков на диске (Система → Хранилище → «Кеширование треков»): локальный аудио-сервер
//! (`stream.rs`) складывает прослушанные потоки в `<кэш>/tracks` и в следующий раз отдаёт их с диска —
//! без сети и протухших ссылок. Кэшируются **байты**, не ссылки: файл (mp3 / FLAC) — по мере
//! проигрывания, если он прочитан с начала до конца; HLS SoundCloud — отдельной загрузкой всех кусков,
//! склеенных в один файл (fMP4 с init-куском или mp3; MPEG-TS не склеиваем — `<audio>` его не играет).
//! Лимит — по размеру, вытесняются давно не игравшие (время изменения файла обновляется при чтении).

use std::collections::HashSet;
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::SystemTime;

static DIR: OnceLock<PathBuf> = OnceLock::new();
static ENABLED: AtomicBool = AtomicBool::new(false);
/// Лимит кэша в байтах (по умолчанию 2 ГБ).
static LIMIT: AtomicU64 = AtomicU64::new(2 * 1024 * 1024 * 1024);
/// Треки, которые сейчас скачиваются (HLS) — не качать дважды.
static BUSY: Mutex<Option<HashSet<String>>> = Mutex::new(None);

pub fn set_dir(dir: PathBuf) {
  let _ = fs::create_dir_all(&dir);
  // недописанные файлы прошлого запуска
  if let Ok(rd) = fs::read_dir(&dir) {
    for e in rd.flatten() {
      if e.path().extension().is_some_and(|x| x == "part") {
        let _ = fs::remove_file(e.path());
      }
    }
  }
  let _ = DIR.set(dir);
}

pub fn enabled() -> bool {
  ENABLED.load(Ordering::Relaxed) && DIR.get().is_some()
}

/// Включить / выключить и задать лимит (МБ); при уменьшении лимита лишнее сразу вытесняется.
pub fn configure(on: bool, limit_mb: u64) {
  ENABLED.store(on, Ordering::Relaxed);
  LIMIT.store(limit_mb.max(64) * 1024 * 1024, Ordering::Relaxed);
  if on {
    evict();
  }
}

/// Имя файла по ref трека: только буквы, цифры и `_`.
pub fn key(track_ref: &str) -> String {
  track_ref.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect()
}

fn paths(dir: &Path, track_ref: &str) -> (PathBuf, PathBuf) {
  let k = key(track_ref);
  (dir.join(format!("{k}.audio")), dir.join(format!("{k}.mime")))
}

/// Трек в кэше: путь, тип и размер. Чтение освежает «время последнего использования».
pub fn lookup(track_ref: &str) -> Option<(PathBuf, String, u64)> {
  let dir = DIR.get()?;
  let (audio, mime) = paths(dir, track_ref);
  let len = fs::metadata(&audio).ok()?.len();
  if len == 0 {
    return None;
  }
  let mime = fs::read_to_string(mime).unwrap_or_else(|_| "audio/mpeg".into());
  if let Ok(f) = File::options().write(true).open(&audio) {
    let _ = f.set_modified(SystemTime::now());
  }
  Some((audio, mime.trim().to_owned(), len))
}

/// Кусок файла `[start, end]` (включительно, не больше 8 МБ за раз) — для ответа на Range.
pub fn read_range(path: &Path, start: u64, end: u64) -> std::io::Result<Vec<u8>> {
  let mut f = File::open(path)?;
  let len = end.saturating_sub(start) + 1;
  let len = len.min(8 * 1024 * 1024);
  f.seek(SeekFrom::Start(start))?;
  let mut buf = vec![0; len as usize];
  let n = f.read(&mut buf)?;
  buf.truncate(n);
  Ok(buf)
}

/// Разбор заголовка Range: `bytes=a-b` / `bytes=a-` → (a, b) в пределах файла.
pub fn parse_range(h: Option<&str>, total: u64) -> Option<(u64, u64)> {
  let spec = h?.trim().strip_prefix("bytes=")?;
  let (a, b) = spec.split_once('-')?;
  let last = total.checked_sub(1)?;
  if a.is_empty() {
    // последние N байт
    let n: u64 = b.parse().ok()?;
    return Some((total.saturating_sub(n), last));
  }
  let start: u64 = a.parse().ok()?;
  let end = if b.is_empty() { last } else { b.parse::<u64>().ok()?.min(last) };
  (start <= end).then_some((start, end))
}

/// Запись трека в кэш: пишется во временный `.part`, готовый — переименовывается. Брошенный на
/// середине (перемотали, закрыли) — удаляется.
pub struct Writer {
  part: PathBuf,
  audio: PathBuf,
  mime_path: PathBuf,
  mime: String,
  file: Option<File>,
  written: u64,
  expect: Option<u64>,
  done: bool,
}

impl Writer {
  /// `expect` — ожидаемый размер (Content-Length), если известен.
  pub fn new(track_ref: &str, mime: &str, expect: Option<u64>) -> Option<Self> {
    if !enabled() {
      return None;
    }
    let dir = DIR.get()?;
    let (audio, mime_path) = paths(dir, track_ref);
    if audio.exists() {
      return None;
    }
    let part = dir.join(format!("{}.{}.part", key(track_ref), std::process::id()));
    let file = File::create(&part).ok()?;
    Some(Self { part, audio, mime_path, mime: mime.to_owned(), file: Some(file), written: 0, expect, done: false })
  }

  pub fn write(&mut self, chunk: &[u8]) {
    let ok = self.file.as_mut().is_some_and(|f| f.write_all(chunk).is_ok());
    if !ok {
      self.file = None;
    }
    self.written += chunk.len() as u64;
  }

  /// Всё записано: проверить размер, переименовать, вытеснить лишнее.
  pub fn finish(mut self) {
    let Some(f) = self.file.take() else { return };
    drop(f);
    if self.written == 0 || self.expect.is_some_and(|n| n != self.written) {
      return;
    }
    if fs::rename(&self.part, &self.audio).is_ok() {
      let _ = fs::write(&self.mime_path, &self.mime);
      self.done = true;
      evict();
    }
  }
}

impl Drop for Writer {
  fn drop(&mut self) {
    if !self.done {
      self.file = None;
      let _ = fs::remove_file(&self.part);
    }
  }
}

/// Взять трек «в работу» (HLS качается один раз); false — уже качается или уже в кэше.
pub fn claim(track_ref: &str) -> bool {
  if lookup(track_ref).is_some() {
    return false;
  }
  let mut g = BUSY.lock().unwrap();
  g.get_or_insert_with(HashSet::new).insert(track_ref.to_owned())
}

pub fn release(track_ref: &str) {
  if let Some(s) = BUSY.lock().unwrap().as_mut() {
    s.remove(track_ref);
  }
}

/// Файлы кэша: (путь, размер, время изменения).
fn entries(dir: &Path) -> Vec<(PathBuf, u64, SystemTime)> {
  let mut out = Vec::new();
  if let Ok(rd) = fs::read_dir(dir) {
    for e in rd.flatten() {
      let p = e.path();
      if p.extension().is_some_and(|x| x == "audio") {
        if let Ok(m) = e.metadata() {
          out.push((p, m.len(), m.modified().unwrap_or(SystemTime::UNIX_EPOCH)));
        }
      }
    }
  }
  out
}

/// Вытеснить давно не игравшие, пока кэш больше лимита.
pub fn evict() {
  let Some(dir) = DIR.get() else { return };
  evict_in(dir, LIMIT.load(Ordering::Relaxed));
}

pub fn evict_in(dir: &Path, limit: u64) {
  let mut list = entries(dir);
  let mut total: u64 = list.iter().map(|e| e.1).sum();
  list.sort_by_key(|e| e.2);
  for (p, len, _) in list {
    if total <= limit {
      break;
    }
    let _ = fs::remove_file(&p);
    let _ = fs::remove_file(p.with_extension("mime"));
    total = total.saturating_sub(len);
  }
}

/// Сколько треков и байт в кэше.
pub fn usage() -> (u64, u64) {
  let Some(dir) = DIR.get() else { return (0, 0) };
  let list = entries(dir);
  (list.len() as u64, list.iter().map(|e| e.1).sum())
}

pub fn clear() {
  let Some(dir) = DIR.get() else { return };
  if let Ok(rd) = fs::read_dir(dir) {
    for e in rd.flatten() {
      let _ = fs::remove_file(e.path());
    }
  }
}

/// Список кусков HLS для склейки: (init-кусок или None, куски, тип). MPEG-TS — None (не склеиваем).
pub fn hls_parts(playlist: &str, base: &url::Url) -> Option<(Option<String>, Vec<String>, &'static str)> {
  let mut init = None;
  let mut segs = Vec::new();
  for line in playlist.lines().map(str::trim) {
    // зашифрованные куски (HLS VK, AES-128) склейкой не сохранить — такой трек не кэшируем
    if line.starts_with("#EXT-X-KEY:") && !line.contains("METHOD=NONE") {
      return None;
    }
    if let Some(rest) = line.strip_prefix("#EXT-X-MAP:") {
      let uri = rest.split("URI=\"").nth(1)?.split('"').next()?;
      init = Some(base.join(uri).ok()?.to_string());
    } else if !line.is_empty() && !line.starts_with('#') {
      segs.push(base.join(line).ok()?.to_string());
    }
  }
  if segs.is_empty() {
    return None;
  }
  let first = segs[0].split('?').next().unwrap_or("").to_ascii_lowercase();
  let mime = if init.is_some() || first.ends_with(".m4s") || first.ends_with(".mp4") {
    "audio/mp4"
  } else if first.ends_with(".mp3") {
    "audio/mpeg"
  } else {
    return None;
  };
  Some((init, segs, mime))
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn ranges() {
    assert_eq!(parse_range(Some("bytes=0-"), 100), Some((0, 99)));
    assert_eq!(parse_range(Some("bytes=10-19"), 100), Some((10, 19)));
    assert_eq!(parse_range(Some("bytes=90-500"), 100), Some((90, 99)));
    assert_eq!(parse_range(Some("bytes=-10"), 100), Some((90, 99)));
    assert_eq!(parse_range(Some("bytes=200-"), 100), None);
    assert_eq!(parse_range(None, 100), None);
  }

  #[test]
  fn hls_parts_fmp4_mp3_ts() {
    let base = url::Url::parse("https://cf-hls.sndcdn.com/playlist/abc/").unwrap();
    let mp4 = "#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:10,\nseg1.m4s\n#EXTINF:10,\nseg2.m4s\n";
    let (init, segs, mime) = hls_parts(mp4, &base).unwrap();
    assert_eq!(init.as_deref(), Some("https://cf-hls.sndcdn.com/playlist/abc/init.mp4"));
    assert_eq!(segs.len(), 2);
    assert_eq!(mime, "audio/mp4");
    let mp3 = "#EXTM3U\n#EXTINF:10,\nhttps://x.sndcdn.com/a.mp3?x=1\n";
    assert_eq!(hls_parts(mp3, &base).unwrap().2, "audio/mpeg");
    assert!(hls_parts("#EXTM3U\n#EXTINF:10,\nseg.ts\n", &base).is_none());
  }

  #[test]
  fn hls_parts_skips_encrypted() {
    let base = url::Url::parse("https://cs1.vkuseraudio.net/s/v1/ac/x/").unwrap();
    let aes = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.pub\"\n#EXTINF:5,\nseg1.mp3\n";
    assert!(hls_parts(aes, &base).is_none());
    let plain = "#EXTM3U\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:5,\nseg1.mp3\n";
    assert_eq!(hls_parts(plain, &base).unwrap().2, "audio/mpeg");
  }

  #[test]
  fn writer_finish_and_evict() {
    let dir = std::env::temp_dir().join(format!("sonar-tc-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    // ручная запись без глобальных настроек: проверяем вытеснение по времени
    for (i, name) in ["a", "b", "c"].iter().enumerate() {
      let p = dir.join(format!("{name}.audio"));
      fs::write(&p, vec![0u8; 100]).unwrap();
      let t = SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(1_000 + i as u64);
      File::options().write(true).open(&p).unwrap().set_modified(t).unwrap();
    }
    evict_in(&dir, 200);
    assert!(!dir.join("a.audio").exists(), "самый старый вытеснен");
    assert!(dir.join("b.audio").exists() && dir.join("c.audio").exists());
    let _ = fs::remove_dir_all(&dir);
    assert_eq!(key("sc:12/3"), "sc_12_3");
  }
}
