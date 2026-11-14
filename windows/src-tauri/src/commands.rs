//! Команды для интерфейса (`invoke` из src/lib/api.ts). Ошибки — строкой, по-русски.

use crate::media::{self, Media, MediaInfo};
use crate::providers::{soundcloud, yandex, Source, Track};
use crate::services::{Core, ServiceStatus, ServicesStatus};
use crate::store::{Play, PlayerState, Store};
use serde::Serialize;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};
use tauri::State;

type Res<T> = Result<T, String>;

fn err(e: impl std::fmt::Display) -> String {
  e.to_string()
}

pub struct Db(pub Mutex<Store>);
pub struct StreamPort(pub u16);

#[tauri::command]
pub async fn services_status(core: State<'_, Arc<Core>>) -> Res<ServicesStatus> {
  Ok(core.status().await)
}

#[tauri::command]
pub async fn connect_soundcloud(
  core: State<'_, Arc<Core>>,
  client_id: String,
  oauth_token: Option<String>,
) -> Res<ServiceStatus> {
  let creds = soundcloud::Creds {
    client_id: client_id.trim().to_owned(),
    oauth_token: oauth_token.map(|t| t.trim().trim_start_matches("OAuth ").to_owned()).filter(|t| !t.is_empty()),
  };
  core.connect_soundcloud(creds).await.map_err(err)
}

#[tauri::command]
pub async fn connect_yandex(core: State<'_, Arc<Core>>, token: String) -> Res<ServiceStatus> {
  core.connect_yandex(yandex::Creds { token: token.trim().to_owned() }).await.map_err(err)
}

#[tauri::command]
pub async fn disconnect_service(core: State<'_, Arc<Core>>, service: String) -> Res<()> {
  core.disconnect(&service).await.map_err(err)
}

#[tauri::command]
pub async fn search(
  core: State<'_, Arc<Core>>,
  db: State<'_, Db>,
  q: String,
  src: String,
  limit: Option<u32>,
) -> Res<Vec<Track>> {
  let tracks = core.search(q.trim(), &src, limit.unwrap_or(30)).await.map_err(err)?;
  db.0.lock().unwrap().upsert_tracks(&tracks).map_err(err)?;
  Ok(tracks)
}

#[derive(Serialize)]
pub struct StreamUrl {
  kind: &'static str,
  url: String,
}

/// Адрес на локальном аудио-сервере для `<audio>` (file) или hls.js (hls).
#[tauri::command]
pub async fn stream_url(core: State<'_, Arc<Core>>, port: State<'_, StreamPort>, track_ref: String) -> Res<StreamUrl> {
  let src = core.resolve(&track_ref, false).await.map_err(err)?;
  let (kind, path) = match src {
    Source::File { .. } => ("file", "file"),
    Source::Hls { .. } => ("hls", "hls"),
  };
  Ok(StreamUrl { kind, url: format!("http://127.0.0.1:{}/{path}?ref={}", port.0, urlencoding::encode(&track_ref)) })
}

#[tauri::command]
pub fn cache_tracks(db: State<'_, Db>, tracks: Vec<Track>) -> Res<()> {
  db.0.lock().unwrap().upsert_tracks(&tracks).map_err(err)
}

#[tauri::command]
pub fn save_player_state(db: State<'_, Db>, state: PlayerState) -> Res<()> {
  db.0.lock().unwrap().save_player_state(&state).map_err(err)
}

#[derive(Serialize)]
pub struct Restored {
  state: PlayerState,
  tracks: Vec<Track>,
}

/// Последнее состояние плеера + треки очереди из кэша (для «Восстановления при запуске»).
#[tauri::command]
pub fn load_player_state(db: State<'_, Db>) -> Res<Option<Restored>> {
  let store = db.0.lock().unwrap();
  let Some(state) = store.player_state().map_err(err)? else { return Ok(None) };
  let tracks = store.tracks(&state.queue).map_err(err)?;
  Ok(Some(Restored { state, tracks }))
}

#[tauri::command]
pub fn record_play(db: State<'_, Db>, play: Play) -> Res<()> {
  db.0.lock().unwrap().add_play(&play).map_err(err)
}

#[tauri::command]
pub fn get_setting(db: State<'_, Db>, key: String) -> Res<Option<serde_json::Value>> {
  db.0.lock().unwrap().setting(&key).map_err(err)
}

#[tauri::command]
pub fn set_setting(core: State<'_, Arc<Core>>, db: State<'_, Db>, key: String, value: serde_json::Value) -> Res<()> {
  if key == "audio.quality" {
    let kbps = match value.as_str() {
      Some("low") => 192,
      Some("medium") => 256,
      _ => 320,
    };
    core.max_kbps.store(kbps, Ordering::Relaxed);
  }
  db.0.lock().unwrap().set_setting(&key, &value).map_err(err)
}

#[tauri::command]
pub fn media_update(media: State<'_, Media>, info: MediaInfo) {
  media::update(&media, &info);
}
