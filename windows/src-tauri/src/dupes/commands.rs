//! Команды экрана «Дубли»: найти группы, убрать отмеченные одной правкой и отменить её.

use super::{find_groups, DupeGroup};
use crate::commands::Db;
use crate::store::{DupeList, ListTrack, Removed, Store};
use anyhow::Result;
use tauri::State;

type Res<T> = Result<T, String>;

fn err(e: impl std::fmt::Display) -> String {
  e.to_string()
}

/// Треки списка по его id (`favorites` или свой плейлист).
fn list_items(store: &Store, list: &str) -> Result<Vec<ListTrack>> {
  Ok(match DupeList::parse(list)? {
    DupeList::Favorites => store.favorites()?,
    DupeList::Playlist(id) => {
      store.playlist(&id)?.and_then(|p| p.tracks).ok_or_else(|| anyhow::anyhow!("Плейлист не найден"))?
    }
  })
}

/// Группы дублей списка; сама сверка — вне блокировки базы и вне главного потока.
#[tauri::command]
pub async fn find_duplicates(db: State<'_, Db>, list: String) -> Res<Vec<DupeGroup>> {
  let items = list_items(&db.0.lock().unwrap(), &list).map_err(err)?;
  tauri::async_runtime::spawn_blocking(move || find_groups(&items)).await.map_err(err)
}

#[tauri::command]
pub fn remove_duplicates(db: State<'_, Db>, list: String, item_ids: Vec<String>) -> Res<Removed> {
  db.0.lock().unwrap().remove_dupes(&list, &item_ids).map_err(err)
}

#[tauri::command]
pub fn restore_duplicates(db: State<'_, Db>, removed: Removed) -> Res<usize> {
  db.0.lock().unwrap().restore_dupes(&removed).map_err(err)
}
