//! «Скачать» (`docs/OFFLINE.md` §8.1–8.2): очередь скачивания на ПК. Трек ложится в `<кэш>/pinned`
//! (`track_cache`), не вытесняется и играет в офлайне; к нему — обложка (`stream::pin_cover`) и текст
//! (`lyrics_cache`, чистка его не трогает). Качает по `PARALLEL` штук; пауза, офлайн-режим и отмена обрывают
//! начатое, и оно встаёт в начало очереди. Очередь живёт до закрытия Sonar.
use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, LazyLock, Mutex, MutexGuard};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State};

use crate::commands::Db;
use crate::providers::Track;
use crate::services::Core;
use crate::stream::FetchErr;
use crate::track_cache;

/// Событие для интерфейса: состояние очереди (`Snapshot`).
pub const EVENT: &str = "downloads-changed";
/// Сколько треков качается одновременно.
const PARALLEL: usize = 2;

type Res<T> = Result<T, String>;

/// Состояние трека в очереди. Скачанный из очереди уходит — его видно по `offline_tracks`.
#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum Job {
  Queued,
  Active,
  Failed { error: String },
  /// MPEG-TS или зашифрованный HLS — такой поток не сохранить.
  Unsupported,
}

/// Чем закончилась загрузка трека.
#[derive(Debug, PartialEq)]
enum Outcome {
  Done,
  /// Оборвали паузой, офлайном или отменой.
  Stopped,
  Unsupported,
  Failed(String),
}

/// Очередь без Tauri — чтобы гонять тестами.
#[derive(Default)]
struct Queue {
  order: VecDeque<String>,
  jobs: HashMap<String, (Track, Job)>,
  active: usize,
  paused: bool,
  /// Скачано в текущей пачке (обнуляется, когда очередь опустела и пришла новая пачка).
  done: u64,
}

/// Что видит интерфейс.
#[derive(Clone, Debug, Serialize)]
pub struct Snapshot {
  paused: bool,
  done: u64,
  /// Ещё в работе: в очереди и качается.
  left: u64,
  jobs: HashMap<String, Job>,
}

impl Queue {
  fn busy(&self) -> bool {
    self.jobs.values().any(|(_, j)| matches!(j, Job::Queued | Job::Active))
  }

  /// Поставить в очередь. Уже стоящее и качающееся — мимо; упавшее — заново. Возвращает, сколько добавлено.
  fn add(&mut self, tracks: Vec<Track>) -> usize {
    if !self.busy() {
      self.done = 0;
    }
    let mut n = 0;
    for t in tracks {
      if matches!(self.jobs.get(&t.ref_), Some((_, Job::Queued | Job::Active))) {
        continue;
      }
      self.order.push_back(t.ref_.clone());
      self.jobs.insert(t.ref_.clone(), (t, Job::Queued));
      n += 1;
    }
    n
  }

  /// Следующий трек в работу, если есть место и не пауза.
  fn take(&mut self, offline: bool) -> Option<Track> {
    if self.paused || offline || self.active >= PARALLEL {
      return None;
    }
    while let Some(r) = self.order.pop_front() {
      if let Some((t, job @ Job::Queued)) = self.jobs.get_mut(&r) {
        *job = Job::Active;
        self.active += 1;
        return Some(t.clone());
      }
    }
    None
  }

  /// Продолжать ли качать трек: его не отменили, не пауза.
  fn keeps(&self, track_ref: &str) -> bool {
    !self.paused && matches!(self.jobs.get(track_ref), Some((_, Job::Active)))
  }

  fn finish(&mut self, track_ref: &str, outcome: Outcome) {
    self.active = self.active.saturating_sub(1);
    // отменили, пока качалось, — строки уже нет (или трек поставили заново, тогда он ждёт своей очереди)
    let Some((_, job)) = self.jobs.get_mut(track_ref) else { return };
    if *job != Job::Active {
      return;
    }
    match outcome {
      Outcome::Done => {
        self.jobs.remove(track_ref);
        self.done += 1;
      }
      Outcome::Stopped => {
        *job = Job::Queued;
        self.order.push_front(track_ref.to_owned());
      }
      Outcome::Unsupported => *job = Job::Unsupported,
      Outcome::Failed(e) => *job = Job::Failed { error: e },
    }
  }

  /// Упавшие — снова в очередь (нескачиваемые — нет: повтор ничего не даст).
  fn retry(&mut self) {
    for (r, (_, job)) in self.jobs.iter_mut() {
      if matches!(job, Job::Failed { .. }) {
        *job = Job::Queued;
        self.order.push_back(r.clone());
      }
    }
  }

  fn cancel(&mut self, refs: &[String]) {
    for r in refs {
      self.jobs.remove(r);
    }
    let jobs = &self.jobs;
    self.order.retain(|r| jobs.contains_key(r));
  }

  fn snapshot(&self) -> Snapshot {
    Snapshot {
      paused: self.paused,
      done: self.done,
      left: self.jobs.values().filter(|(_, j)| matches!(j, Job::Queued | Job::Active)).count() as u64,
      jobs: self.jobs.iter().map(|(r, (_, j))| (r.clone(), j.clone())).collect(),
    }
  }
}

static QUEUE: LazyLock<Mutex<Queue>> = LazyLock::new(|| Mutex::new(Queue::default()));

fn queue() -> MutexGuard<'static, Queue> {
  QUEUE.lock().unwrap_or_else(|e| e.into_inner())
}

fn emit(app: &AppHandle) {
  let snap = queue().snapshot();
  if let Err(e) = app.emit(EVENT, snap) {
    log::warn!("скачивание: событие не ушло — {e}");
  }
}

/// Занять свободные места очереди. Зовётся после любого изменения и при выходе из офлайна.
pub fn pump(app: &AppHandle) {
  let started: Vec<Track> = {
    let mut q = queue();
    let offline = crate::offline::is_on();
    std::iter::from_fn(|| q.take(offline)).collect()
  };
  for t in started {
    tauri::async_runtime::spawn(run(app.clone(), t));
  }
  emit(app);
}

async fn run(app: AppHandle, track: Track) {
  let core = app.state::<Arc<Core>>().inner().clone();
  let outcome = download(&app, &core, &track).await;
  if let Outcome::Failed(e) = &outcome {
    log::warn!("скачивание: {} — {e}", track.ref_);
  }
  queue().finish(&track.ref_, outcome);
  pump(&app);
}

/// Пакет на трек: аудио (из автокэша, если там уже лежит), потом обложка и текст — они не обязательны.
async fn download(app: &AppHandle, core: &Core, track: &Track) -> Outcome {
  let r = track.ref_.as_str();
  if !track_cache::is_pinned(r) && !track_cache::pin(r) {
    let stop = || crate::offline::is_on() || !queue().keeps(r);
    match crate::stream::fetch_track(core, r, true, &stop).await {
      Ok(()) => {}
      Err(FetchErr::Stopped) => return Outcome::Stopped,
      Err(FetchErr::Unsupported) => return Outcome::Unsupported,
      // офлайн включили посреди куска — это не сбой, очередь продолжит сама
      Err(FetchErr::Failed(_)) if crate::offline::is_on() => return Outcome::Stopped,
      Err(FetchErr::Failed(e)) => return Outcome::Failed(e),
    }
  }
  if !queue().keeps(r) {
    return Outcome::Stopped;
  }
  if let Some(url) = &track.cover_url {
    if let Err(e) = crate::stream::pin_cover(core, url).await {
      log::info!("скачивание: обложка {r} — {e}");
    }
  }
  if let Err(e) = pin_lyrics(app, core, track).await {
    log::info!("скачивание: текст {r} — {e}");
  }
  // без сети обложка и текст могли не прийти — повтор после офлайна доберёт их, аудио уже на месте
  if crate::offline::is_on() {
    return Outcome::Stopped;
  }
  Outcome::Done
}

/// Текст в кэш, если его там нет. «Текста нет» тоже запоминается — в офлайне не будет вечного поиска.
async fn pin_lyrics(app: &AppHandle, core: &Core, track: &Track) -> anyhow::Result<()> {
  let cached = app.state::<Db>().0.lock().unwrap().lyrics_cached(&track.ref_)?;
  if cached.is_some() {
    return Ok(());
  }
  let found = crate::lyrics::fetch_track(&core.http(), track, false).await?;
  let json = found.as_ref().map(serde_json::to_string).transpose()?;
  app.state::<Db>().0.lock().unwrap().put_lyrics(&track.ref_, json.as_deref(), found.as_ref().map(|l| l.source.as_str()))?;
  Ok(())
}

fn err(e: impl std::fmt::Display) -> String {
  e.to_string()
}

/// «Скачать»: трек, плейлист, Любимые, альбом. Локальные и уже скачанные — мимо. Возвращает, сколько встало в очередь.
#[tauri::command]
pub fn download_tracks(app: AppHandle, db: State<'_, Db>, tracks: Vec<Track>) -> Res<usize> {
  let tracks: Vec<Track> =
    tracks.into_iter().filter(|t| !crate::local::is_local_ref(&t.ref_) && !track_cache::is_pinned(&t.ref_)).collect();
  // снимок трека — в `tracks`: по нему офлайн-индекс покажет название без сети
  db.0.lock().unwrap().upsert_tracks(&tracks).map_err(err)?;
  let n = queue().add(tracks);
  pump(&app);
  Ok(n)
}

#[tauri::command]
pub fn downloads_state() -> Snapshot {
  queue().snapshot()
}

/// Скачанные треки (ref).
#[tauri::command]
pub fn downloaded_refs(db: State<'_, Db>) -> Res<Vec<String>> {
  db.0.lock().unwrap().offline_pinned_refs().map_err(err)
}

#[tauri::command]
pub fn downloads_pause(app: AppHandle, paused: bool) {
  queue().paused = paused;
  pump(&app);
}

#[tauri::command]
pub fn downloads_retry(app: AppHandle) {
  queue().retry();
  pump(&app);
}

/// Убрать из очереди (качающиеся обрываются).
#[tauri::command]
pub fn downloads_cancel(app: AppHandle, refs: Vec<String>) {
  queue().cancel(&refs);
  pump(&app);
}

/// Удалить из скачанного (и из очереди).
#[tauri::command]
pub fn downloads_remove(app: AppHandle, refs: Vec<String>) {
  queue().cancel(&refs);
  for r in &refs {
    track_cache::unpin(r);
  }
  pump(&app);
}

/// «Удалить все»: очередь и всё скачанное с обложками. Тексты остаются обычным кэшем.
#[tauri::command]
pub fn downloads_clear(app: AppHandle) {
  {
    let mut q = queue();
    let all: Vec<String> = q.jobs.keys().cloned().collect();
    q.cancel(&all);
  }
  track_cache::clear_pinned();
  pump(&app);
}

/// «Показать в папке».
#[tauri::command]
pub fn downloads_reveal() -> Res<()> {
  let dir = track_cache::pinned_dir().ok_or("папки скачанного нет")?;
  std::process::Command::new("explorer").arg(dir).spawn().map_err(err)?;
  Ok(())
}

/// Свободное место на диске со скачанным, байт. Не узнали — `None` (окно пачки покажет без него).
#[tauri::command]
pub fn disk_free() -> Option<u64> {
  free_bytes(track_cache::pinned_dir()?)
}

#[cfg(windows)]
fn free_bytes(dir: &std::path::Path) -> Option<u64> {
  use std::os::windows::ffi::OsStrExt;
  use windows::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;
  use windows::core::PCWSTR;
  let wide: Vec<u16> = dir.as_os_str().encode_wide().chain(std::iter::once(0)).collect();
  let mut free = 0u64;
  // SAFETY: строка с нулём на конце живёт до конца вызова, `free` — локальная переменная
  unsafe { GetDiskFreeSpaceExW(PCWSTR(wide.as_ptr()), Some(&raw mut free), None, None) }.ok()?;
  Some(free)
}

#[cfg(not(windows))]
fn free_bytes(_dir: &std::path::Path) -> Option<u64> {
  None
}

#[cfg(test)]
mod tests {
  use super::*;

  fn tr(r: &str) -> Track {
    Track {
      ref_: r.into(),
      title: r.into(),
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

  fn take_all(q: &mut Queue) -> Vec<String> {
    std::iter::from_fn(|| q.take(false)).map(|t| t.ref_).collect()
  }

  #[test]
  fn runs_two_at_a_time_in_order() {
    let mut q = Queue::default();
    assert_eq!(q.add(vec![tr("a"), tr("b"), tr("c"), tr("a")]), 3);
    assert_eq!(take_all(&mut q), ["a", "b"]);
    q.finish("a", Outcome::Done);
    assert_eq!(take_all(&mut q), ["c"]);
    assert_eq!(q.snapshot().done, 1);
    assert_eq!(q.snapshot().left, 2);
  }

  #[test]
  fn pause_and_offline_hold_the_queue() {
    let mut q = Queue::default();
    q.add(vec![tr("a")]);
    assert!(q.take(true).is_none());
    q.paused = true;
    assert!(q.take(false).is_none());
    q.paused = false;
    assert_eq!(take_all(&mut q), ["a"]);
  }

  #[test]
  fn stopped_track_goes_back_to_the_front() {
    let mut q = Queue::default();
    q.add(vec![tr("a"), tr("b"), tr("c")]);
    take_all(&mut q);
    q.paused = true;
    assert!(!q.keeps("a"));
    q.finish("a", Outcome::Stopped);
    q.paused = false;
    assert_eq!(take_all(&mut q), ["a"]);
  }

  #[test]
  fn failed_is_retried_unsupported_is_not() {
    let mut q = Queue::default();
    q.add(vec![tr("a"), tr("b")]);
    take_all(&mut q);
    q.finish("a", Outcome::Failed("сеть".into()));
    q.finish("b", Outcome::Unsupported);
    assert_eq!(q.snapshot().left, 0);
    q.retry();
    assert_eq!(take_all(&mut q), ["a"]);
    assert_eq!(q.snapshot().jobs.get("b"), Some(&Job::Unsupported));
  }

  #[test]
  fn cancel_stops_active_and_drops_queued() {
    let mut q = Queue::default();
    q.add(vec![tr("a"), tr("b"), tr("c")]);
    take_all(&mut q);
    q.cancel(&["a".into(), "c".into()]);
    assert!(!q.keeps("a"));
    q.finish("a", Outcome::Done);
    assert_eq!(q.snapshot().done, 0);
    assert!(take_all(&mut q).is_empty());
    assert_eq!(q.snapshot().left, 1);
  }

  #[test]
  fn new_batch_after_idle_resets_progress() {
    let mut q = Queue::default();
    q.add(vec![tr("a")]);
    take_all(&mut q);
    q.finish("a", Outcome::Done);
    q.add(vec![tr("b")]);
    assert_eq!(q.snapshot().done, 0);
  }
}
