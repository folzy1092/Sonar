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

/// Подключить сервис в один клик: окно входа самого сервиса, ключи Sonar забирает сам (login.rs).
#[tauri::command]
pub async fn login_service(app: tauri::AppHandle, core: State<'_, Arc<Core>>, service: String) -> Res<ServiceStatus> {
  let core = core.inner().clone();
  match service.as_str() {
    "yandex" => crate::login::yandex(app, core).await,
    "soundcloud" => crate::login::soundcloud(app, core).await,
    _ => Err(anyhow::anyhow!("Неизвестный сервис: {service}")),
  }
  .map_err(err)
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
pub fn set_setting(
  core: State<'_, Arc<Core>>,
  discord: State<'_, Arc<crate::discord::Discord>>,
  obs: State<'_, Arc<crate::obs::Obs>>,
  db: State<'_, Db>,
  key: String,
  value: serde_json::Value,
) -> Res<()> {
  let flag = |a: &std::sync::atomic::AtomicBool| {
    a.store(value.as_bool().unwrap_or(true), Ordering::Relaxed);
    discord.refresh();
  };
  match key.as_str() {
    "integrations.discord.enabled" => flag(&discord.enabled),
    "integrations.discord.cover" => flag(&discord.cover),
    "integrations.discord.progress" => flag(&discord.progress),
    "system.tray" => crate::tray::HIDE_ON_CLOSE.store(value.as_bool().unwrap_or(true), Ordering::Relaxed),
    "obs.size" => *obs.size.write().unwrap() = value.as_str().unwrap_or("standard").to_owned(),
    "obs.hide_paused" => obs.hide_paused.store(value.as_bool().unwrap_or(true), Ordering::Relaxed),
    _ => {}
  }
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
pub fn media_update(media: State<'_, Media>, discord: State<'_, Arc<crate::discord::Discord>>, obs: State<'_, Arc<crate::obs::Obs>>, info: MediaInfo) {
  media::update(&media, &info);
  discord.update(&info);
  obs.update(&info);
}

/// Плашка OBS: адрес для источника «Браузер» и работает ли (порт мог быть занят).
#[tauri::command]
pub fn obs_status(obs: State<'_, Arc<crate::obs::Obs>>) -> serde_json::Value {
  serde_json::json!({
    "url": format!("http://127.0.0.1:{}/obs", crate::obs::PORT),
    "ok": !obs.failed.load(Ordering::Relaxed),
  })
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
  /// «Волна по треку»: стиль сессии — похожие на этот трек (во всех порциях сессии).
  seed: Option<Track>,
  /// Дослушанные / лайкнутые в этой сессии — сиды следующей порции (волна учится на ходу).
  #[serde(default)]
  session: Vec<Track>,
  /// Артисты, пропущенные в сессии хотя бы раз.
  #[serde(default)]
  skipped_artists: Vec<String>,
  /// Артисты всех выданных в сессии треков (с повторами, по порядку).
  #[serde(default)]
  served_artists: Vec<String>,
  n: Option<usize>,
  /// Режим волны (`wave::MODES`), по умолчанию «своя».
  #[serde(default)]
  mode: Option<String>,
  /// Смещение часового пояса (`Date.getTimezoneOffset()`) — для времени суток.
  #[serde(default)]
  tz_min: Option<i64>,
}

/// Следующая порция своей волны.
#[tauri::command]
pub async fn wave_portion(core: State<'_, Arc<Core>>, db: State<'_, Db>, req: WaveRequest) -> Res<Vec<Track>> {
  use crate::wave::{pick, tag_words, Filter, Origin, Rng, Session, PORTION};
  let mut rng = Rng::new(crate::store::now_ms() as u64);
  // что зашло в сессии — свежие в конце; берём до трёх последних
  let live: Vec<String> = req.session.iter().rev().take(3).map(|t| t.ref_.clone()).collect();
  let mut session = Session {
    skipped_artists: req.skipped_artists.iter().map(|a| a.to_lowercase()).collect(),
    recent_artists: req.served_artists.iter().map(|a| a.to_lowercase()).collect(),
    ..Default::default()
  };
  for a in &session.recent_artists {
    *session.served.entry(a.clone()).or_insert(0) += 1;
  }
  for (i, t) in req.session.iter().rev().enumerate() {
    // свежее зашедшее весит больше
    let w = 1.0 / (1.0 + i as f64 * 0.5);
    for tag in tag_words(t) {
      *session.tags.entry(tag).or_insert(0.0) += w;
    }
  }
  let (seeds, taste, filter, platform) = {
    let mut store = db.0.lock().unwrap();
    if !req.session.is_empty() {
      store.upsert_tracks(&req.session).map_err(err)?;
    }
    let seeds = match &req.seed {
      // стиль «по треку» держится всю сессию; зашедшее в ней понемногу его уточняет
      Some(s) => {
        store.upsert_tracks(std::slice::from_ref(s)).map_err(err)?;
        let mut v = vec![s.ref_.clone()];
        v.extend(live.iter().filter(|r| **r != s.ref_).take(2).cloned());
        v
      }
      None if !live.is_empty() => {
        // волна учится на ходу: зашедшее в сессии + немного общего вкуса и разведки
        let mut v = live.clone();
        let fresh = store.recent_like_refs(15).map_err(err)?;
        let fresh: Vec<String> = fresh.into_iter().filter(|r| !v.contains(r)).collect();
        v.extend(rng.sample(&fresh, 2));
        let old = store.old_like_refs(15, 300).map_err(err)?;
        v.extend(rng.sample(&old, 1));
        v
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
        // настроение — больше сидов, чтобы было из чего выбрать подходящее
        let wide = req.mode.as_deref().is_some_and(|m| m != "own");
        let mut seeds = rng.sample(&fresh, if wide { 8 } else { 5 });
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
    let mut taste = store.taste().map_err(err)?;
    taste.hour_share = store.hour_share(req.tz_min.unwrap_or(0)).unwrap_or_default();
    (seeds, taste, filter, platform)
  };

  let has_ym = core.has_yandex().await;
  let mut seeds: Vec<String> = seeds.into_iter().filter(|r| has_ym || !r.starts_with("ym:")).collect();
  let mut taste = taste;
  // Новичок: в Sonar ни лайков, ни прослушиваний — волна стартует от лайков (а если их нет —
  // от плейлистов) в выбранном сервисе. Их артисты считаются любимыми.
  if seeds.is_empty() {
    let svc = if has_ym && platform.as_deref() == Some("yandex") { "yandex" } else { "soundcloud" };
    let pl = if svc == "yandex" { "ympl:likes" } else { "scpl:likes" };
    let mut pool: Vec<Track> = core.service_playlist(pl).await.map(|p| p.tracks).unwrap_or_default();
    if pool.is_empty() {
      if let Ok(lists) = core.service_playlists(svc).await {
        for l in lists.iter().filter(|l| !l.ref_.ends_with("likes")).take(3) {
          if let Ok(p) = core.service_playlist(&l.ref_).await {
            pool.extend(p.tracks);
          }
        }
      }
    }
    pool.truncate(300);
    for t in &pool {
      taste.liked_artists.insert(crate::wave::artist_key(t));
    }
    let refs: Vec<String> = pool.iter().take(60).map(|t| t.ref_.clone()).collect();
    seeds = rng.sample(&refs, 6);
  }
  if seeds.is_empty() {
    return Err("Волне пока не от чего оттолкнуться — лайкни или послушай пару треков.".into());
  }
  let mode = req.mode.as_deref().filter(|m| crate::wave::MODES.contains(m)).unwrap_or("own").to_owned();
  let results = futures_util::future::join_all(seeds.iter().map(|r| core.similar(r, if mode == "own" { 25 } else { 35 }))).await;
  let mut cands = Vec::new();
  let mut origin = Origin::default();
  let mut first_err = None;
  for (seed, r) in seeds.iter().zip(results) {
    match r {
      Ok(v) => {
        origin.add(&v, live.contains(seed));
        cands.extend(v)
      }
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
  let mut out = pick(cands.clone(), &taste, &origin, &session, &filter, Some(prefer), &mode, n, false, &mut rng);
  if out.len() < 3 {
    out = pick(cands, &taste, &origin, &session, &filter, Some(prefer), &mode, n, true, &mut rng);
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

/// Треки из локального кэша по ref (в том же порядке).
#[tauri::command]
pub fn cached_tracks(db: State<'_, Db>, refs: Vec<String>) -> Res<Vec<Track>> {
  db.0.lock().unwrap().tracks(&refs).map_err(err)
}

/// Недавно игравшие треки (свежие первыми, без повторов).
#[tauri::command]
pub fn recent_tracks(db: State<'_, Db>, limit: Option<usize>) -> Res<Vec<Track>> {
  let store = db.0.lock().unwrap();
  let refs = store.recent_play_refs(limit.unwrap_or(20)).map_err(err)?;
  store.tracks(&refs).map_err(err)
}

/// Подборка на главной под время суток («Добрый вечер»): что слушаешь в эти часы + лайки.
#[tauri::command]
pub fn daypart_mix(db: State<'_, Db>, tz_min: Option<i64>, limit: Option<usize>) -> Res<Vec<Track>> {
  let store = db.0.lock().unwrap();
  let refs = store.daypart_refs(tz_min.unwrap_or(0), limit.unwrap_or(24)).map_err(err)?;
  store.tracks(&refs).map_err(err)
}

/// «Релизы недели»: свежие альбомы и синглы тех, на кого стоят лайки (новые первыми, с датой
/// `released`, неделю отсекает клиент); пусто — новинки Яндекса.
#[tauri::command]
pub async fn home_releases(core: State<'_, Arc<Core>>, db: State<'_, Db>) -> Res<Vec<crate::providers::Album>> {
  let artists = db.0.lock().unwrap().release_artist_refs(16).map_err(err)?;
  let has_ym = core.has_yandex().await;
  let artists: Vec<String> = artists.into_iter().filter(|r| has_ym || r.starts_with("sca:")).collect();
  let lists = futures_util::future::join_all(artists.iter().map(|r| core.artist_albums(r))).await;
  let mut seen = std::collections::HashSet::new();
  let mut albums: Vec<crate::providers::Album> =
    lists.into_iter().flat_map(|r| r.unwrap_or_default().into_iter().take(6)).filter(|a| seen.insert(a.ref_.clone())).collect();
  // свежие первыми: по дате выхода, без даты — по году (внутри — как отдал сервис)
  albums.sort_by_cached_key(|a| std::cmp::Reverse(release_key(a)));
  albums.truncate(20);
  if albums.len() < 4 && has_ym {
    if let Ok(more) = core.yandex_new_releases(16).await {
      albums.extend(more.into_iter().filter(|a| seen.insert(a.ref_.clone())));
      albums.truncate(20);
    }
  }
  Ok(albums)
}

/// Ключ сортировки релиза: `YYYY-MM-DD`, без даты — `YYYY-00-00`.
fn release_key(a: &crate::providers::Album) -> String {
  a.released.clone().unwrap_or_else(|| format!("{:04}-00-00", a.year.unwrap_or(0)))
}

/// Статистика из локальной истории (`GET /stats` в API.md §5). `tz_min` — смещение часового пояса.
#[tauri::command]
pub fn stats(db: State<'_, Db>, period: String, tz_min: Option<i64>) -> Res<crate::store::Stats> {
  db.0.lock().unwrap().stats(&period, tz_min.unwrap_or(0)).map_err(err)
}

/// Порт локального сервера — для `/cover` (цвет темы из обложки).
#[tauri::command]
pub fn stream_port(port: State<'_, StreamPort>) -> u16 {
  port.0
}

// ——— настройки, хранилище, система ———

#[tauri::command]
pub fn all_settings(db: State<'_, Db>) -> Res<std::collections::HashMap<String, serde_json::Value>> {
  db.0.lock().unwrap().all_settings().map_err(err)
}

#[tauri::command]
pub fn reset_settings(core: State<'_, Arc<Core>>, db: State<'_, Db>) -> Res<()> {
  db.0.lock().unwrap().reset_settings().map_err(err)?;
  core.sc_via_yandex.store(true, Ordering::Relaxed);
  core.max_kbps.store(crate::services::quality_kbps(None), Ordering::Relaxed);
  Ok(())
}

#[derive(Serialize)]
pub struct StorageUsage {
  covers: u64,
  covers_bytes: u64,
  lyrics: i64,
  lyrics_bytes: i64,
  track_prefs: i64,
  db_bytes: u64,
}

fn dir_usage(dir: &std::path::Path) -> (u64, u64) {
  let mut n = 0;
  let mut bytes = 0;
  if let Ok(rd) = std::fs::read_dir(dir) {
    for e in rd.flatten() {
      if let Ok(m) = e.metadata() {
        if m.is_file() {
          n += 1;
          bytes += m.len();
        }
      }
    }
  }
  (n, bytes)
}

/// Экран «Хранилище»: сколько занято обложками, текстами, базой.
#[tauri::command]
pub fn storage_usage(app: tauri::AppHandle, db: State<'_, Db>) -> Res<StorageUsage> {
  use tauri::Manager;
  let (covers, covers_bytes) = crate::stream::cover_dir().map(|d| dir_usage(d)).unwrap_or((0, 0));
  let store = db.0.lock().unwrap();
  let (lyrics, lyrics_bytes) = store.lyrics_usage().map_err(err)?;
  let db_bytes = app
    .path()
    .app_data_dir()
    .ok()
    .and_then(|d| std::fs::metadata(d.join("sonar.db")).ok())
    .map(|m| m.len())
    .unwrap_or(0);
  Ok(StorageUsage { covers, covers_bytes, lyrics, lyrics_bytes, track_prefs: store.track_prefs_count().map_err(err)?, db_bytes })
}

/// Очистить: `covers` | `lyrics` | `track_prefs` | `all` (обложки и тексты).
#[tauri::command]
pub fn clear_storage(db: State<'_, Db>, kind: String) -> Res<()> {
  let clear_covers = || {
    if let Some(d) = crate::stream::cover_dir() {
      if let Ok(rd) = std::fs::read_dir(d) {
        for e in rd.flatten() {
          let _ = std::fs::remove_file(e.path());
        }
      }
    }
  };
  let store = db.0.lock().unwrap();
  match kind.as_str() {
    "covers" => clear_covers(),
    "lyrics" => store.clear_lyrics_cache().map_err(err)?,
    "track_prefs" => store.reset_track_prefs().map_err(err)?,
    "all" => {
      clear_covers();
      store.clear_lyrics_cache().map_err(err)?;
    }
    _ => return Err(format!("неизвестно, что чистить: {kind}")),
  }
  Ok(())
}

/// Открыть ссылку в браузере (только https; «О приложении»: канал, сайт).
#[tauri::command]
pub fn open_url(url: String) -> Res<()> {
  if !url.starts_with("https://") {
    return Err("можно открыть только https-ссылку".into());
  }
  #[cfg(windows)]
  {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    std::process::Command::new("rundll32")
      .args(["url.dll,FileProtocolHandler", &url])
      .creation_flags(CREATE_NO_WINDOW)
      .spawn()
      .map_err(err)?;
  }
  Ok(())
}

/// Масштаб: `kind` — `window` (в окне) или `fullscreen` (развёрнуто), `percent` — 75–125.
#[tauri::command]
pub fn set_zoom(window: tauri::WebviewWindow, kind: String, percent: f64) {
  crate::zoom::set(&window, &kind, percent);
}

/// Автозапуск с Windows (`system.autostart`): запись в HKCU…Run через tauri-plugin-autostart.
#[tauri::command]
pub fn set_autostart(app: tauri::AppHandle, on: bool) -> Res<()> {
  use tauri_plugin_autostart::ManagerExt;
  let al = app.autolaunch();
  if on { al.enable() } else { al.disable() }.map_err(err)
}

#[tauri::command]
pub fn autostart_enabled(app: tauri::AppHandle) -> Res<bool> {
  use tauri_plugin_autostart::ManagerExt;
  app.autolaunch().is_enabled().map_err(err)
}

/// `system.tray`: крестик прячет в трей (true) или закрывает Sonar (false).
#[tauri::command]
pub fn set_tray_mode(on: bool) {
  crate::tray::HIDE_ON_CLOSE.store(on, Ordering::Relaxed);
}
