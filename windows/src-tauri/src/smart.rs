//! Команды умных плейлистов (NEXT_PROMPT, этап 6). Правила — docs/PLATFORMS.md «Умные плейлисты».

use crate::commands::Db;
use crate::store::{SmartPlaylist, SmartPreview, SmartRules};
use tauri::State;

type Res<T> = Result<T, String>;

fn err(e: impl std::fmt::Display) -> String {
  e.to_string()
}

#[tauri::command]
pub fn smart_playlists(db: State<'_, Db>) -> Res<Vec<SmartPlaylist>> {
  db.0.lock().unwrap().smart_playlists().map_err(err)
}

#[tauri::command]
pub fn smart_playlist(db: State<'_, Db>, id: String) -> Res<SmartPlaylist> {
  db.0.lock().unwrap().smart_playlist(&id).map_err(err)?.ok_or_else(|| "Умный плейлист не найден".into())
}

#[tauri::command]
pub fn smart_preview(db: State<'_, Db>, rules: SmartRules) -> Res<SmartPreview> {
  db.0.lock().unwrap().smart_preview(&rules).map_err(err)
}

#[tauri::command]
pub fn create_smart_playlist(db: State<'_, Db>, name: String, rules: SmartRules) -> Res<SmartPlaylist> {
  let name = name.trim();
  if name.is_empty() {
    return Err("Дай плейлисту название".into());
  }
  let store = db.0.lock().unwrap();
  let id = store.create_smart_playlist(name, &rules).map_err(err)?;
  store.smart_playlist(&id).map_err(err)?.ok_or_else(|| "Умный плейлист не найден".into())
}

#[tauri::command]
pub fn update_smart_playlist(db: State<'_, Db>, id: String, name: Option<String>, rules: Option<SmartRules>) -> Res<()> {
  db.0.lock().unwrap().update_smart_playlist(&id, name.as_deref(), rules.as_ref()).map_err(err)
}

#[tauri::command]
pub fn delete_smart_playlist(db: State<'_, Db>, id: String) -> Res<()> {
  db.0.lock().unwrap().delete_smart_playlist(&id).map_err(err)
}
