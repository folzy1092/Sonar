//! Команды для интерфейса (`invoke` из src/lib/api.ts). Ошибки — строкой, по-русски.

use crate::lyrics::{self, Lyrics};
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
  /// Что реально играет: «AAC 160», «MP3 320», «FLAC».
  quality: String,
}

/// Адрес на локальном аудио-сервере для `<audio>` (file) или hls.js (hls).
#[tauri::command]
pub async fn stream_url(core: State<'_, Arc<Core>>, port: State<'_, StreamPort>, track_ref: String) -> Res<StreamUrl> {
  let src = core.resolve(&track_ref, false).await.map_err(err)?;
  let (kind, path, quality) = match src {
    Source::File { quality, .. } => ("file", "file", quality),
    Source::Hls { quality, .. } => ("hls", "hls", quality),
  };
  Ok(StreamUrl { kind, url: format!("http://127.0.0.1:{}/{path}?ref={}", port.0, urlencoding::encode(&track_ref)), quality })
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
  if key == "audio.sc_via_yandex" {
    core.sc_via_yandex.store(value.as_bool().unwrap_or(true), Ordering::Relaxed);
  }
  if key == "audio.quality" {
    core.max_kbps.store(crate::services::quality_kbps(value.as_str()), Ordering::Relaxed);
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

// ——— тексты песен (SPEC §3.7б, docs/LYRICS.md) ———

/// Текст трека: кэш в базе → lrclib → Genius. `None` — «Текст не найден»
/// («нет» перепроверяется через 30 мин). `refresh` — выбросить кэш и искать заново.
#[tauri::command]
pub async fn lyrics(core: State<'_, Arc<Core>>, db: State<'_, Db>, track: Track, refresh: Option<bool>) -> Res<Option<Lyrics>> {
  if refresh == Some(true) {
    db.0.lock().unwrap().clear_lyrics(&track.ref_).map_err(err)?;
  } else if let Some((json, at)) = db.0.lock().unwrap().lyrics_cached(&track.ref_).map_err(err)? {
    match json {
      Some(j) => {
        if let Ok(l) = serde_json::from_str::<Lyrics>(&j) {
          return Ok(Some(l));
        }
      }
      None if crate::store::now_ms() - at < lyrics::RECHECK_TTL_MS => return Ok(None),
      None => {}
    }
  }
  let found = lyrics::fetch_any(&core.http, &lyrics::Meta::of(&track)).await.map_err(err)?;
  let json = found.as_ref().map(|l| serde_json::to_string(l)).transpose().map_err(err)?;
  db.0
    .lock()
    .unwrap()
    .put_lyrics(&track.ref_, json.as_deref(), found.as_ref().map(|l| l.source.as_str()))
    .map_err(err)?;
  Ok(found)
}

#[tauri::command]
pub fn lyrics_offset(db: State<'_, Db>, track_ref: String) -> Res<i64> {
  db.0.lock().unwrap().lyrics_offset(&track_ref).map_err(err)
}

#[tauri::command]
pub fn set_lyrics_offset(db: State<'_, Db>, track_ref: String, ms: i64) -> Res<()> {
  db.0.lock().unwrap().set_lyrics_offset(&track_ref, ms).map_err(err)
}

// ——— эквалайзер: кривая, запомненная для трека ———

#[tauri::command]
pub fn track_eq(db: State<'_, Db>, track_ref: String) -> Res<Option<Vec<f64>>> {
  db.0.lock().unwrap().track_eq(&track_ref).map_err(err)
}

#[tauri::command]
pub fn set_track_eq(db: State<'_, Db>, track_ref: String, gains: Option<Vec<f64>>) -> Res<()> {
  db.0.lock().unwrap().set_track_eq(&track_ref, gains.as_deref()).map_err(err)
}

// ——— главная и своя волна (SPEC §3.7) ———

#[derive(serde::Deserialize)]
pub struct WaveRequest {
  /// Уже выданные в этой сессии волны.
  #[serde(default)]
  exclude: Vec<String>,
  /// Артисты на паузе до конца сессии (два пропуска подряд).
  #[serde(default)]
  paused_artists: Vec<String>,
  /// «Волна по треку»: сид — только этот трек.
  seed: Option<Track>,
  n: Option<usize>,
}

/// Следующая порция своей волны.
#[tauri::command]
pub async fn wave_portion(core: State<'_, Arc<Core>>, db: State<'_, Db>, req: WaveRequest) -> Res<Vec<Track>> {
  use crate::wave::{pick, Filter, Rng, PORTION};
  let mut rng = Rng::new(crate::store::now_ms() as u64);
  let (seeds, taste, filter, platform) = {
    let mut store = db.0.lock().unwrap();
    let seeds = match &req.seed {
      Some(s) => {
        store.upsert_tracks(std::slice::from_ref(s)).map_err(err)?;
        vec![s.ref_.clone()]
      }
      None => {
        let mut fresh = store.recent_like_refs(15).map_err(err)?;
        for r in store.recent_finished_refs(10).map_err(err)? {
          if !fresh.contains(&r) {
            fresh.push(r);
          }
        }
        if fresh.is_empty() {
          fresh = store.recent_play_refs(10).map_err(err)?;
        }
        let mut seeds = rng.sample(&fresh, 5);
        // 10–20 % «разведки»: похожие от случайного старого лайка
        let old = store.old_like_refs(15, 300).map_err(err)?;
        seeds.extend(rng.sample(&old, 1));
        seeds
      }
    };
    let filter = Filter {
      recent: store.played_since_days(7).map_err(err)?,
      banned: store.disliked_refs().map_err(err)?.into_iter().collect(),
      exclude: req.exclude.into_iter().collect(),
      paused_artists: req.paused_artists.iter().map(|a| a.to_lowercase()).collect(),
    };
    let platform = store.setting("general.platform").ok().flatten().and_then(|v| v.as_str().map(str::to_owned));
    (seeds, store.taste().map_err(err)?, filter, platform)
  };

  let has_ym = core.has_yandex().await;
  let seeds: Vec<String> = seeds.into_iter().filter(|r| has_ym || !r.starts_with("ym:")).collect();
  if seeds.is_empty() {
    return Err("Волне пока не от чего оттолкнуться — лайкни или послушай пару треков.".into());
  }
  let results = futures_util::future::join_all(seeds.iter().map(|r| core.similar(r, 25))).await;
  let mut cands = Vec::new();
  let mut first_err = None;
  for r in results {
    match r {
      Ok(v) => cands.extend(v),
      Err(e) => {
        first_err.get_or_insert_with(|| e.to_string());
      }
    }
  }
  if cands.is_empty() {
    return Err(first_err.unwrap_or_else(|| "Похожих треков не нашлось — попробуй лайкнуть что-нибудь ещё.".into()));
  }
  let prefer = if has_ym && platform.as_deref() == Some("yandex") { "ym" } else { "sc" };
  let n = req.n.unwrap_or(PORTION);
  let mut out = pick(cands.clone(), &taste, &filter, Some(prefer), n, false, &mut rng);
  if out.len() < 3 {
    out = pick(cands, &taste, &filter, Some(prefer), n, true, &mut rng);
  }
  db.0.lock().unwrap().upsert_tracks(&out).map_err(err)?;
  Ok(out)
}

/// Сигнал волне: `dislike` / `undislike` (👎 и отмена), `skip` (пропуск в первые 30 с).
#[tauri::command]
pub fn wave_feedback(db: State<'_, Db>, event: String, track: Track, played_ms: Option<i64>) -> Res<()> {
  let mut store = db.0.lock().unwrap();
  match event.as_str() {
    "dislike" | "undislike" => {
      store.upsert_tracks(std::slice::from_ref(&track)).map_err(err)?;
      store.set_dislike(&track.ref_, &track.artist, event == "dislike").map_err(err)
    }
    "skip" => store.add_skip(&track.ref_, &track.artist, played_ms.unwrap_or(0)).map_err(err),
    _ => Err(format!("неизвестный сигнал {event}")),
  }
}

#[tauri::command]
pub fn disliked_refs(db: State<'_, Db>) -> Res<Vec<String>> {
  db.0.lock().unwrap().disliked_refs().map_err(err)
}

/// Похожие на трек — ряд «Похожее» на главной.
#[tauri::command]
pub async fn similar_tracks(core: State<'_, Arc<Core>>, db: State<'_, Db>, track_ref: String, limit: Option<u32>) -> Res<Vec<Track>> {
  let banned: std::collections::HashSet<String> = db.0.lock().unwrap().disliked_refs().map_err(err)?.into_iter().collect();
  let tracks: Vec<Track> = core
    .similar(&track_ref, limit.unwrap_or(20))
    .await
    .map_err(err)?
    .into_iter()
    .filter(|t| t.available && !banned.contains(&t.ref_))
    .collect();
  db.0.lock().unwrap().upsert_tracks(&tracks).map_err(err)?;
  Ok(tracks)
}

/// Недавно игравшие треки (свежие первыми, без повторов).
#[tauri::command]
pub fn recent_tracks(db: State<'_, Db>, limit: Option<usize>) -> Res<Vec<Track>> {
  let store = db.0.lock().unwrap();
  let refs = store.recent_play_refs(limit.unwrap_or(20)).map_err(err)?;
  store.tracks(&refs).map_err(err)
}

/// «Релизы»: свежие альбомы лайкнутых и самых слушаемых исполнителей; пусто — новинки Яндекса.
#[tauri::command]
pub async fn home_releases(core: State<'_, Arc<Core>>, db: State<'_, Db>) -> Res<Vec<crate::providers::Album>> {
  let artists = db.0.lock().unwrap().favorite_artist_refs(10).map_err(err)?;
  let has_ym = core.has_yandex().await;
  let artists: Vec<String> = artists.into_iter().filter(|r| has_ym || r.starts_with("sca:")).collect();
  let lists = futures_util::future::join_all(artists.iter().map(|r| core.artist_albums(r))).await;
  let mut seen = std::collections::HashSet::new();
  let mut albums: Vec<crate::providers::Album> =
    lists.into_iter().flat_map(|r| r.unwrap_or_default().into_iter().take(4)).filter(|a| seen.insert(a.ref_.clone())).collect();
  // свежие первыми; внутри года — как отдал сервис (у него новые первыми)
  albums.sort_by(|a, b| b.year.unwrap_or(0).cmp(&a.year.unwrap_or(0)));
  albums.truncate(16);
  if albums.len() < 4 && has_ym {
    if let Ok(more) = core.yandex_new_releases(16).await {
      albums.extend(more.into_iter().filter(|a| seen.insert(a.ref_.clone())));
      albums.truncate(16);
    }
  }
  Ok(albums)
}
