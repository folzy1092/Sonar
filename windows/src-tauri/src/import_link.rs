//! Команды импорта плейлиста по ссылке (этап 5, логика — `services/import.rs`): прочитать и сверить
//! (шаги — событием `import:progress`), отменить, сохранить итог смешанным плейлистом Sonar.

use crate::commands::Db;
use crate::providers::Track;
use crate::services::import::{cancel, forget_job, ImportHead, ImportStep};
use crate::services::Core;
use crate::store::{Playlist, Store};
use serde::Serialize;
use std::sync::Arc;
use std::time::Duration;
use tauri::{Emitter, State};

/// Сколько ждать чтения источника (сам поиск пар не ограничен: он идёт шагами и виден).
const READ_TIMEOUT: Duration = Duration::from_secs(60);
/// Самое длинное имя нового плейлиста.
const MAX_NAME_CHARS: usize = 200;
/// Событие прогресса для экрана импорта.
const PROGRESS_EVENT: &str = "import:progress";

/// Событие `import:progress`: сначала шапка и треки источника, потом шаг на каждый трек.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum Progress<'a> {
  Head { job: &'a str, head: &'a ImportHead, tracks: &'a [Track] },
  Step { job: &'a str, step: &'a ImportStep },
}

/// Итог: источник, его треки и шаг на каждый трек (по порядку источника).
#[derive(Debug, Clone, Serialize)]
pub struct ImportResult {
  pub head: ImportHead,
  pub tracks: Vec<Track>,
  pub steps: Vec<ImportStep>,
}

/// Прочитать источник по ссылке (или ref) и подобрать пары. `job` — id задачи из интерфейса:
/// по нему фильтруются события и работает `import_cancel`.
#[tauri::command]
pub async fn import_link(app: tauri::AppHandle, core: State<'_, Arc<Core>>, link: String, job: String) -> Result<ImportResult, String> {
  let read = tokio::time::timeout(READ_TIMEOUT, core.import_source(&link))
    .await
    .map_err(|_| "Сервис не ответил за минуту — попробуй ещё раз".to_string())
    .and_then(|r| r.map_err(|e| e.to_string()));
  let source = match read {
    Ok(source) => source,
    Err(e) => {
      // отмена, пришедшая во время чтения, больше не нужна
      forget_job(&job);
      return Err(e);
    }
  };
  let _ = app.emit(PROGRESS_EVENT, Progress::Head { job: &job, head: &source.head, tracks: &source.tracks });
  let steps = core
    .import_match_all(&job, &source.tracks, |step| {
      let _ = app.emit(PROGRESS_EVENT, Progress::Step { job: &job, step });
    })
    .await;
  Ok(ImportResult { head: source.head, tracks: source.tracks, steps })
}

/// Остановить подбор пар («Остановить» на экране импорта или новый импорт).
#[tauri::command]
pub fn import_cancel(job: String) {
  cancel(&job);
}

/// Сохранить найденное смешанным плейлистом. `source` — `head.source` (ref или адрес страницы):
/// тот же источник второй раз не создаёт копию, а дописывает в прежний плейлист новые треки.
#[tauri::command]
pub fn import_create(db: State<'_, Db>, name: String, source: String, tracks: Vec<Track>) -> Result<Playlist, String> {
  let name: String = name.trim().chars().take(MAX_NAME_CHARS).collect();
  if name.is_empty() {
    return Err("Назови плейлист".into());
  }
  if tracks.is_empty() {
    return Err("Переносить нечего: ни один трек не нашёлся".into());
  }
  let mut store = db.0.lock().unwrap();
  let id = save_import(&mut store, &source, &name, &tracks).map_err(|e| e.to_string())?;
  store.playlist(&id).map_err(|e| e.to_string())?.ok_or_else(|| "плейлист пропал".into())
}

/// Треки — в кэш, плейлист с `source_ref = source`: новый или уже перенесённый (дописать недостающее).
/// Общий путь «Перенести в Sonar» фантомного плейлиста и импорта по ссылке.
pub fn save_import(store: &mut Store, source: &str, name: &str, tracks: &[Track]) -> anyhow::Result<String> {
  store.upsert_tracks(tracks)?;
  let refs = unique_refs(tracks);
  match store.playlist_by_source(source)? {
    Some(id) => {
      let old = store.playlist(&id)?.and_then(|p| p.tracks).unwrap_or_default();
      let have: std::collections::HashSet<&str> = old.iter().map(|t| t.track.ref_.as_str()).collect();
      let new: Vec<String> = refs.into_iter().filter(|r| !have.contains(r.as_str())).collect();
      store.add_to_playlist(&id, &new, false)?;
      Ok(id)
    }
    None => store.create_playlist(name, &refs, Some(source)),
  }
}

/// ref по порядку без повторов: две строки источника могут найти один и тот же трек.
fn unique_refs(tracks: &[Track]) -> Vec<String> {
  let mut seen = std::collections::HashSet::new();
  tracks.iter().filter(|t| seen.insert(t.ref_.as_str())).map(|t| t.ref_.clone()).collect()
}

#[cfg(test)]
mod tests {
  use super::*;

  fn track(r: &str) -> Track {
    Track {
      ref_: r.into(),
      title: format!("t {r}"),
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

  #[test]
  fn unique_refs_keep_first_order() {
    let refs = unique_refs(&[track("sc:1"), track("ym:2"), track("sc:1")]);
    assert_eq!(refs, vec!["sc:1".to_string(), "ym:2".to_string()]);
  }

  #[test]
  fn same_source_appends_instead_of_copy() {
    let mut store = Store::memory().unwrap();
    let src = "https://music.apple.com/us/playlist/x/pl.1";
    let first = save_import(&mut store, src, "Микс", &[track("sc:1"), track("ym:2")]).unwrap();
    let again = save_import(&mut store, src, "Другое имя", &[track("ym:2"), track("yt:3")]).unwrap();
    assert_eq!(first, again);
    let p = store.playlist(&first).unwrap().unwrap();
    assert_eq!(p.name, "Микс");
    let refs: Vec<String> = p.tracks.unwrap().into_iter().map(|t| t.track.ref_).collect();
    assert_eq!(refs, vec!["sc:1", "ym:2", "yt:3"]);
  }
}
