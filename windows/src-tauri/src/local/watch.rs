//! Слежка за папками с музыкой (`notify`): добавили, удалили, переименовали файл — через
//! пару секунд тишины пересканировать. Пачка событий (копируют альбом) — один скан.

use notify::event::ModifyKind;
use notify::{Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{channel, RecvTimeoutError};
use std::time::Duration;

/// Событие про музыку: не чтение и не смена атрибутов; путь — аудиофайл или папка (у удалённой
/// папки уже не узнать, что она папка, поэтому «без расширения» тоже считаем).
fn relevant(e: &Event) -> bool {
  if matches!(e.kind, EventKind::Access(_) | EventKind::Modify(ModifyKind::Metadata(_))) {
    return false;
  }
  e.paths.is_empty() || e.paths.iter().any(|p| super::is_audio(p) || p.is_dir() || p.extension().is_none())
}

/// Следить за папками; `on_change` зовётся из своего потока после `debounce` тишины. Поток живёт,
/// пока жив возвращённый watcher (уронили — отправитель закрылся, поток вышел). Папок, которых нет,
/// не видно — их строки и так серые до следующего скана.
pub fn start(folders: &[PathBuf], debounce: Duration, on_change: impl Fn() + Send + 'static) -> Option<RecommendedWatcher> {
  let existing: Vec<&Path> = folders.iter().map(PathBuf::as_path).filter(|f| f.is_dir()).collect();
  if existing.is_empty() {
    return None;
  }
  let (tx, rx) = channel::<()>();
  let mut watcher = match notify::recommended_watcher(move |res: notify::Result<Event>| match res {
    Ok(e) if relevant(&e) => {
      let _ = tx.send(());
    }
    Ok(_) => {}
    Err(e) => log::warn!("[local] слежка за папками: {e}"),
  }) {
    Ok(w) => w,
    Err(e) => {
      log::warn!("[local] слежка за папками не запустилась: {e}");
      return None;
    }
  };
  for f in existing {
    if let Err(e) = watcher.watch(f, RecursiveMode::Recursive) {
      log::warn!("[local] не слежу за {}: {e}", f.display());
    }
  }
  std::thread::spawn(move || {
    while rx.recv().is_ok() {
      // ждём, пока события утихнут
      loop {
        match rx.recv_timeout(debounce) {
          Ok(()) => continue,
          Err(RecvTimeoutError::Timeout) => break,
          Err(RecvTimeoutError::Disconnected) => return,
        }
      }
      on_change();
    }
  });
  Some(watcher)
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::local::fixtures::{temp_dir, write_wav};
  use notify::event::{AccessKind, CreateKind, MetadataKind};
  use std::sync::atomic::{AtomicUsize, Ordering};
  use std::sync::Arc;
  use std::time::Instant;

  fn ev(kind: EventKind, path: &str) -> Event {
    Event::new(kind).add_path(PathBuf::from(path))
  }

  #[test]
  fn only_music_events_count() {
    assert!(relevant(&ev(EventKind::Create(CreateKind::File), "/m/a.mp3")));
    assert!(relevant(&ev(EventKind::Remove(notify::event::RemoveKind::Any), "/m/album")));
    assert!(!relevant(&ev(EventKind::Create(CreateKind::File), "/m/notes.txt")));
    assert!(!relevant(&ev(EventKind::Access(AccessKind::Any), "/m/a.mp3")));
    assert!(!relevant(&ev(EventKind::Modify(ModifyKind::Metadata(MetadataKind::Any)), "/m/a.mp3")));
  }

  #[test]
  fn no_existing_folders_no_watcher() {
    assert!(start(&[PathBuf::from("/definitely/not/here")], Duration::from_millis(10), || {}).is_none());
    assert!(start(&[], Duration::from_millis(10), || {}).is_none());
  }

  #[test]
  fn new_file_triggers_one_debounced_change() {
    let dir = temp_dir("watch");
    let hits = Arc::new(AtomicUsize::new(0));
    let h = hits.clone();
    let w = start(std::slice::from_ref(&dir), Duration::from_millis(400), move || {
      h.fetch_add(1, Ordering::SeqCst);
    });
    assert!(w.is_some());
    // FSEvents на macOS просыпается не сразу
    std::thread::sleep(Duration::from_millis(300));
    for i in 0..3 {
      write_wav(&dir.join(format!("{i}.wav")), 50);
    }
    let deadline = Instant::now() + Duration::from_secs(10);
    while hits.load(Ordering::SeqCst) == 0 && Instant::now() < deadline {
      std::thread::sleep(Duration::from_millis(50));
    }
    assert!(hits.load(Ordering::SeqCst) >= 1, "слежка не сработала");
    drop(w);
    let _ = std::fs::remove_dir_all(dir);
  }
}
