//! Кэш треков на диске (Система → Хранилище → «Кеширование треков»): локальный аудио-сервер
//! (`stream.rs`) складывает прослушанные потоки в `<кэш>/tracks` и в следующий раз отдаёт их с диска —
//! без сети и протухших ссылок. Кэшируются **байты**, не ссылки: файл (mp3 / FLAC) — по мере
//! проигрывания, если он прочитан с начала до конца; HLS SoundCloud — отдельной загрузкой всех кусков,
//! склеенных в один файл (fMP4 с init-куском или mp3; MPEG-TS не склеиваем — `<audio>` его не играет).
//! Лимит — по размеру, вытесняются давно не игравшие (время изменения файла обновляется при чтении).
//!
//! Скачанное руками («Скачать», `downloads.rs`, `docs/OFFLINE.md` §8) лежит рядом, в `<кэш>/pinned`:
//! тот же формат файлов, но без лимита и вытеснения, «Очистить кэш» его не трогает. Скачан — играет
//! оттуда, копия в автокэше не нужна и не пишется.
//!
//! Временные файлы сведения (`<кэш>/blend-tmp`, `blend.rs`, `docs/BLEND.md` §4.1): трек для анализа, когда
//! автокэш выключен. Индекс и лимит их не видят; удаляются после анализа и при запуске.

use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::SystemTime;

static DIR: OnceLock<PathBuf> = OnceLock::new();
/// Скачанное руками: `<кэш>/pinned` (обложки — `pinned/covers`).
static PINNED: OnceLock<PathBuf> = OnceLock::new();
/// Временные файлы для анализа сведения: `<кэш>/blend-tmp`.
static BLEND: OnceLock<PathBuf> = OnceLock::new();
static ENABLED: AtomicBool = AtomicBool::new(false);
/// Лимит кэша в байтах (по умолчанию 2 ГБ).
static LIMIT: AtomicU64 = AtomicU64::new(2 * 1024 * 1024 * 1024);
/// Треки, которые сейчас скачиваются (HLS) — не качать дважды.
static BUSY: Mutex<Option<HashSet<String>>> = Mutex::new(None);

/// Что поменялось на диске — для офлайн-индекса (`offline_index.rs`, `docs/OFFLINE.md` §7.1).
/// `pinned` — скачанное руками, иначе автокэш.
pub enum Change {
  /// Трек лёг целиком: ref, имя файла, тип, размер.
  Added { track_ref: String, file: String, mime: String, bytes: u64, pinned: bool },
  /// Файл вытеснен или удалён (имя файла).
  Removed { file: String, pinned: bool },
  /// Папка очищена.
  Cleared { pinned: bool },
}

static HOOK: OnceLock<Box<dyn Fn(Change) + Send + Sync>> = OnceLock::new();

/// Подписка на изменения кэша (одна, ставится при запуске).
pub fn on_change(f: impl Fn(Change) + Send + Sync + 'static) {
  let _ = HOOK.set(Box::new(f));
}

fn notify(c: Change) {
  if let Some(f) = HOOK.get() {
    f(c);
  }
}

fn dir_of(pinned: bool) -> Option<&'static PathBuf> {
  if pinned { PINNED.get() } else { DIR.get() }
}

/// Готовые файлы по имени: (размер, тип) — для сверки индекса при запуске.
pub fn disk_files(pinned: bool) -> HashMap<String, (u64, String)> {
  let Some(dir) = dir_of(pinned) else { return HashMap::new() };
  entries(dir)
    .into_iter()
    .filter_map(|(p, len, _)| {
      let name = p.file_name()?.to_string_lossy().into_owned();
      let mime = fs::read_to_string(p.with_extension("mime")).unwrap_or_else(|_| "audio/mpeg".into());
      Some((name, (len, mime.trim().to_owned())))
    })
    .collect()
}

/// Создать папку и убрать недописанные файлы прошлого запуска.
fn prepare(dir: &Path) {
  let _ = fs::create_dir_all(dir);
  if let Ok(rd) = fs::read_dir(dir) {
    for e in rd.flatten() {
      if e.path().extension().is_some_and(|x| x == "part") {
        let _ = fs::remove_file(e.path());
      }
    }
  }
}

pub fn set_dir(dir: PathBuf) {
  prepare(&dir);
  let _ = DIR.set(dir);
}

/// Папка скачанного (`<кэш>/pinned`) и её обложек.
pub fn set_pinned_dir(dir: PathBuf) {
  prepare(&dir);
  let _ = fs::create_dir_all(dir.join("covers"));
  let _ = PINNED.set(dir);
}

/// Папка временных файлов сведения: при запуске пустая (прошлые — мусор).
pub fn set_blend_dir(dir: PathBuf) {
  let _ = fs::create_dir_all(&dir);
  remove_files(&dir);
  let _ = BLEND.set(dir);
}

/// Временный файл сведения: путь, тип, размер.
pub fn blend_lookup(track_ref: &str) -> Option<(PathBuf, String, u64)> {
  found(BLEND.get()?, track_ref)
}

/// Удалить временный файл сведения (анализ готов).
pub fn blend_drop(track_ref: &str) {
  let Some(dir) = BLEND.get() else { return };
  let (audio, mime) = paths(dir, track_ref);
  let _ = fs::remove_file(audio);
  let _ = fs::remove_file(mime);
}

pub fn pinned_dir() -> Option<&'static PathBuf> {
  PINNED.get()
}

/// Обложки скачанного: `/cover` ищет здесь, если в общем кэше обложек файла нет.
pub fn pinned_covers_dir() -> Option<PathBuf> {
  PINNED.get().map(|d| d.join("covers"))
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

fn found(dir: &Path, track_ref: &str) -> Option<(PathBuf, String, u64)> {
  let (audio, mime) = paths(dir, track_ref);
  let len = fs::metadata(&audio).ok()?.len();
  if len == 0 {
    return None;
  }
  let mime = fs::read_to_string(mime).unwrap_or_else(|_| "audio/mpeg".into());
  Some((audio, mime.trim().to_owned(), len))
}

/// Трек на диске (сначала скачанное, потом автокэш): путь, тип и размер. Чтение из автокэша освежает
/// «время последнего использования».
pub fn lookup(track_ref: &str) -> Option<(PathBuf, String, u64)> {
  if let Some(hit) = PINNED.get().and_then(|d| found(d, track_ref)) {
    return Some(hit);
  }
  let hit = found(DIR.get()?, track_ref)?;
  if let Ok(f) = File::options().write(true).open(&hit.0) {
    let _ = f.set_modified(SystemTime::now());
  }
  Some(hit)
}

/// Трек скачан руками.
pub fn is_pinned(track_ref: &str) -> bool {
  PINNED.get().is_some_and(|d| found(d, track_ref).is_some())
}

/// Перенести копию из автокэша в скачанное (без сети). false — в автокэше трека нет.
pub fn pin(track_ref: &str) -> bool {
  let (Some(cache), Some(pinned)) = (DIR.get(), PINNED.get()) else { return false };
  let (from_audio, from_mime) = paths(cache, track_ref);
  let (to_audio, to_mime) = paths(pinned, track_ref);
  let Ok(bytes) = fs::metadata(&from_audio).map(|m| m.len()) else { return false };
  if bytes == 0 {
    return false;
  }
  let mime = fs::read_to_string(&from_mime).map(|m| m.trim().to_owned()).unwrap_or_else(|_| "audio/mpeg".into());
  if fs::rename(&from_audio, &to_audio).is_err() {
    return false;
  }
  let _ = fs::write(&to_mime, &mime);
  let _ = fs::remove_file(&from_mime);
  let file = file_name(&to_audio);
  notify(Change::Added { track_ref: track_ref.to_owned(), file, mime, bytes, pinned: true });
  true
}

/// Убрать из скачанного (файл удаляется).
pub fn unpin(track_ref: &str) {
  let Some(dir) = PINNED.get() else { return };
  let (audio, mime) = paths(dir, track_ref);
  if fs::remove_file(&audio).is_ok() {
    notify(Change::Removed { file: file_name(&audio), pinned: true });
  }
  let _ = fs::remove_file(mime);
}

/// Убрать копию трека из автокэша («Играть из» сменили — там звук прежнего сервиса). Скачанное руками
/// не трогаем: его пользователь удаляет сам.
pub fn forget(track_ref: &str) {
  let Some(dir) = DIR.get() else { return };
  let (audio, mime) = paths(dir, track_ref);
  if fs::remove_file(&audio).is_ok() {
    notify(Change::Removed { file: file_name(&audio), pinned: false });
  }
  let _ = fs::remove_file(mime);
}

fn file_name(p: &Path) -> String {
  p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
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
  track_ref: String,
  pinned: bool,
  /// Временный файл сведения: мимо индекса и лимита.
  temp: bool,
  /// Предел размера: больше — файл бросается.
  cap: Option<u64>,
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
  /// В автокэш. `expect` — ожидаемый размер (Content-Length), если известен. Трек уже скачан — None.
  pub fn new(track_ref: &str, mime: &str, expect: Option<u64>) -> Option<Self> {
    if !enabled() || is_pinned(track_ref) {
      return None;
    }
    Self::open(DIR.get()?, false, track_ref, mime, expect)
  }

  /// В скачанное (без лимита, автокэш может быть выключен).
  pub fn pinned(track_ref: &str, mime: &str, expect: Option<u64>) -> Option<Self> {
    Self::open(PINNED.get()?, true, track_ref, mime, expect)
  }

  /// Во временные файлы сведения (`<кэш>/blend-tmp`).
  pub fn blend(track_ref: &str, mime: &str, expect: Option<u64>) -> Option<Self> {
    let mut w = Self::open(BLEND.get()?, false, track_ref, mime, expect)?;
    w.temp = true;
    Some(w)
  }

  /// Не больше `bytes`: файл крупнее бросается (Content-Length больше — сразу).
  pub fn capped(mut self, bytes: u64) -> Option<Self> {
    if self.expect.is_some_and(|n| n > bytes) {
      return None;
    }
    self.cap = Some(bytes);
    Some(self)
  }

  /// Записано больше предела — дальше качать незачем.
  pub fn over_cap(&self) -> bool {
    self.cap.is_some_and(|c| self.written > c)
  }

  fn open(dir: &Path, pinned: bool, track_ref: &str, mime: &str, expect: Option<u64>) -> Option<Self> {
    let (audio, mime_path) = paths(dir, track_ref);
    if audio.exists() {
      return None;
    }
    // разные части на процесс и на запись: скачивание и проигрывание могут писать одно и то же
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let n = SEQ.fetch_add(1, Ordering::Relaxed);
    let part = dir.join(format!("{}.{}-{n}.part", key(track_ref), std::process::id()));
    let file = File::create(&part).ok()?;
    let track_ref = track_ref.to_owned();
    Some(Self { track_ref, pinned, temp: false, cap: None, part, audio, mime_path, mime: mime.to_owned(), file: Some(file), written: 0, expect, done: false })
  }

  pub fn write(&mut self, chunk: &[u8]) {
    let ok = self.file.as_mut().is_some_and(|f| f.write_all(chunk).is_ok());
    self.written += chunk.len() as u64;
    if !ok || self.over_cap() {
      self.file = None;
    }
  }

  /// Всё записано: проверить размер, переименовать, вытеснить лишнее. true — файл на месте.
  pub fn finish(mut self) -> bool {
    let Some(f) = self.file.take() else { return false };
    drop(f);
    if self.written == 0 || self.expect.is_some_and(|n| n != self.written) {
      return false;
    }
    // пока писался в автокэш, трек скачали — копия не нужна
    if !self.pinned && is_pinned(&self.track_ref) {
      return false;
    }
    if fs::rename(&self.part, &self.audio).is_err() {
      return false;
    }
    let _ = fs::write(&self.mime_path, &self.mime);
    self.done = true;
    if self.temp {
      return true;
    }
    let (track_ref, mime) = (std::mem::take(&mut self.track_ref), std::mem::take(&mut self.mime));
    let pinned = self.pinned;
    notify(Change::Added { track_ref: track_ref.clone(), file: file_name(&self.audio), mime, bytes: self.written, pinned });
    if pinned {
      drop_cached(&track_ref);
    } else {
      evict();
    }
    true
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

/// Копия в автокэше рядом со скачанным — лишняя.
fn drop_cached(track_ref: &str) {
  let Some(dir) = DIR.get() else { return };
  let (audio, mime) = paths(dir, track_ref);
  if fs::remove_file(&audio).is_ok() {
    notify(Change::Removed { file: file_name(&audio), pinned: false });
  }
  let _ = fs::remove_file(mime);
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
    notify(Change::Removed { file: file_name(&p), pinned: false });
    total = total.saturating_sub(len);
  }
}

/// Сколько треков и байт: в автокэше (`pinned` = false) или в скачанном.
pub fn usage(pinned: bool) -> (u64, u64) {
  let Some(dir) = dir_of(pinned) else { return (0, 0) };
  let list = entries(dir);
  (list.len() as u64, list.iter().map(|e| e.1).sum())
}

/// Очистить автокэш. Скачанное не трогает.
pub fn clear() {
  let Some(dir) = DIR.get() else { return };
  remove_files(dir);
  notify(Change::Cleared { pinned: false });
}

/// Удалить всё скачанное (с обложками).
pub fn clear_pinned() {
  let Some(dir) = PINNED.get() else { return };
  remove_files(dir);
  remove_files(&dir.join("covers"));
  notify(Change::Cleared { pinned: true });
}

fn remove_files(dir: &Path) {
  if let Ok(rd) = fs::read_dir(dir) {
    for e in rd.flatten().filter(|e| e.path().is_file()) {
      let _ = fs::remove_file(e.path());
    }
  }
}

/// Список кусков HLS для склейки: (init-кусок или None, куски, тип). MPEG-TS — None (не склеиваем).
pub fn hls_parts(playlist: &str, base: &url::Url) -> Option<(Option<String>, Vec<String>, &'static str)> {
  let mut init = None;
  let mut segs = Vec::new();
  for line in playlist.lines().map(str::trim) {
    // зашифрованные куски (AES-128) склейкой не сохранить — такой трек не кэшируем
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
    let base = url::Url::parse("https://cf-hls-media.sndcdn.com/x/").unwrap();
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

  /// Папка сведения — один раз на процесс (OnceLock), поэтому все проверки — в одном тесте.
  #[test]
  fn blend_temp_files() {
    let dir = std::env::temp_dir().join(format!("sonar-blend-test-{}", std::process::id()));
    let _ = fs::create_dir_all(&dir);
    fs::write(dir.join("old.audio"), b"x").unwrap();
    set_blend_dir(dir.clone());
    assert!(!dir.join("old.audio").exists(), "остатки прошлого запуска удалены");

    let mut w = Writer::blend("sc:1", "audio/mpeg", None).unwrap();
    w.write(b"abc");
    assert!(w.finish());
    let (path, mime, len) = blend_lookup("sc:1").unwrap();
    assert_eq!((mime.as_str(), len), ("audio/mpeg", 3));
    assert!(path.starts_with(&dir));
    blend_drop("sc:1");
    assert!(blend_lookup("sc:1").is_none());

    assert!(Writer::blend("sc:2", "audio/mpeg", Some(100)).unwrap().capped(10).is_none(), "заявлен больше предела");
    let mut w = Writer::blend("sc:2", "audio/mpeg", None).unwrap().capped(4).unwrap();
    w.write(b"abc");
    assert!(!w.over_cap());
    w.write(b"de");
    assert!(w.over_cap());
    assert!(!w.finish());
    assert!(blend_lookup("sc:2").is_none());
    assert_eq!(fs::read_dir(&dir).unwrap().count(), 0, "недописанный .part удалён");
    let _ = fs::remove_dir_all(&dir);
  }
}
