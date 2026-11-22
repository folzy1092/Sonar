//! Команды для интерфейса (`invoke` из src/lib/api.ts). Ошибки — строкой, по-русски.

use crate::lyrics::{self, Lyrics};
use crate::media::{self, Media, MediaInfo};
use crate::providers::registry::{by_key, is_kind, likes_ref, RefKind, ServiceId, ServiceInfo};
use crate::providers::{soundcloud, vk, yandex, AlbumPage, ArtistPage, SearchResults, ServicePlaylist, Source, Track};
use crate::services::{Core, PlaylistPage, ServiceEntry, ServiceStatus, ServicesStatus};
use crate::store::{like_kind, ListTrack, Play, PlayerState, Playlist, Store};
use serde::Serialize;
use std::collections::HashMap;
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
  core.connect_soundcloud(sc_creds(&client_id, oauth_token.as_deref())).await.map_err(err)
}

#[tauri::command]
pub async fn connect_yandex(core: State<'_, Arc<Core>>, token: String) -> Res<ServiceStatus> {
  core.connect_yandex(ym_creds(&token)).await.map_err(err)
}

/// Ключи SoundCloud как их вставили: без пробелов по краям и без `OAuth ` перед токеном.
fn sc_creds(client_id: &str, oauth_token: Option<&str>) -> soundcloud::Creds {
  soundcloud::Creds {
    client_id: client_id.trim().to_owned(),
    oauth_token: oauth_token.map(|t| t.trim().trim_start_matches("OAuth ").to_owned()).filter(|t| !t.is_empty()),
  }
}

fn ym_creds(token: &str) -> yandex::Creds {
  yandex::Creds { token: token.trim().to_owned() }
}

/// Ключи из формы «Вставить ключ» для своего сервиса.
#[derive(Debug)]
enum KeyCreds {
  Sc(soundcloud::Creds),
  Ym(yandex::Creds),
  /// Cookie music.youtube.com как вставили; разбирает и проверяет `Core::connect_youtube`.
  Yt(String),
  Vk(vk::Creds),
  /// Cookie `sp_dc` как есть: разбор и проверка — в Core::connect_spotify.
  Sp(String),
}

/// Поля формы → ключи сервиса. Нет обязательного поля — пустая строка, её отклонит проверка
/// в Core прежним текстом. Чужие поля не смотрим. Значения полей в ошибки не попадают.
fn key_creds(info: &ServiceInfo, fields: &HashMap<String, String>) -> Res<KeyCreds> {
  let field = |name: &str| fields.get(name).map(String::as_str);
  match info.id {
    ServiceId::Sc => Ok(KeyCreds::Sc(sc_creds(field("client_id").unwrap_or(""), field("oauth_token")))),
    ServiceId::Ym => Ok(KeyCreds::Ym(ym_creds(field("token").unwrap_or("")))),
    ServiceId::Yt => Ok(KeyCreds::Yt(field("cookie").unwrap_or("").to_owned())),
    ServiceId::Vk => Ok(KeyCreds::Vk(vk::Creds { token: field("token").unwrap_or("").trim().to_owned() })),
    ServiceId::Sp => Ok(KeyCreds::Sp(field("sp_dc").unwrap_or("").to_owned())),
    _ => Err(format!("{}: пока не поддерживается", info.name)),
  }
}

/// Все сервисы реестра с состоянием подключения.
#[tauri::command]
pub async fn services_list(core: State<'_, Arc<Core>>) -> Res<Vec<ServiceEntry>> {
  Ok(core.list().await)
}

/// Подключить сервис по вставленному ключу (`service` — `sc` или `soundcloud` и т. д.).
#[tauri::command]
pub async fn connect_service_key(core: State<'_, Arc<Core>>, service: String, fields: HashMap<String, String>) -> Res<ServiceStatus> {
  let info = by_key(&service).ok_or_else(|| format!("Неизвестный сервис: {service}"))?;
  match key_creds(info, &fields)? {
    KeyCreds::Sc(creds) => core.connect_soundcloud(creds).await,
    KeyCreds::Ym(creds) => core.connect_yandex(creds).await,
    KeyCreds::Yt(cookie) => core.connect_youtube(&cookie).await,
    KeyCreds::Vk(creds) => core.connect_vk(creds).await,
    KeyCreds::Sp(sp_dc) => core.connect_spotify(&sp_dc).await,
  }
  .map_err(err)
}

/// Подключить сервис в один клик: окно входа самого сервиса, ключи Sonar забирает сам (login.rs).
#[tauri::command]
pub async fn login_service(app: tauri::AppHandle, core: State<'_, Arc<Core>>, db: State<'_, Db>, service: String) -> Res<ServiceStatus> {
  let core = core.inner().clone();
  match by_key(&service).map(|s| s.key).unwrap_or(service.as_str()) {
    // Яндекс — в браузере по умолчанию по коду; вход по коду недоступен — прежнее окно
    "yandex" => {
      let device = db.0.lock().unwrap().device_id().unwrap_or_else(|_| "sonar-windows".into());
      match crate::login::yandex_device(&app, &core, &device).await {
        Ok(Some(s)) => Ok(s),
        Ok(None) => crate::login::yandex(app, core).await,
        Err(e) => Err(e),
      }
    }
    "soundcloud" => crate::login::soundcloud(app, core).await,
    "youtube" => crate::login::youtube(app, core).await,
    "vk" => crate::login::vk(app, core).await,
    "spotify" => crate::login::spotify(app, core).await,
    _ => Err(anyhow::anyhow!("Неизвестный сервис: {service}")),
  }
  .map_err(err)
}

/// «Отмена» входа через браузер (Яндекс по коду).
#[tauri::command]
pub fn cancel_login() {
  crate::login::cancel();
}

#[tauri::command]
pub async fn disconnect_service(core: State<'_, Arc<Core>>, service: String) -> Res<()> {
  // Core сам понимает и `sc`, и `soundcloud`; неизвестное — прежний текст с тем, что прислали
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
  /// Что реально играет: «AAC 160», «MP3 320», «FLAC», «Opus 160 · YouTube Music».
  quality: String,
  /// Играет не со своего сервиса: откуда и почему (для всплывашки «Играет из …»).
  via: Option<crate::services::fallback::Via>,
}

/// Адрес на локальном аудио-сервере для `<audio>` (file) или hls.js (hls). Свой сервис трек не
/// отдаёт — тот же трек из резервного (`audio.fallback`). `track` — трек из интерфейса: по нему
/// ищется замена, если в кэше треков его нет.
#[tauri::command]
pub async fn stream_url(
  core: State<'_, Arc<Core>>,
  db: State<'_, Db>,
  port: State<'_, StreamPort>,
  track_ref: String,
  track: Option<Track>,
) -> Res<StreamUrl> {
  // трек в кэше на диске — играет файлом оттуда (и HLS, уже склеенный)
  if let Some((_, mime, _)) = crate::track_cache::lookup(&track_ref) {
    let quality = match mime.as_str() {
      "audio/flac" | "audio/x-flac" => "FLAC · кэш",
      "audio/mp4" | "audio/aac" => "AAC · кэш",
      "audio/webm" => "Opus · кэш",
      _ => "MP3 · кэш",
    };
    let url = crate::stream::track_url(port.0, "file", &track_ref);
    return Ok(StreamUrl { kind: "file", url, quality: quality.into(), via: None });
  }
  playable_url(&core, &db, port.0, &track_ref, track, false).await
}

/// Свой поток открылся, но не играет (ошибка `<audio>` после повтора) — тот же трек из резервного
/// сервиса. Замены нет — ошибка, и плеер идёт дальше по очереди.
#[tauri::command]
pub async fn stream_fallback(
  core: State<'_, Arc<Core>>,
  db: State<'_, Db>,
  port: State<'_, StreamPort>,
  track_ref: String,
  track: Option<Track>,
) -> Res<StreamUrl> {
  playable_url(&core, &db, port.0, &track_ref, track, true).await
}

async fn playable_url(core: &Core, db: &Db, port: u16, track_ref: &str, track: Option<Track>, broken: bool) -> Res<StreamUrl> {
  let (known, meta) = {
    let db = db.0.lock().unwrap();
    let known = db.track_aliases(track_ref).unwrap_or_else(|e| {
      log::warn!("[fallback] track_alias {track_ref}: {e}");
      Vec::new()
    });
    let meta = track.or_else(|| db.tracks(&[track_ref.to_owned()]).ok().and_then(|t| t.into_iter().next()));
    (known, meta)
  };
  core.fallback.remember(&known);
  // YouTube Music не открылся — ещё раз с новой visitorData, причина — в журнал ошибок
  let played = core.resolve_playable(track_ref, meta.as_ref(), broken).await;
  // найденные пары, «не нашлось» и переставшие играть — на диск, даже когда замены нет
  let writes = core.fallback.take_writes();
  if !writes.is_empty() {
    if let Err(e) = db.0.lock().unwrap().apply_track_alias_writes(&writes) {
      log::warn!("[fallback] track_alias {track_ref}: {e}");
    }
  }
  let played = played.map_err(err)?;
  {
    let mut db = db.0.lock().unwrap();
    if let Some(t) = &played.found {
      if let Err(e) = db.upsert_tracks(std::slice::from_ref(t)) {
        log::warn!("[fallback] трек замены {}: {e}", t.ref_);
      }
    }
  }
  let (kind, path, quality) = match played.source {
    Source::File { quality, .. } => ("file", "file", quality),
    Source::Hls { quality, .. } => ("hls", "hls", quality),
  };
  Ok(StreamUrl { kind, url: crate::stream::track_url(port, path, track_ref), quality, via: played.via })
}

/// «Волна офлайн»: следующие треки волны — в кэш треков заранее (фоном, по одному; новый вызов
/// отменяет старый). Кэш выключен — ничего не делает.
#[tauri::command]
pub fn prefetch_tracks(core: State<'_, Arc<Core>>, refs: Vec<String>) {
  if !crate::track_cache::enabled() {
    return;
  }
  let refs: Vec<String> = refs.into_iter().take(20).collect();
  tauri::async_runtime::spawn(crate::stream::prefetch(core.inner().clone(), refs));
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
    "integrations.discord.artist_photo" => flag(&discord.artist_photo),
    "integrations.discord.show_paused" => flag(&discord.show_paused),
    "integrations.discord.button_listen" => flag(&discord.button_listen),
    "integrations.discord.button_download" => flag(&discord.button_download),
    "integrations.discord.status_format" => {
      let i = crate::discord::FORMATS.iter().position(|f| Some(*f) == value.as_str()).unwrap_or(0);
      discord.format.store(i as u8, Ordering::Relaxed);
      discord.refresh();
    }
    "system.tray" => crate::tray::HIDE_ON_CLOSE.store(value.as_bool().unwrap_or(true), Ordering::Relaxed),
    "obs.token" => *obs.token.write().unwrap() = value.as_str().unwrap_or_default().to_owned(),
    "obs.size" => *obs.size.write().unwrap() = value.as_str().unwrap_or("standard").to_owned(),
    "obs.hide_paused" => obs.hide_paused.store(value.as_bool().unwrap_or(true), Ordering::Relaxed),
    _ => {}
  }
  if key == "audio.sc_via_yandex" {
    core.sc_via_yandex.store(value.as_bool().unwrap_or(false), Ordering::Relaxed);
  }
  if key == "audio.fallback" {
    core.fallback.enabled.store(value.as_bool().unwrap_or(true), Ordering::Relaxed);
  }
  if key == "audio.fallback_order" {
    core.fallback.set_order(crate::services::fallback::parse_order(Some(&value)));
  }
  if key == "audio.quality" {
    core.max_kbps.store(crate::services::quality_kbps(value.as_str()), Ordering::Relaxed);
  }
  if key == "audio.yt_quality" {
    core.yt_high.store(crate::services::yt_high(value.as_str()), Ordering::Relaxed);
    core.forget_streams();
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
  let title = name.filter(|n| !n.trim().is_empty()).unwrap_or(page.playlist.title);
  let mut store = db.0.lock().unwrap();
  let id = crate::import_link::save_import(&mut store, &pl_ref, &title, &page.tracks).map_err(err)?;
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

/// «Очистить Любимые»: снять все лайки треков; вернёт, сколько убрано.
#[tauri::command]
pub fn clear_favorites(db: State<'_, Db>) -> Res<usize> {
  db.0.lock().unwrap().clear_track_likes().map_err(err)
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
pub fn media_update(
  media: State<'_, Media>,
  discord: State<'_, Arc<crate::discord::Discord>>,
  obs: State<'_, Arc<crate::obs::Obs>>,
  info: MediaInfo,
) {
  media::update(&media, &info);
  discord.update(&info);
  obs.update(&info);
}

/// Плашка OBS: адрес для источника «Браузер» и работает ли (порт мог быть занят).
#[tauri::command]
pub fn obs_status(obs: State<'_, Arc<crate::obs::Obs>>) -> serde_json::Value {
  serde_json::json!({
    "url": obs.url(),
    "ok": !obs.failed.load(Ordering::Relaxed),
  })
}

/// Новый токен плашки OBS: старая ссылка перестаёт работать (засветил на стриме — сбросил).
#[tauri::command]
pub fn obs_new_token(obs: State<'_, Arc<crate::obs::Obs>>, db: State<'_, Db>) -> Res<serde_json::Value> {
  let t = crate::obs::new_token();
  db.0.lock().unwrap().set_setting("obs.token", &serde_json::json!(t)).map_err(err)?;
  *obs.token.write().unwrap() = t;
  Ok(serde_json::json!({ "url": obs.url(), "ok": !obs.failed.load(Ordering::Relaxed) }))
}

/// Видит ли Sonar запущенный Discord (для «Ожидание Discord…» в настройках).
#[tauri::command]
pub fn discord_status(discord: State<'_, Arc<crate::discord::Discord>>) -> serde_json::Value {
  serde_json::json!({
    "enabled": discord.enabled.load(Ordering::Relaxed),
    "connected": discord.connected.load(Ordering::Relaxed),
  })
}

// ——— тексты песен (SPEC §3.7б, docs/LYRICS.md) ———

/// Текст трека: кэш в базе → lrclib → Genius. `None` — «Текст не найден»
/// («нет» перепроверяется через 30 мин, текст без времени — раз в 3 дня ищет синхронный). `refresh` — выбросить кэш и искать заново.
#[tauri::command]
pub async fn lyrics(core: State<'_, Arc<Core>>, db: State<'_, Db>, track: Track, refresh: Option<bool>) -> Res<Option<Lyrics>> {
  // кэш читаем отдельно: блокировка базы не должна дожить до `await` ниже
  let cached = if refresh == Some(true) {
    db.0.lock().unwrap().clear_lyrics(&track.ref_).map_err(err)?;
    None
  } else {
    db.0.lock().unwrap().lyrics_cached(&track.ref_).map_err(err)?
  };
  if let Some((json, at)) = cached {
    match json {
      Some(j) => {
        if let Ok(l) = serde_json::from_str::<Lyrics>(&j) {
          if !lyrics::wants_synced_upgrade(&l, crate::store::now_ms() - at) {
            return Ok(Some(l));
          }
          // текст без времени и давно — вдруг на lrclib появился синхронный; нет — оставляем прежний
          // и откладываем следующую проверку (fetched_at обновится)
          let fresh = lyrics::fetch_track(&core.http, &track, false).await.ok().flatten();
          let keep = match fresh {
            Some(n) if n.is_synced => n,
            _ => l,
          };
          let json = serde_json::to_string(&keep).map_err(err)?;
          db.0.lock().unwrap().put_lyrics(&track.ref_, Some(&json), Some(keep.source.as_str())).map_err(err)?;
          return Ok(Some(keep));
        }
      }
      None if crate::store::now_ms() - at < lyrics::RECHECK_TTL_MS => return Ok(None),
      None => {}
    }
  }
  let found = lyrics::fetch_track(&core.http, &track, refresh == Some(true)).await.map_err(err)?;
  let json = found.as_ref().map(|l| serde_json::to_string(l)).transpose().map_err(err)?;
  db.0
    .lock()
    .unwrap()
    .put_lyrics(&track.ref_, json.as_deref(), found.as_ref().map(|l| l.source.as_str()))
    .map_err(err)?;
  Ok(found)
}

/// Аннотации Genius к тексту трека (строки фрагмента + пояснение). Нет на Genius — пустой список.
#[tauri::command]
pub async fn lyrics_annotations(core: State<'_, Arc<Core>>, track: Track) -> Res<Vec<lyrics::genius::Annotation>> {
  let m = lyrics::Meta::of(&track);
  lyrics::genius::annotations(&core.http, &m.artist, &m.title).await.map_err(err)
}

/// Перевод строк текста на язык интерфейса (меню текста → «Перевести»).
#[tauri::command]
pub async fn lyrics_translate(core: State<'_, Arc<Core>>, lines: Vec<String>, to: String) -> Res<lyrics::translate::Translation> {
  lyrics::translate::translate(&core.http, &lines, &to).await.map_err(err)
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
  /// Пропущенные в сессии треки (оценка исхода < 0): их теги идут в минус следующим порциям.
  #[serde(default)]
  skipped_tracks: Vec<Track>,
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
  /// Сессия волны (создаёт интерфейс) — выданные треки пишутся в журнал `wave_events` под этим id.
  #[serde(default)]
  session_id: Option<String>,
}

/// Следующая порция своей волны.
/// Ссылка в строке поиска → что это (трек кладётся в кэш, чтобы лайк и плейлист его знали).
#[tauri::command]
pub async fn resolve_link(core: State<'_, Arc<Core>>, db: State<'_, Db>, url: String) -> Res<crate::services::LinkItem> {
  // ответа нет 20 с — честная ошибка вместо вечной загрузки
  let item = tokio::time::timeout(std::time::Duration::from_secs(20), core.resolve_link(&url))
    .await
    .map_err(|_| "Сервис не ответил за 20 секунд — попробуй ещё раз".to_string())?
    .map_err(err)?;
  if let crate::services::LinkItem::Track { track } = &item {
    db.0.lock().unwrap().upsert_tracks(std::slice::from_ref(track)).map_err(err)?;
  }
  Ok(item)
}

/// Мини-окно поверх всех окон: показать / закрыть (кнопка в плеере). Вернёт, открыто ли.
/// `async` обязательно: синхронная команда, создающая окно, на Windows виснет (документация Tauri).
#[tauri::command]
pub async fn mini_window(app: tauri::AppHandle, show: bool) -> Res<bool> {
  crate::mini::toggle(&app, show).map_err(err)
}

/// Оверлей (Интерфейс → Оверлей): показать / переставить по `layout` / закрыть. Вернёт, открыт ли.
#[tauri::command]
pub async fn overlay_window(app: tauri::AppHandle, show: bool, layout: Option<crate::mini::Layout>) -> Res<bool> {
  crate::mini::overlay(&app, show, &layout.unwrap_or_default()).map_err(err)
}

/// Все мониторы, как они расставлены (Интерфейс → Оверлей → «Положение на экране»): название модели,
/// разрешение, частота, рабочая область, масштаб, основной ли — `monitors.rs`.
#[tauri::command]
pub async fn list_monitors(app: tauri::AppHandle) -> Res<Vec<crate::monitors::MonitorInfo>> {
  Ok(crate::monitors::list(&app))
}

/// Кнопки «назад / пауза / вперёд» в превью окна на панели задач: `icons` — prev, play, pause, next
/// (RGBA 32×32, рисует интерфейс из наших значков).
#[tauri::command]
pub fn thumbbar_init(app: tauri::AppHandle, icons: Vec<Vec<u8>>, playing: bool) -> Res<()> {
  #[cfg(windows)]
  crate::thumbbar::init(&app, icons, playing).map_err(err)?;
  #[cfg(not(windows))]
  let _ = (app, icons, playing);
  Ok(())
}

#[tauri::command]
pub fn thumbbar_state(app: tauri::AppHandle, playing: bool) {
  #[cfg(windows)]
  crate::thumbbar::set_playing(&app, playing);
  #[cfg(not(windows))]
  let _ = (app, playing);
}

/// Показать главное окно (из мини-окна: двойной клик по обложке).
#[tauri::command]
pub fn show_main(app: tauri::AppHandle) {
  crate::tray::show_main(&app);
}

/// Все треки исполнителя (вкладка «Треки» на его странице): сначала самые прослушиваемые.
#[tauri::command]
pub async fn artist_tracks(core: State<'_, Arc<Core>>, db: State<'_, Db>, artist_ref: String) -> Res<Vec<crate::providers::ArtistTrack>> {
  let list = core.artist_tracks(&artist_ref).await.map_err(err)?;
  let tracks: Vec<Track> = list.iter().map(|t| t.track.clone()).collect();
  db.0.lock().unwrap().upsert_tracks(&tracks).map_err(err)?;
  Ok(list)
}

/// Репосты исполнителя SoundCloud (раздел «Репосты» на его странице); у других сервисов — пусто.
#[tauri::command]
pub async fn artist_reposts(core: State<'_, Arc<Core>>, db: State<'_, Db>, artist_ref: String) -> Res<Vec<Track>> {
  let list = core.artist_reposts(&artist_ref, REPOSTS_LIMIT).await.map_err(err)?;
  db.0.lock().unwrap().upsert_tracks(&list).map_err(err)?;
  Ok(list)
}

/// Сколько репостов берём для страницы исполнителя (свёрнуто видно 5, остальное — «Показать все»).
const REPOSTS_LIMIT: u32 = 50;

/// Синхронизация сейчас (API.md §6): отправить своё, забрать с других устройств. До сервера — ошибка
/// «ещё не подключён».
#[tauri::command]
pub async fn sync_now(core: State<'_, Arc<Core>>, db: State<'_, Db>) -> Res<crate::sync::SyncReport> {
  crate::sync::sync_now(&core.http, &db.0).await.map_err(err)
}

/// Отчёт прошлого запуска (было падение или ошибки) — для плашки «Sonar закрылся с ошибкой».
#[tauri::command]
pub fn report_pending() -> Option<crate::crashlog::Pending> {
  crate::crashlog::pending()
}

/// «Отправить лог»: в Telegram ботом отчётов (или в «Загрузки», если бот не вшит в сборку).
#[tauri::command]
pub async fn report_send(core: State<'_, Arc<Core>>, db: State<'_, Db>, context: Option<crate::crashlog::Context>) -> Res<crate::crashlog::Sent> {
  let device = db.0.lock().unwrap().device_id().map_err(err)?;
  let sent = crate::crashlog::send(&core.http, &device, &context.unwrap_or_default()).await.map_err(err)?;
  if let crate::crashlog::Sent::Saved { path } = &sent {
    // показать файл в Проводнике — его останется переслать
    let _ = std::process::Command::new("explorer").arg(format!("/select,{path}")).spawn();
  }
  Ok(sent)
}

#[tauri::command]
pub fn report_dismiss() {
  crate::crashlog::dismiss()
}

/// Ошибка интерфейса — в журнал сессии.
#[tauri::command]
pub fn log_frontend(level: String, message: String) {
  crate::crashlog::frontend(&level, &message)
}

/// Вес сида при выборе (docs/WAVE.md 4.3): `0.85 ^ место` (0 — самый свежий), × 1.5 — и лайкнут, и
/// дослушан, × 0.3 — его предложения в волне чаще всего пропускали.
fn seed_weights(fresh: &[String], both: &[String], weak: &std::collections::HashSet<String>) -> Vec<(String, f64)> {
  fresh
    .iter()
    .enumerate()
    .map(|(i, r)| {
      let mut w = 0.85f64.powi(i as i32);
      if both.contains(r) {
        w *= 1.5;
      }
      if weak.contains(r) {
        w *= 0.3;
      }
      (r.clone(), w)
    })
    .collect()
}

/// Сиды волны и автоплея: у локальных файлов (`local:…`) похожих нет — такой сид только занял бы
/// место, а «все сиды локальные» отключили бы запасной старт от лайков сервиса.
fn seedable(refs: Vec<String>) -> Vec<String> {
  refs.into_iter().filter(|r| !crate::local::is_local_ref(r)).collect()
}

/// «Похожие» через кэш на сутки (docs/WAVE.md 4.4): повторная порция от тех же сидов не ходит в сеть.
/// Берём с запасом (40) и режем до `limit`; ошибки сети не кэшируются.
async fn similar_cached(core: &Core, db: &Db, r: &str, limit: u32) -> anyhow::Result<Vec<Track>> {
  const DAY_MS: i64 = 24 * 3600 * 1000;
  let cached = db.0.lock().unwrap().cached_similar(r, DAY_MS).ok().flatten();
  let mut list = match cached {
    Some(v) => v,
    None => {
      let v = core.similar(r, limit.max(40)).await?;
      if let Err(e) = db.0.lock().unwrap().put_similar(r, &v) {
        log::warn!("кэш похожих: {e}");
      }
      v
    }
  };
  list.truncate(limit as usize);
  Ok(list)
}

/// Сервис, от которого стартует волна (`general.platform`): Яндекс или VK — если выбран и подключён,
/// иначе SoundCloud.
fn platform_service(platform: Option<&str>, has_ym: bool, has_vk: bool) -> ServiceId {
  match platform {
    Some(k) if has_ym && k == ServiceId::Ym.key() => ServiceId::Ym,
    Some(k) if has_vk && k == ServiceId::Vk.key() => ServiceId::Vk,
    _ => ServiceId::Sc,
  }
}

#[tauri::command]
pub async fn wave_portion(core: State<'_, Arc<Core>>, db: State<'_, Db>, req: WaveRequest) -> Res<Vec<serde_json::Value>> {
  use crate::store::ServedEvent;
  use crate::wave::{artist_key, pick_with, tag_set, Filter, Origin, Rng, Session, PORTION};
  let mut rng = Rng::new(crate::store::now_ms() as u64);
  // что зашло в сессии — свежие в конце; берём до трёх последних
  let live: Vec<String> = seedable(req.session.iter().rev().map(|t| t.ref_.clone()).collect()).into_iter().take(3).collect();
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
    for tag in tag_set(t) {
      *session.tags.entry(tag).or_insert(0.0) += w;
    }
  }
  // теги пропущенных — в минус, вдвое слабее, чем теги зашедших (докажет ещё один пропуск — потянет сильнее)
  for (i, t) in req.skipped_tracks.iter().rev().enumerate() {
    let w = 0.5 / (1.0 + i as f64 * 0.5);
    for tag in tag_set(t) {
      *session.tags.entry(tag).or_insert(0.0) -= w;
    }
  }
  let mode = req.mode.as_deref().filter(|m| crate::wave::MODES.contains(m)).unwrap_or("own").to_owned();
  let (seeds, taste, filter, platform, fav_artists) = {
    let mut store = db.0.lock().unwrap();
    if !req.session.is_empty() {
      store.upsert_tracks(&req.session).map_err(err)?;
    }
    // сиды, чьи предложения в волне чаще всего пропускали (по журналу за 30 дней)
    let weak = store.weak_seeds(30).unwrap_or_default();
    let seeds = match &req.seed {
      // стиль «по треку» держится всю сессию; зашедшее в ней понемногу его уточняет
      Some(s) => {
        store.upsert_tracks(std::slice::from_ref(s)).map_err(err)?;
        let mut v = seedable(vec![s.ref_.clone()]);
        v.extend(live.iter().filter(|r| **r != s.ref_).take(2).cloned());
        v
      }
      None if !live.is_empty() => {
        // волна учится на ходу: зашедшее в сессии + немного общего вкуса и разведки
        let mut v = live.clone();
        let fresh = seedable(store.recent_like_refs(15).map_err(err)?);
        let fresh: Vec<String> = fresh.into_iter().filter(|r| !v.contains(r)).collect();
        v.extend(rng.weighted_sample(&seed_weights(&fresh, &[], &weak), 2));
        let old = seedable(store.old_like_refs(15, 300).map_err(err)?);
        v.extend(rng.sample(&old, 1));
        v
      }
      None => {
        let likes = seedable(store.recent_like_refs(15).map_err(err)?);
        let finished = seedable(store.recent_finished_refs(10).map_err(err)?);
        let mut fresh = likes.clone();
        for r in &finished {
          if !fresh.contains(r) {
            fresh.push(r.clone());
          }
        }
        if fresh.is_empty() {
          fresh = seedable(store.recent_play_refs(10).map_err(err)?);
        }
        // настроение — больше сидов, чтобы было из чего выбрать подходящее
        let wide = req.mode.as_deref().is_some_and(|m| m != "own");
        // свежее — чаще, «и лайкнут, и дослушан» — ещё чаще, сид с провальными предложениями — реже
        let both: Vec<String> = likes.iter().filter(|r| finished.contains(r)).cloned().collect();
        let mut seeds = rng.weighted_sample(&seed_weights(&fresh, &both, &weak), if wide { 8 } else { 5 });
        // 10–20 % «разведки»: похожие от случайного старого лайка
        let old = seedable(store.old_like_refs(15, 300).map_err(err)?);
        seeds.extend(rng.sample(&old, 1));
        seeds
      }
    };
    // знакомое и новое по режиму: «Обычное» — не больше 3 незнакомых артистов на 10 треков и без
    // малоизвестных заливов SoundCloud от незнакомых (жалоба владельца «люди, которых я не знаю»)
    let (max_unknown, min_plays_unknown) = crate::wave::familiarity(&mode, req.seed.is_some(), req.n.unwrap_or(PORTION));
    let filter = Filter {
      recent: store.played_since_days(7).map_err(err)?,
      banned: store.disliked_refs().map_err(err)?.into_iter().collect(),
      exclude: req.exclude.into_iter().collect(),
      paused_artists: req.paused_artists.iter().map(|a| a.to_lowercase()).collect(),
      max_unknown,
      min_plays_unknown,
    };
    // знакомое в котёл: популярные треки 1–2 любимых / слушаемых артистов, у волны по треку —
    // артиста этого трека (его другие треки)
    let fav_artists: Vec<String> = match &req.seed {
      Some(s) => s.artists.first().map(|a| vec![a.ref_.clone()]).unwrap_or_default(),
      None => {
        let all = store.favorite_artist_refs(15).unwrap_or_default();
        rng.sample(&all, if matches!(mode.as_str(), "own" | "popular") { 2 } else { 1 })
      }
    };
    let platform = store.setting("general.platform").ok().flatten().and_then(|v| v.as_str().map(str::to_owned));
    let mut taste = store.taste().map_err(err)?;
    taste.hour_share = store.hour_share(req.tz_min.unwrap_or(0)).unwrap_or_default();
    // профили тегов: общий и (для настроений) режима — по ним `profile_fit` / `mode_profile`; сбой не ломает волну
    taste.tag_profile = store.tag_profile(None).unwrap_or_default();
    if crate::wave::is_mood(&mode) {
      taste.mode_tag_profile = store.tag_profile(Some(&mode)).unwrap_or_default();
    }
    // соседи по карте исполнителей (граф кэшируется на минуту); сбой не ломает волну
    taste.scene = crate::artist_graph::scene_for(&store).unwrap_or_default();
    (seeds, taste, filter, platform, fav_artists)
  };

  let has_ym = core.has_yandex().await;
  let has_vk = core.has_vk().await;
  let mut seeds: Vec<String> = seedable(seeds)
    .into_iter()
    .filter(|r| (has_ym || !is_kind(r, ServiceId::Ym, RefKind::Track)) && (has_vk || !is_kind(r, ServiceId::Vk, RefKind::Track)))
    .collect();
  let platform = platform_service(platform.as_deref(), has_ym, has_vk);
  let mut taste = taste;
  // Новичок: в Sonar ни лайков, ни прослушиваний — волна стартует от лайков (а если их нет —
  // от плейлистов) в выбранном сервисе. Их артисты считаются любимыми.
  if seeds.is_empty() {
    let id = platform;
    let svc = id.key();
    let pl = likes_ref(id).expect("sc/ym/vk have likes");
    let mut pool: Vec<Track> = core.service_playlist(&pl).await.map(|p| p.tracks).unwrap_or_default();
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
      taste.liked_artists.extend(crate::wave::artist_keys(t));
    }
    let refs: Vec<String> = pool.iter().take(60).map(|t| t.ref_.clone()).collect();
    seeds = rng.sample(&refs, 6);
  }
  if seeds.is_empty() {
    return Err("Волне пока не от чего оттолкнуться — лайкни или послушай пару треков.".into());
  }
  let limit = if mode == "own" { 25 } else { 35 };
  let fav_artists: Vec<String> = fav_artists.into_iter().filter(|r| has_ym || !is_kind(r, ServiceId::Ym, RefKind::Artist)).collect();
  let (results, tops) = futures_util::join!(
    futures_util::future::join_all(seeds.iter().map(|r| similar_cached(&core, &db, r, limit))),
    futures_util::future::join_all(fav_artists.iter().map(|a| core.artist_top(a, 10))),
  );
  let mut cands = Vec::new();
  let mut origin = Origin::default();
  let mut first_err = None;
  for (seed, r) in seeds.iter().zip(results) {
    match r {
      Ok(v) => {
        origin.add(seed, &v, live.contains(seed));
        cands.extend(v)
      }
      Err(e) => {
        first_err.get_or_insert_with(|| e.to_string());
      }
    }
  }
  for (artist, top) in fav_artists.iter().zip(tops) {
    if let Ok(v) = top {
      origin.add_artist(artist, &v);
      cands.extend(v);
    }
  }
  if cands.is_empty() {
    return Err(first_err.unwrap_or_else(|| "Похожих треков не нашлось — попробуй лайкнуть что-нибудь ещё.".into()));
  }
  // второй шаг (разведка, docs/WAVE.md 4.2): похожие от лучших кандидатов незнакомых артистов —
  // «Обычное» — 1 запрос, настроения и волна по треку — без него
  let hops = match mode.as_str() {
    _ if req.seed.is_some() => 0,
    "own" => 1,
    _ => 0,
  };
  if hops > 0 {
    let unknown = |t: &Track| {
      crate::wave::artist_keys(t)
        .iter()
        .all(|k| !taste.liked_artists.contains(k) && taste.plays.get(k).is_none_or(|p| *p <= 0.0))
    };
    let mut best: Vec<&Track> = cands.iter().filter(|t| unknown(t) && !filter.banned.contains(&t.ref_)).collect();
    best.sort_by(|a, b| {
      let r = |t: &Track| origin.rank.get(&t.ref_).copied().unwrap_or(0.0);
      r(b).partial_cmp(&r(a)).unwrap_or(std::cmp::Ordering::Equal)
    });
    let mut artists = std::collections::HashSet::new();
    let hop_refs: Vec<String> = best
      .into_iter()
      .filter(|t| artists.insert(artist_key(t)))
      .take(hops)
      .map(|t| t.ref_.clone())
      .collect();
    let more = futures_util::future::join_all(hop_refs.iter().map(|r| similar_cached(&core, &db, r, 20))).await;
    for (r, res) in hop_refs.iter().zip(more) {
      if let Ok(v) = res {
        origin.add_hop(r, &v);
        cands.extend(v);
      }
    }
  }
  let prefer = platform.as_str();
  let n = req.n.unwrap_or(PORTION);
  let mut out = pick_with(cands.clone(), &taste, &origin, &session, &filter, Some(prefer), &mode, n, false, &mut rng);
  // знакомого не хватило — лучше незнакомые, чем пустая волна
  let open = Filter { max_unknown: None, ..filter.clone() };
  if out.len() < n / 2 {
    out = pick_with(cands.clone(), &taste, &origin, &session, &open, Some(prefer), &mode, n, false, &mut rng);
  }
  if out.len() < 3 {
    out = pick_with(cands, &taste, &origin, &session, &open, Some(prefer), &mode, n, true, &mut rng);
  }
  // свои забытые лайки (docs/WAVE.md 4.1): «Обычное» — 3 из 10, настроение — до 2, на места 2, 5, 8
  let k = crate::wave::liked_share(&mode, req.seed.is_some());
  if k > 0 {
    let pool = db.0.lock().unwrap().forgotten_likes(30, 40).unwrap_or_default();
    let liked = crate::wave::pick_liked(pool, &taste, &session, &filter, &mode, k, &mut rng);
    out = crate::wave::insert_liked(out, liked, n);
  }
  let tracks: Vec<Track> = out.iter().map(|p| p.track.clone()).collect();
  let mut store = db.0.lock().unwrap();
  store.upsert_tracks(&tracks).map_err(err)?;
  // журнал волны (docs/WAVE.md, этап 6): что выдали и с какими признаками. Сбой записи волну не ломает.
  if let Some(sid) = req.session_id.as_deref().filter(|s| !s.is_empty()) {
    let items: Vec<ServedEvent> = out
      .iter()
      .map(|p| ServedEvent {
        ref_: p.track.ref_.clone(),
        artist: artist_key(&p.track),
        source: p.source.into(),
        seed_ref: origin.seed_of.get(&p.track.ref_).cloned(),
        features_json: serde_json::to_string(&p.features).ok(),
      })
      .collect();
    if let Err(e) = store.log_wave_served(sid, &mode, &items) {
      log::warn!("журнал волны: {e}");
    }
  }
  // «Почему этот трек»: к каждому — `why` { kind, title?, artist? } (сид — название и артист, у `artist` — имя)
  let by_seed = req.seed.as_ref().map(|s| s.ref_.clone());
  let reasons: Vec<(&str, Option<String>)> = out.iter().map(|p| crate::wave::why(p, &origin, by_seed.as_deref())).collect();
  let seed_refs: Vec<String> = reasons.iter().filter(|r| r.0 != "artist").filter_map(|r| r.1.clone()).collect();
  let seeds: std::collections::HashMap<String, Track> =
    store.tracks(&seed_refs).unwrap_or_default().into_iter().map(|t| (t.ref_.clone(), t)).collect();
  drop(store);
  Ok(
    tracks
      .into_iter()
      .zip(reasons)
      .map(|(t, (kind, seed))| {
        let mut why = serde_json::json!({ "kind": kind });
        match (kind, seed) {
          ("artist", Some(a)) => {
            let name = t.artists.iter().find(|x| x.ref_ == a).map(|x| x.name.clone()).unwrap_or_else(|| t.artist.clone());
            why["artist"] = name.into();
          }
          (_, Some(r)) => {
            if let Some(s) = seeds.get(&r) {
              why["title"] = s.title.clone().into();
              why["artist"] = s.artist.clone().into();
            }
          }
          _ => {}
        }
        let mut v = serde_json::to_value(&t).unwrap_or_default();
        v["why"] = why;
        v
      })
      .collect(),
  )
}

/// Сигнал волне: `dislike` / `undislike` (👎 и отмена), `skip` (ручной пропуск с оценкой < 0),
/// `end` — исход трека волны для журнала (`session_id`, `reward` по `reward.ts`, `played_ms`).
#[tauri::command]
pub fn wave_feedback(
  db: State<'_, Db>,
  event: String,
  track: Track,
  played_ms: Option<i64>,
  session_id: Option<String>,
  reward: Option<f64>,
) -> Res<()> {
  let mut store = db.0.lock().unwrap();
  match event.as_str() {
    "dislike" | "undislike" => {
      store.upsert_tracks(std::slice::from_ref(&track)).map_err(err)?;
      store.set_dislike(&track.ref_, &track.artist, event == "dislike").map_err(err)
    }
    "skip" => store.add_skip(&track.ref_, &track.artist, played_ms.unwrap_or(0)).map_err(err),
    "end" => {
      // без сессии или оценки (старый клиент) писать нечего
      if let (Some(sid), Some(r)) = (session_id.as_deref().filter(|s| !s.is_empty()), reward) {
        store.finish_wave_event(sid, &track.ref_, r, played_ms.unwrap_or(0)).map_err(err)?;
      }
      Ok(())
    }
    _ => Err(format!("неизвестный сигнал {event}")),
  }
}

/// Сводка по журналу волны: по режимам и по источникам — сыграно, доля ранних пропусков, доля
/// дослушанных, средняя оценка. Экрана нет (docs/WAVE.md, этап 6), только команда.
#[tauri::command]
pub fn wave_stats(db: State<'_, Db>, days: Option<i64>) -> Res<crate::store::WaveStats> {
  db.0.lock().unwrap().wave_stats(days.unwrap_or(30)).map_err(err)
}

#[tauri::command]
pub fn disliked_refs(db: State<'_, Db>) -> Res<Vec<String>> {
  db.0.lock().unwrap().disliked_refs().map_err(err)
}

/// Похожие на трек — ряд «Похожее» на главной.
#[tauri::command]
pub async fn similar_tracks(core: State<'_, Arc<Core>>, db: State<'_, Db>, track_ref: String, limit: Option<u32>) -> Res<Vec<Track>> {
  let banned: std::collections::HashSet<String> = db.0.lock().unwrap().disliked_refs().map_err(err)?.into_iter().collect();
  let tracks: Vec<Track> = similar_cached(&core, &db, &track_ref, limit.unwrap_or(20))
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
  let artists: Vec<String> = artists.into_iter().filter(|r| has_ym || is_kind(r, ServiceId::Sc, RefKind::Artist)).collect();
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

/// Итоги месяца (`kind` = `month`, `month` 1–12) или года (`year`) — карточки итогов (этап 11).
#[tauri::command]
pub fn recap(db: State<'_, Db>, kind: String, year: i64, month: Option<u32>, tz_min: Option<i64>) -> Res<crate::store::Recap> {
  let span = crate::store::RecapSpan::parse(&kind, year, month).map_err(err)?;
  db.0.lock().unwrap().recap(span, tz_min.unwrap_or(0)).map_err(err)
}

/// Месяцы и годы с прослушиваниями — список итогов и приглашение на Главной.
#[tauri::command]
pub fn recap_periods(db: State<'_, Db>, tz_min: Option<i64>) -> Res<crate::store::RecapPeriods> {
  db.0.lock().unwrap().recap_periods(tz_min.unwrap_or(0)).map_err(err)
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
  core.sc_via_yandex.store(false, Ordering::Relaxed);
  core.fallback.enabled.store(true, Ordering::Relaxed);
  core.fallback.set_order(crate::services::fallback::default_order());
  core.max_kbps.store(crate::services::quality_kbps(None), Ordering::Relaxed);
  core.yt_high.store(crate::services::yt_high(None), Ordering::Relaxed);
  Ok(())
}

#[derive(Serialize)]
pub struct StorageUsage {
  covers: u64,
  covers_bytes: u64,
  tracks: u64,
  tracks_bytes: u64,
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
  let (tracks, tracks_bytes) = crate::track_cache::usage();
  let store = db.0.lock().unwrap();
  let (lyrics, lyrics_bytes) = store.lyrics_usage().map_err(err)?;
  let db_bytes = app
    .path()
    .app_data_dir()
    .ok()
    .and_then(|d| std::fs::metadata(d.join("sonar.db")).ok())
    .map(|m| m.len())
    .unwrap_or(0);
  Ok(StorageUsage { covers, covers_bytes, tracks, tracks_bytes, lyrics, lyrics_bytes, track_prefs: store.track_prefs_count().map_err(err)?, db_bytes })
}

/// Очистить: `covers` | `lyrics` | `track_prefs` | `all` (обложки и тексты).
#[tauri::command]
pub fn clear_storage(db: State<'_, Db>, kind: String) -> Res<()> {
  let clear_covers = || {
    if let Some(d) = crate::stream::cover_dir() {
      if let Ok(rd) = std::fs::read_dir(d) {
        // обложки локальных файлов не кэш, а часть индекса папок с музыкой — их не трогаем
        for e in rd.flatten().filter(|e| !crate::local::is_cover_file(&e.file_name().to_string_lossy())) {
          let _ = std::fs::remove_file(e.path());
        }
      }
    }
  };
  let store = db.0.lock().unwrap();
  match kind.as_str() {
    "covers" => clear_covers(),
    "tracks" => crate::track_cache::clear(),
    "lyrics" => store.clear_lyrics_cache().map_err(err)?,
    "track_prefs" => store.reset_track_prefs().map_err(err)?,
    "all" => {
      clear_covers();
      crate::track_cache::clear();
      store.clear_lyrics_cache().map_err(err)?;
    }
    _ => return Err(format!("неизвестно, что чистить: {kind}")),
  }
  Ok(())
}

/// История поиска: записать запрос или открытый из поиска результат.
#[tauri::command]
pub fn add_search_history(db: State<'_, Db>, entry: crate::store::SearchEntry) -> Res<()> {
  db.0.lock().unwrap().add_search(&entry).map_err(err)
}

#[tauri::command]
pub fn search_history(db: State<'_, Db>, limit: Option<usize>) -> Res<Vec<crate::store::SearchEntry>> {
  db.0.lock().unwrap().search_history(limit.unwrap_or(20)).map_err(err)
}

#[tauri::command]
pub fn search_history_count(db: State<'_, Db>) -> Res<i64> {
  db.0.lock().unwrap().search_history_count().map_err(err)
}

#[tauri::command]
pub fn clear_search_history(db: State<'_, Db>) -> Res<()> {
  db.0.lock().unwrap().clear_search_history().map_err(err)
}

/// Кэш треков (Хранилище): включить / выключить и лимит, МБ.
#[tauri::command]
pub fn set_track_cache(on: bool, limit_mb: u64) {
  crate::track_cache::configure(on, limit_mb);
}

/// Открыть ссылку в браузере (только https; «О приложении»: канал, сайт).
#[tauri::command]
pub fn open_url(url: String) -> Res<()> {
  crate::login::open_in_browser(&url).map_err(err)
}

/// Ярлык Sonar в меню «Пуск» — `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Sonar.lnk`.
/// Установщик обычно уже создаёт его; готовый ярлык не трогаем (он может вести на установленную копию,
/// а не на exe, из которого запущен этот Sonar). Вернёт путь и `true`, если ярлык создан сейчас.
#[cfg(windows)]
fn ensure_start_shortcut() -> Res<(std::path::PathBuf, bool)> {
  use std::os::windows::process::CommandExt;
  const CREATE_NO_WINDOW: u32 = 0x0800_0000;
  let appdata = std::env::var("APPDATA").map_err(err)?;
  let lnk = std::path::PathBuf::from(appdata).join(r"Microsoft\Windows\Start Menu\Programs\Sonar.lnk");
  if lnk.exists() {
    return Ok((lnk, false));
  }
  let exe = std::env::current_exe().map_err(err)?;
  let dir = exe.parent().map(|p| p.to_path_buf()).unwrap_or_default();
  // одинарные кавычки PowerShell экранируются удвоением (в имени пользователя может быть «'»)
  let q = |p: &std::path::Path| p.to_string_lossy().replace('\'', "''");
  let script = format!(
    "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('{}');$s.TargetPath='{}';$s.WorkingDirectory='{}';$s.IconLocation='{},0';$s.Description='Sonar';$s.Save()",
    q(&lnk),
    q(&exe),
    q(&dir),
    q(&exe)
  );
  let out = std::process::Command::new("powershell")
    .args(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", &script])
    .creation_flags(CREATE_NO_WINDOW)
    .output()
    .map_err(err)?;
  if !out.status.success() || !lnk.exists() {
    return Err(format!("не удалось создать ярлык: {}", String::from_utf8_lossy(&out.stderr).trim()));
  }
  Ok((lnk, true))
}

/// «Добавить в меню Пуск»: ярлык Sonar в «Все приложения». Вернёт `true`, если создан сейчас, и `false`,
/// если уже был.
#[tauri::command]
pub fn add_to_start_menu() -> Res<bool> {
  #[cfg(windows)]
  {
    ensure_start_shortcut().map(|(_, created)| created)
  }
  #[cfg(not(windows))]
  {
    Err("только для Windows".into())
  }
}

/// «Закрепить на панели задач»: Windows не даёт программе закрепить себя тихо (нужна идентичность
/// MSIX-пакета), поэтому — ярлык в Проводнике, дальше «ПКМ → Закрепить на панели задач».
#[tauri::command]
pub fn reveal_start_shortcut() -> Res<()> {
  #[cfg(windows)]
  {
    let (lnk, _) = ensure_start_shortcut()?;
    std::process::Command::new("explorer").arg(format!("/select,{}", lnk.display())).spawn().map_err(err)?;
    Ok(())
  }
  #[cfg(not(windows))]
  {
    Err("только для Windows".into())
  }
}

/// Масштаб: `kind` — `window` (в окне) или `fullscreen` (развёрнуто), `percent` — 75–125.
#[tauri::command]
pub fn set_zoom(window: tauri::WebviewWindow, kind: String, percent: f64) {
  crate::zoom::set(&window, &kind, percent);
}

/// Заставка нарисовала первый кадр — можно показать главное окно (tray.rs `show_first`).
#[tauri::command]
pub fn first_paint(app: tauri::AppHandle) {
  crate::tray::show_first(&app);
}

/// Автозапуск с Windows (`system.autostart`): `HKCU…\Run\Sonar` = `"<exe>" --autostart` (autostart.rs).
#[tauri::command]
pub fn set_autostart(on: bool) -> Res<()> {
  crate::autostart::set(on).map_err(err)
}

#[tauri::command]
pub fn autostart_enabled() -> Res<bool> {
  crate::autostart::enabled().map_err(err)
}

/// `system.tray`: крестик прячет в трей (true) или закрывает Sonar (false).
#[tauri::command]
pub fn set_tray_mode(on: bool) {
  crate::tray::HIDE_ON_CLOSE.store(on, Ordering::Relaxed);
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::providers::registry::info;

  fn fields(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
  }

  #[test]
  fn local_files_are_not_wave_seeds() {
    let local = |c: char| format!("local:{}", c.to_string().repeat(40));
    // всё лайкнутое — локальное: сидов нет, волна стартует запасным путём (лайки сервиса)
    assert!(seedable(vec![local('a'), local('b')]).is_empty());
    assert_eq!(seedable(vec![local('a'), "sc:1".into(), "ym:2".into(), local('b')]), ["sc:1", "ym:2"]);
  }

  #[test]
  fn wave_platform_needs_connected_service() {
    assert_eq!(platform_service(Some("vk"), false, true), ServiceId::Vk);
    assert_eq!(platform_service(Some("vk"), true, false), ServiceId::Sc);
    assert_eq!(platform_service(Some("yandex"), true, true), ServiceId::Ym);
    assert_eq!(platform_service(Some("yandex"), false, true), ServiceId::Sc);
    assert_eq!(platform_service(Some("soundcloud"), true, true), ServiceId::Sc);
    assert_eq!(platform_service(None, true, true), ServiceId::Sc);
  }

  #[test]
  fn sc_creds_normalises() {
    let c = sc_creds("  abc  ", Some(" OAuth tok "));
    assert_eq!(c.client_id, "abc");
    assert_eq!(c.oauth_token.as_deref(), Some("tok"));
    assert_eq!(sc_creds("abc", Some("  ")).oauth_token, None);
    assert_eq!(sc_creds("abc", None).oauth_token, None);
    assert_eq!(ym_creds("  y0_tok \n").token, "y0_tok");
  }

  #[test]
  fn key_creds_fields_per_service() {
    let sc = key_creds(info(ServiceId::Sc), &fields(&[("client_id", " id "), ("oauth_token", "OAuth t"), ("token", "x")])).unwrap();
    let KeyCreds::Sc(c) = sc else { panic!("ожидался SoundCloud") };
    assert_eq!((c.client_id.as_str(), c.oauth_token.as_deref()), ("id", Some("t")));
    // нет обязательного поля — пустая строка, её отклонит Core прежним текстом
    let KeyCreds::Sc(c) = key_creds(info(ServiceId::Sc), &fields(&[])).unwrap() else { panic!("ожидался SoundCloud") };
    assert_eq!((c.client_id.as_str(), c.oauth_token), ("", None));
    let KeyCreds::Ym(c) = key_creds(info(ServiceId::Ym), &fields(&[("token", " t ")])).unwrap() else { panic!("ожидался Яндекс") };
    assert_eq!(c.token, "t");
    let KeyCreds::Ym(c) = key_creds(info(ServiceId::Ym), &fields(&[("client_id", "x")])).unwrap() else { panic!("ожидался Яндекс") };
    assert_eq!(c.token, "");
    let KeyCreds::Vk(c) = key_creds(info(ServiceId::Vk), &fields(&[("token", " vk1.a.t \n")])).unwrap() else { panic!("ожидался VK") };
    assert_eq!(c.token, "vk1.a.t");
    let KeyCreds::Sp(v) = key_creds(info(ServiceId::Sp), &fields(&[("sp_dc", "sp_dc=AQ")])).unwrap() else { panic!("ожидался Spotify") };
    assert_eq!(v, "sp_dc=AQ");
  }

  #[test]
  fn key_creds_unimplemented_service() {
    let e = key_creds(info(ServiceId::Local), &fields(&[("token", "SECRET123")])).unwrap_err();
    assert_eq!(e, "Локальные файлы: пока не поддерживается");
  }

  #[test]
  fn key_creds_youtube_takes_cookie_field() {
    let KeyCreds::Yt(c) = key_creds(info(ServiceId::Yt), &fields(&[("cookie", "SAPISID=a"), ("token", "x")])).unwrap() else {
      panic!("ожидался YouTube")
    };
    assert_eq!(c, "SAPISID=a");
    let KeyCreds::Yt(c) = key_creds(info(ServiceId::Yt), &fields(&[])).unwrap() else { panic!("ожидался YouTube") };
    assert_eq!(c, "");
  }

  /// Ключ в текст ошибки не попадает: ни из формы, ни из проверки Core.
  #[tokio::test]
  async fn connect_key_error_hides_secret() {
    let secret = "SECRET123";
    let core = Core::new_empty_for_tests();
    let KeyCreds::Sc(creds) = key_creds(info(ServiceId::Sc), &fields(&[("client_id", secret)])).unwrap() else {
      panic!("ожидался SoundCloud")
    };
    let e = core.connect_soundcloud(creds).await.map_err(err).unwrap_err();
    assert!(!e.contains(secret), "{e}");
    assert_eq!(e, "client_id SoundCloud — строка из 32 символов");
    let KeyCreds::Ym(creds) = key_creds(info(ServiceId::Ym), &fields(&[("token", "   ")])).unwrap() else { panic!("ожидался Яндекс") };
    assert_eq!(core.connect_yandex(creds).await.map_err(err).unwrap_err(), "Вставь токен Яндекс Музыки");
    let e = core.connect_youtube("SID=SECRET123; HSID=x").await.map_err(err).unwrap_err();
    assert!(!e.contains(secret), "{e}");
    assert_eq!(e, "В cookie нет SAPISID — войди на music.youtube.com и скопируй cookie заново");
    let KeyCreds::Sp(raw) = key_creds(info(ServiceId::Sp), &fields(&[("sp_dc", secret)])).unwrap() else { panic!("ожидался Spotify") };
    let e = core.connect_spotify(&raw).await.map_err(err).unwrap_err();
    assert!(!e.contains(secret), "{e}");
    let KeyCreds::Vk(creds) = key_creds(info(ServiceId::Vk), &fields(&[("token", " ")])).unwrap() else { panic!("ожидался VK") };
    assert_eq!(core.connect_vk(creds).await.map_err(err).unwrap_err(), "Вставь токен VK");
  }
}
