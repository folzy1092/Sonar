//! Команды для интерфейса (`invoke` из src/lib/api.ts). Ошибки — строкой, по-русски.

use crate::media::{self, Media, MediaInfo};
use crate::providers::{soundcloud, yandex, AlbumPage, ArtistPage, SearchResults, ServicePlaylist, Source, Track};
use crate::services::{Core, PlaylistPage, ServiceStatus, ServicesStatus};
use crate::store::{like_kind, ListTrack, Play, PlayerState, Playlist, Store};
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

// ——— каталог: поиск артистов/альбомов/плейлистов, страницы ———

#[tauri::command]
pub async fn search_more(core: State<'_, Arc<Core>>, q: String, src: String, limit: Option<u32>) -> Res<SearchResults> {
  core.search_more(q.trim(), &src, limit.unwrap_or(12)).await.map_err(err)
}

#[tauri::command]
pub async fn artist_page(core: State<'_, Arc<Core>>, db: State<'_, Db>, artist_ref: String) -> Res<ArtistPage> {
  let page = core.artist_page(&artist_ref).await.map_err(err)?;
  let mut store = db.0.lock().unwrap();
  let _ = store.put_catalog(&page.artist.ref_, "artist", &serde_json::to_value(&page.artist).map_err(err)?);
  store.upsert_tracks(&page.top).map_err(err)?;
  Ok(page)
}

#[tauri::command]
pub async fn album_page(core: State<'_, Arc<Core>>, db: State<'_, Db>, album_ref: String) -> Res<AlbumPage> {
  let page = core.album_page(&album_ref).await.map_err(err)?;
  let mut store = db.0.lock().unwrap();
  let _ = store.put_catalog(&page.album.ref_, "album", &serde_json::to_value(&page.album).map_err(err)?);
  store.upsert_tracks(&page.tracks).map_err(err)?;
  Ok(page)
}

#[tauri::command]
pub async fn service_playlists(core: State<'_, Arc<Core>>, service: String) -> Res<Vec<ServicePlaylist>> {
  core.service_playlists(&service).await.map_err(err)
}

#[tauri::command]
pub async fn service_playlist(core: State<'_, Arc<Core>>, db: State<'_, Db>, pl_ref: String) -> Res<PlaylistPage> {
  let page = core.service_playlist(&pl_ref).await.map_err(err)?;
  db.0.lock().unwrap().upsert_tracks(&page.tracks).map_err(err)?;
  Ok(page)
}

/// Перенести плейлист сервиса в Sonar (`POST /services/{svc}/playlists/{id}/import`).
/// Уже перенесённый — обновляется до текущего состава сервиса не создаётся второй раз.
#[tauri::command]
pub async fn import_playlist(core: State<'_, Arc<Core>>, db: State<'_, Db>, pl_ref: String, name: Option<String>) -> Res<Playlist> {
  let page = core.service_playlist(&pl_ref).await.map_err(err)?;
  let refs: Vec<String> = page.tracks.iter().map(|t| t.ref_.clone()).collect();
  let mut store = db.0.lock().unwrap();
  store.upsert_tracks(&page.tracks).map_err(err)?;
  let id = match store.playlist_by_source(&pl_ref).map_err(err)? {
    Some(id) => {
      let old = store.playlist(&id).map_err(err)?.and_then(|p| p.tracks).unwrap_or_default();
      let have: std::collections::HashSet<&str> = old.iter().map(|t| t.track.ref_.as_str()).collect();
      let new: Vec<String> = refs.iter().filter(|r| !have.contains(r.as_str())).cloned().collect();
      store.add_to_playlist(&id, &new, false).map_err(err)?;
      id
    }
    None => {
      let title = name.filter(|n| !n.trim().is_empty()).unwrap_or(page.playlist.title);
      store.create_playlist(&title, &refs, Some(&pl_ref)).map_err(err)?
    }
  };
  store.playlist(&id).map_err(err)?.ok_or_else(|| "плейлист пропал".into())
}

// ——— медиатека: лайки и плейлисты Sonar ———

/// Лайк трека, альбома или исполнителя. `item` — его JSON (Track / Album / Artist), чтобы показать
/// в медиатеке без похода в сервис.
#[tauri::command]
pub fn set_like(db: State<'_, Db>, item_ref: String, on: bool, item: Option<serde_json::Value>) -> Res<()> {
  let mut store = db.0.lock().unwrap();
  if let (true, Some(item)) = (on, item) {
    match like_kind(&item_ref) {
      Some("track") => {
        let t: Track = serde_json::from_value(item).map_err(err)?;
        store.upsert_tracks(&[t]).map_err(err)?;
      }
      Some(kind) => store.put_catalog(&item_ref, kind, &item).map_err(err)?,
      None => {}
    }
  }
  store.set_like(&item_ref, on).map_err(err)
}

/// Все лайкнутые ref (для сердечек в списках).
#[tauri::command]
pub fn liked_refs(db: State<'_, Db>) -> Res<Vec<String>> {
  let store = db.0.lock().unwrap();
  let mut out = Vec::new();
  for kind in ["track", "album", "artist"] {
    out.extend(store.likes(kind).map_err(err)?.into_iter().map(|(r, _)| r));
  }
  Ok(out)
}

#[tauri::command]
pub fn favorites(db: State<'_, Db>) -> Res<Vec<ListTrack>> {
  db.0.lock().unwrap().favorites().map_err(err)
}

#[tauri::command]
pub fn liked_catalog(db: State<'_, Db>, kind: String) -> Res<Vec<serde_json::Value>> {
  db.0.lock().unwrap().liked_catalog(&kind).map_err(err)
}

#[tauri::command]
pub fn playlists(db: State<'_, Db>) -> Res<Vec<Playlist>> {
  db.0.lock().unwrap().playlists().map_err(err)
}

#[tauri::command]
pub fn playlist(db: State<'_, Db>, id: String) -> Res<Playlist> {
  db.0.lock().unwrap().playlist(&id).map_err(err)?.ok_or_else(|| "Плейлист не найден".into())
}

#[tauri::command]
pub fn create_playlist(db: State<'_, Db>, name: String, tracks: Option<Vec<Track>>) -> Res<Playlist> {
  let name = name.trim();
  if name.is_empty() {
    return Err("Дай плейлисту название".into());
  }
  let tracks = tracks.unwrap_or_default();
  let mut store = db.0.lock().unwrap();
  store.upsert_tracks(&tracks).map_err(err)?;
  let refs: Vec<String> = tracks.iter().map(|t| t.ref_.clone()).collect();
  let id = store.create_playlist(name, &refs, None).map_err(err)?;
  store.playlist(&id).map_err(err)?.ok_or_else(|| "плейлист пропал".into())
}

#[tauri::command]
pub fn update_playlist(db: State<'_, Db>, id: String, name: Option<String>, hidden: Option<bool>) -> Res<()> {
  db.0.lock().unwrap().update_playlist(&id, name.as_deref(), hidden).map_err(err)
}

#[tauri::command]
pub fn delete_playlist(db: State<'_, Db>, id: String) -> Res<()> {
  db.0.lock().unwrap().delete_playlist(&id).map_err(err)
}

/// Добавить треки; `position` — "start" или "end" (настройка `library.add_position`).
#[tauri::command]
pub fn add_to_playlist(db: State<'_, Db>, id: String, tracks: Vec<Track>, position: Option<String>) -> Res<()> {
  let mut store = db.0.lock().unwrap();
  store.upsert_tracks(&tracks).map_err(err)?;
  let refs: Vec<String> = tracks.iter().map(|t| t.ref_.clone()).collect();
  store.add_to_playlist(&id, &refs, position.as_deref() == Some("start")).map_err(err)
}

#[tauri::command]
pub fn remove_from_playlist(db: State<'_, Db>, id: String, item_ids: Vec<String>) -> Res<()> {
  db.0.lock().unwrap().remove_from_playlist(&id, &item_ids).map_err(err)
}

#[tauri::command]
pub fn reorder_playlist(db: State<'_, Db>, id: String, item_ids: Vec<String>) -> Res<()> {
  db.0.lock().unwrap().reorder_playlist(&id, &item_ids).map_err(err)
}

#[tauri::command]
pub fn media_update(media: State<'_, Media>, info: MediaInfo) {
  media::update(&media, &info);
}
