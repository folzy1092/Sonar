//! Команды «Папок с музыкой» (Система → Хранилище) и жизненный цикл индекса: при запуске индекс
//! берётся из базы, затем фоновый скан и слежка за папками; после каждого скана — событие
//! `local-files-changed` для интерфейса.

use super::{prune_covers, scan, watch, Index, Summary};
use crate::commands::Db;
use crate::providers::Track;
use crate::services::Core;
use crate::store::Store;
use anyhow::Result;
use notify::RecommendedWatcher;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager, State};

/// Ключ настройки со списком папок (docs/SETTINGS.md).
pub const FOLDERS_KEY: &str = "storage.music_folders";
/// Событие интерфейсу: индекс изменился (полезная нагрузка — `Summary`).
pub const CHANGED_EVENT: &str = "local-files-changed";
/// Тишина после событий файловой системы, прежде чем пересканировать.
const WATCH_DEBOUNCE: Duration = Duration::from_secs(2);
/// Больше результатов поиска по файлам не отдаём.
const MAX_SEARCH: usize = 100;

/// Сканы по очереди: слежка и кнопка «Пересканировать» не должны писать одновременно.
static SCAN: Mutex<()> = Mutex::new(());

/// Текущий watcher папок; заменить — старый уронится и перестанет следить.
pub struct LocalWatch(Mutex<Option<RecommendedWatcher>>);

/// Папки из настройки: строки, без пустых и повторов, в порядке добавления.
pub fn folders_of(store: &Store) -> Vec<PathBuf> {
  let list = store.setting(FOLDERS_KEY).ok().flatten();
  let mut out: Vec<PathBuf> = Vec::new();
  for s in list.as_ref().and_then(|v| v.as_array()).into_iter().flatten().filter_map(|v| v.as_str()) {
    let p = PathBuf::from(s.trim());
    if !s.trim().is_empty() && !out.contains(&p) {
      out.push(p);
    }
  }
  out
}

/// Скан и запись: папки и известное — под замком базы, сам скан (диск, теги) — без него.
/// Возвращает итог и было ли что менять.
fn rescan_store(db: &Mutex<Store>, index: &Index, cover_dir: Option<&Path>) -> Result<(Summary, bool)> {
  let _turn = SCAN.lock().unwrap_or_else(|e| e.into_inner());
  let (folders, known) = {
    let s = db.lock().unwrap_or_else(|e| e.into_inner());
    (folders_of(&s), s.local_files()?)
  };
  let r = scan(&folders, &known, cover_dir);
  let changed = !r.upserts.is_empty() || !r.removed.is_empty();
  let all = {
    let mut s = db.lock().unwrap_or_else(|e| e.into_inner());
    if changed {
      s.apply_local_scan(&r.upserts, &r.removed)?;
    }
    s.local_files()?
  };
  index.replace(&all);
  if let Some(d) = cover_dir {
    prune_covers(d, &all);
  }
  Ok((r.summary, changed))
}

pub fn rescan(app: &AppHandle) -> Result<Summary> {
  let core = app.state::<Arc<Core>>();
  let cover_dir = crate::stream::cover_dir().map(PathBuf::as_path);
  let (summary, changed) = rescan_store(&app.state::<Db>().0, &core.local, cover_dir)?;
  if changed {
    let _ = app.emit(CHANGED_EVENT, &summary);
  }
  Ok(summary)
}

/// Заново поставить слежку на текущий список папок.
fn restart_watch(app: &AppHandle) {
  let folders = folders_of(&app.state::<Db>().0.lock().unwrap_or_else(|e| e.into_inner()));
  let handle = app.clone();
  let watcher = watch::start(&folders, WATCH_DEBOUNCE, move || {
    if let Err(e) = rescan(&handle) {
      log::warn!("[local] пересканирование: {e}");
    }
  });
  if let Some(w) = app.try_state::<LocalWatch>() {
    *w.0.lock().unwrap_or_else(|e| e.into_inner()) = watcher;
  }
}

/// При запуске: индекс из базы сразу (играть можно до скана), потом скан и слежка в фоне.
pub fn init(app: &AppHandle) {
  let files = app.state::<Db>().0.lock().unwrap_or_else(|e| e.into_inner()).local_files();
  match files {
    Ok(files) => app.state::<Arc<Core>>().local.replace(&files),
    Err(e) => log::warn!("[local] индекс из базы: {e}"),
  }
  app.manage(LocalWatch(Mutex::new(None)));
  let app = app.clone();
  std::thread::spawn(move || {
    restart_watch(&app);
    if let Err(e) = rescan(&app) {
      log::warn!("[local] скан при запуске: {e}");
    }
  });
}

/// Выбор папки системным окном. Отмена — None.
#[tauri::command]
pub async fn local_pick_folder(app: AppHandle, title: String) -> Result<Option<String>, String> {
  use tauri_plugin_dialog::DialogExt;
  let (tx, rx) = tokio::sync::oneshot::channel();
  app.dialog().file().set_title(title).pick_folder(move |p| {
    let _ = tx.send(p);
  });
  let picked = rx.await.map_err(|e| e.to_string())?;
  Ok(picked.and_then(|p| p.into_path().ok()).map(|p| p.to_string_lossy().into_owned()))
}

/// Пересканировать папки из настройки и заново поставить слежку (после +/− в списке).
#[tauri::command]
pub async fn local_rescan(app: AppHandle) -> Result<Summary, String> {
  tauri::async_runtime::spawn_blocking(move || {
    restart_watch(&app);
    rescan(&app)
  })
  .await
  .map_err(|e| e.to_string())?
  .map_err(|e| e.to_string())
}

/// Все найденные файлы как треки; пропавшие — `available: false` («Файл не найден»).
#[tauri::command]
pub fn local_tracks(db: State<'_, Db>) -> Result<Vec<Track>, String> {
  let files = db.0.lock().unwrap_or_else(|e| e.into_inner()).local_files().map_err(|e| e.to_string())?;
  Ok(files.iter().map(|f| f.to_track(f.exists())).collect())
}

/// Поиск по файлам (название, исполнитель, альбом).
#[tauri::command]
pub fn local_search(db: State<'_, Db>, query: String, limit: Option<usize>) -> Result<Vec<Track>, String> {
  let limit = limit.unwrap_or(MAX_SEARCH).min(MAX_SEARCH);
  let files = db.0.lock().unwrap_or_else(|e| e.into_inner()).search_local(&query, limit).map_err(|e| e.to_string())?;
  Ok(files.iter().map(|f| f.to_track(f.exists())).collect())
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::local::fixtures::{tag_wav, temp_dir, write_wav, PNG};

  fn store_with(folders: &[&Path]) -> Mutex<Store> {
    let s = Store::memory().unwrap();
    let list: Vec<String> = folders.iter().map(|p| p.to_string_lossy().into_owned()).collect();
    s.set_setting(FOLDERS_KEY, &serde_json::json!(list)).unwrap();
    Mutex::new(s)
  }

  #[test]
  fn folders_setting_is_cleaned() {
    let s = Store::memory().unwrap();
    assert!(folders_of(&s).is_empty());
    s.set_setting(FOLDERS_KEY, &serde_json::json!(["/a", " ", "/b", "/a", 5])).unwrap();
    assert_eq!(folders_of(&s), [PathBuf::from("/a"), PathBuf::from("/b")]);
    s.set_setting(FOLDERS_KEY, &serde_json::json!("not a list")).unwrap();
    assert!(folders_of(&s).is_empty());
  }

  #[test]
  fn rescan_fills_db_index_and_tracks() {
    let music = temp_dir("cmd-music");
    let covers = temp_dir("cmd-covers");
    let a = music.join("a.wav");
    write_wav(&a, 300);
    tag_wav(&a, "Песня", "Группа", Some("Альбом"), Some(PNG));
    let db = store_with(&[&music]);
    let index = Index::default();

    let (sum, changed) = rescan_store(&db, &index, Some(&covers)).unwrap();
    assert!(changed);
    assert_eq!(sum, Summary { total: 1, added: 1, updated: 0, removed: 0 });
    let r = crate::local::local_ref(&a);
    assert_eq!(index.get(&r), Some(a.clone()));
    {
      let s = db.lock().unwrap();
      // обычный трек: лайк и плейлист видят его метаданные
      let t = &s.tracks(std::slice::from_ref(&r)).unwrap()[0];
      assert_eq!((t.title.as_str(), t.artist.as_str(), t.available), ("Песня", "Группа", true));
      assert_eq!(s.search_local("песня", 5).unwrap().len(), 1);
    }
    // второй скан — без изменений
    let (_, changed) = rescan_store(&db, &index, Some(&covers)).unwrap();
    assert!(!changed);

    // файл пропал — строка остаётся до скана, трек серый
    std::fs::remove_file(&a).unwrap();
    assert!(!db.lock().unwrap().tracks(std::slice::from_ref(&r)).unwrap()[0].available);
    // после скана строка ушла, обложка-сирота тоже
    let (sum, _) = rescan_store(&db, &index, Some(&covers)).unwrap();
    assert_eq!(sum.removed, 1);
    assert_eq!(index.len(), 0);
    assert_eq!(std::fs::read_dir(&covers).unwrap().count(), 0);
    let _ = std::fs::remove_dir_all(music);
    let _ = std::fs::remove_dir_all(covers);
  }
}
