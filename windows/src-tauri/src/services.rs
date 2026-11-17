//! Общее ядро: HTTP-клиент, ключи сервисов, кэш ссылок на поток.
//! Команды интерфейса и локальный аудио-сервер ходят в сервисы только через него.

use crate::providers::registry::{by_key, parse_ref, split_ref, RefKind, ServiceId, ServiceInfo, REGISTRY};
use crate::providers::{
  soundcloud, spotify, yandex, Account, Album, AlbumPage, Artist, ArtistPage, ArtistTrack, SearchResults, ServicePlaylist, Source, Track,
};
use crate::secrets;
use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

mod provider;
mod sc;
mod sp;
mod ym;
pub use provider::{AnyProvider, Provider};

/// Ссылки SoundCloud и Яндекса живут минуты — держим чуть меньше, при 403 берём заново.
const STREAM_TTL: Duration = Duration::from_secs(240);

/// Что нашлось по ссылке из строки поиска.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum LinkItem {
  Track { track: Track },
  Album { album: Album },
  Artist { artist: Artist },
  Playlist { playlist: ServicePlaylist },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Stored<C> {
  pub creds: C,
  pub account: Account,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ServiceStatus {
  pub connected: bool,
  pub name: Option<String>,
  pub avatar_url: Option<String>,
  /// Платная подписка сервиса (Яндекс Плюс); None — сервис не говорит.
  pub premium: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ServicesStatus {
  pub soundcloud: ServiceStatus,
  pub yandex: ServiceStatus,
  pub spotify: ServiceStatus,
}

/// Сервис из реестра и состояние его подключения (команда `services_list`).
#[derive(Debug, Serialize)]
pub struct ServiceEntry {
  #[serde(flatten)]
  pub info: &'static ServiceInfo,
  pub connected: bool,
  pub account_name: Option<String>,
  pub avatar_url: Option<String>,
  pub premium: Option<bool>,
}

/// Плейлист сервиса с треками.
#[derive(Debug, Clone, Serialize)]
pub struct PlaylistPage {
  pub playlist: ServicePlaylist,
  pub tracks: Vec<Track>,
}

pub struct Core {
  pub http: reqwest::Client,
  sc: RwLock<Option<Stored<soundcloud::Creds>>>,
  ym: RwLock<Option<Stored<yandex::Creds>>>,
  sp: RwLock<Option<Stored<spotify::Creds>>>,
  /// Токен веб-плеера Spotify (живёт около часа) — общий для всех запросов.
  sp_token: tokio::sync::Mutex<Option<spotify::WebToken>>,
  /// Шифр TOTP для токена Spotify; потом — с сервера (`GET /config`).
  sp_totp: spotify::TotpSecret,
  /// Сырой JSON треков SoundCloud из поиска — в нём `transcodings` для потока.
  sc_raw: Mutex<HashMap<String, Value>>,
  /// Публичный client_id с soundcloud.com — когда своих ключей нет (поиск и открытые треки).
  sc_auto: RwLock<Option<String>>,
  streams: Mutex<HashMap<String, (Source, Instant)>>,
  /// Потолок битрейта Яндекса (`audio.quality`): 192 / 256 / 320 / 1411 (FLAC без потерь).
  pub max_kbps: AtomicU32,
  /// Трек SoundCloud играть с Яндекса, если там есть тот же (`audio.sc_via_yandex`).
  pub sc_via_yandex: AtomicBool,
  /// Найденные пары `sc:…` → `ym:…` (None — на Яндексе нет), чтобы не искать каждый раз.
  ym_twins: Mutex<HashMap<String, Option<String>>>,
}

fn status<C>(s: &Option<Stored<C>>) -> ServiceStatus {
  match s {
    Some(s) => ServiceStatus {
      connected: true,
      name: s.account.name.clone(),
      avatar_url: s.account.avatar_url.clone(),
      premium: s.account.premium,
    },
    None => ServiceStatus::default(),
  }
}

impl Core {
  pub fn new() -> Self {
    let http = reqwest::Client::builder()
      .connect_timeout(Duration::from_secs(10))
      .gzip(true)
      .build()
      .expect("http client");
    Self {
      http,
      sc: RwLock::new(secrets::load(ServiceId::Sc.key())),
      ym: RwLock::new(secrets::load(ServiceId::Ym.key())),
      sp: RwLock::new(secrets::load(ServiceId::Sp.key())),
      sp_token: tokio::sync::Mutex::new(None),
      sp_totp: spotify::default_totp(),
      sc_raw: Mutex::new(HashMap::new()),
      sc_auto: RwLock::new(None),
      streams: Mutex::new(HashMap::new()),
      max_kbps: AtomicU32::new(crate::providers::yandex::LOSSLESS_KBPS),
      // по умолчанию выключено (решение владельца 2026-11-17): на Яндексе треки бывают заблюрены
      sc_via_yandex: AtomicBool::new(false),
      ym_twins: Mutex::new(HashMap::new()),
    }
  }

  /// Ключи SoundCloud: свои из «Сервисов», иначе публичный client_id с сайта.
  /// Второе значение — true, если ключи публичные (их можно взять заново при 401/403).
  /// `renew` — выбросить старый публичный client_id и найти свежий.
  async fn sc_creds(&self, renew: bool) -> Result<(soundcloud::Creds, bool)> {
    if let Some(s) = self.sc.read().await.as_ref() {
      return Ok((s.creds.clone(), false));
    }
    if !renew {
      if let Some(id) = self.sc_auto.read().await.clone() {
        return Ok((soundcloud::Creds { client_id: id, oauth_token: None }, true));
      }
    }
    let id = soundcloud::public_client_id(&self.http).await?;
    *self.sc_auto.write().await = Some(id.clone());
    Ok((soundcloud::Creds { client_id: id, oauth_token: None }, true))
  }

  async fn sc_search(&self, creds: &soundcloud::Creds, q: &str, limit: u32) -> Result<Vec<(Track, Value)>> {
    soundcloud::SoundCloud { http: &self.http, creds }.search(q, limit).await
  }

  async fn sc_stream(&self, creds: &soundcloud::Creds, track_ref: &str, id: &str, fresh: bool) -> Result<Source> {
    let sc = soundcloud::SoundCloud { http: &self.http, creds };
    let cached = self.sc_raw.lock().unwrap().get(track_ref).cloned();
    let json = match cached {
      Some(j) if !fresh => j,
      _ => sc.track_json(id).await?,
    };
    match sc.stream(&json).await {
      Ok(src) => Ok(src),
      // в сохранённом JSON могла протухнуть track_authorization — берём трек заново
      Err(_) if !fresh => {
        let json = sc.track_json(id).await?;
        self.sc_raw.lock().unwrap().insert(track_ref.to_owned(), json.clone());
        sc.stream(&json).await
      }
      Err(e) => Err(e),
    }
  }

  /// Для тестов: ядро с ключами SoundCloud, без Диспетчера учётных данных.
  #[cfg(test)]
  pub fn with_soundcloud(creds: soundcloud::Creds) -> Self {
    let core = Self::new_empty();
    *core.sc.try_write().unwrap() = Some(Stored { creds, account: Account::default() });
    core
  }

  /// Для тестов других модулей: пустое ядро без keyring.
  #[cfg(test)]
  pub fn new_empty_for_tests() -> Self {
    Self::new_empty()
  }

  #[cfg(test)]
  fn new_empty() -> Self {
    Self {
      http: reqwest::Client::new(),
      sc: RwLock::new(None),
      ym: RwLock::new(None),
      sp: RwLock::new(None),
      sp_token: tokio::sync::Mutex::new(None),
      sp_totp: spotify::default_totp(),
      sc_raw: Mutex::new(HashMap::new()),
      sc_auto: RwLock::new(None),
      streams: Mutex::new(HashMap::new()),
      max_kbps: AtomicU32::new(crate::providers::yandex::LOSSLESS_KBPS),
      sc_via_yandex: AtomicBool::new(false),
      ym_twins: Mutex::new(HashMap::new()),
    }
  }

  pub async fn status(&self) -> ServicesStatus {
    ServicesStatus {
      soundcloud: status(&*self.sc.read().await),
      yandex: status(&*self.ym.read().await),
      spotify: status(&*self.sp.read().await),
    }
  }

  /// Все сервисы реестра по порядку; у работающих — подключён ли и чей аккаунт.
  pub async fn list(&self) -> Vec<ServiceEntry> {
    let ServicesStatus { soundcloud, yandex, spotify } = self.status().await;
    REGISTRY
      .iter()
      .map(|info| {
        let st = match info.id {
          ServiceId::Sc => soundcloud.clone(),
          ServiceId::Ym => yandex.clone(),
          ServiceId::Sp => spotify.clone(),
          _ => ServiceStatus::default(),
        };
        ServiceEntry { info, connected: st.connected, account_name: st.name, avatar_url: st.avatar_url, premium: st.premium }
      })
      .collect()
  }

  pub async fn connect_soundcloud(&self, creds: soundcloud::Creds) -> Result<ServiceStatus> {
    if creds.client_id.trim().len() < 20 {
      bail!("client_id SoundCloud — строка из 32 символов");
    }
    let account = soundcloud::SoundCloud { http: &self.http, creds: &creds }.account().await?;
    let stored = Stored { creds, account };
    secrets::save(ServiceId::Sc.key(), &stored)?;
    *self.sc.write().await = Some(stored.clone());
    self.streams.lock().unwrap().clear();
    Ok(status(&Some(stored)))
  }

  pub async fn connect_yandex(&self, creds: yandex::Creds) -> Result<ServiceStatus> {
    if creds.token.trim().is_empty() {
      bail!("Вставь токен Яндекс Музыки");
    }
    let account = yandex::Yandex { http: &self.http, creds: &creds }.account().await?;
    let stored = Stored { creds, account };
    secrets::save(ServiceId::Ym.key(), &stored)?;
    *self.ym.write().await = Some(stored.clone());
    self.streams.lock().unwrap().clear();
    Ok(status(&Some(stored)))
  }

  pub async fn disconnect(&self, service: &str) -> Result<()> {
    let Some(info) = by_key(service) else { bail!("неизвестный сервис {service}") };
    match info.id {
      ServiceId::Sc => *self.sc.write().await = None,
      ServiceId::Ym => *self.ym.write().await = None,
      ServiceId::Sp => self.forget_spotify().await,
      _ => bail!("неизвестный сервис {service}"),
    }
    secrets::delete(info.key)
  }

  /// Работающий сервис по id. Остальные — «{name}: пока не поддерживается».
  pub fn provider(&self, id: ServiceId) -> Result<AnyProvider<'_>> {
    match id {
      ServiceId::Sc => Ok(AnyProvider::Sc(sc::ScProvider { core: self })),
      ServiceId::Ym => Ok(AnyProvider::Ym(ym::YmProvider { core: self })),
      ServiceId::Sp => Ok(AnyProvider::Sp(sp::SpProvider { core: self })),
      other => bail!("{}: пока не поддерживается", other.info().name),
    }
  }

  /// Сервис по `src` поиска — только короткий id (`sc`, `ym`), как и раньше.
  fn source(&self, src: &str) -> Result<AnyProvider<'_>> {
    let info = by_key(src).filter(|s| s.id.as_str() == src).ok_or_else(|| anyhow!("неизвестный источник {src}"))?;
    self.provider(info.id)
  }

  /// Сервис и id объекта по ref вида `kind`. Без `:` — «плохой ref», чужой вид или
  /// неработающий сервис — `{unknown} {ref}`.
  fn route<'r>(&self, r: &'r str, kind: RefKind, unknown: &str) -> Result<(AnyProvider<'_>, &'r str)> {
    let (_, id) = split_ref(r).ok_or_else(|| anyhow!("плохой ref {r}"))?;
    match parse_ref(r) {
      Some((s, k)) if k == kind && s.implemented => Ok((self.provider(s.id)?, id)),
      _ => bail!("{unknown} {r}"),
    }
  }

  pub async fn search(&self, q: &str, src: &str, limit: u32) -> Result<Vec<Track>> {
    self.source(src)?.search(q, limit).await
  }

  /// Сырой JSON треков SoundCloud → модели; JSON запоминаем для потока.
  fn sc_keep(&self, raw: Vec<Value>) -> Vec<Track> {
    let mut cache = self.sc_raw.lock().unwrap();
    if cache.len() > 5000 {
      cache.clear();
    }
    raw
      .into_iter()
      .filter_map(|j| {
        let t = soundcloud::track_from_json(&j)?;
        cache.insert(t.ref_.clone(), j);
        Some(t)
      })
      .collect()
  }

  /// Вызов SoundCloud с повтором на свежем публичном client_id при 401/403.
  async fn with_sc<T, F, Fut>(&self, f: F) -> Result<T>
  where
    F: Fn(soundcloud::Creds) -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
  {
    let (creds, public) = self.sc_creds(false).await?;
    match f(creds).await {
      Err(e) if public && is_auth_error(&e) => f(self.sc_creds(true).await?.0).await,
      r => r,
    }
  }

  async fn ym_creds(&self) -> Result<Stored<yandex::Creds>> {
    self.ym.read().await.clone().ok_or_else(|| anyhow!("Яндекс Музыка не подключена — открой Настройки → Сервисы"))
  }

  /// Исполнители, альбомы, плейлисты для вкладок поиска.
  pub async fn search_more(&self, q: &str, src: &str, limit: u32) -> Result<SearchResults> {
    self.source(src)?.search_more(q, limit).await
  }

  pub async fn artist_page(&self, artist_ref: &str) -> Result<ArtistPage> {
    let (p, id) = self.route(artist_ref, RefKind::Artist, "неизвестный исполнитель")?;
    p.artist_page(id).await
  }

  /// Все треки исполнителя для вкладки «Треки» (до 1000), сначала самые прослушиваемые.
  pub async fn artist_tracks(&self, artist_ref: &str) -> Result<Vec<ArtistTrack>> {
    let (p, id) = self.route(artist_ref, RefKind::Artist, "неизвестный исполнитель")?;
    p.artist_tracks(id).await
  }

  pub async fn album_page(&self, album_ref: &str) -> Result<AlbumPage> {
    let (p, id) = self.route(album_ref, RefKind::Album, "неизвестный альбом")?;
    p.album_page(id).await
  }

  /// Похожие на трек (`sc:` — related SoundCloud, `ym:` — similar Яндекса). Для волны и «Похожего».
  pub async fn similar(&self, track_ref: &str, limit: u32) -> Result<Vec<Track>> {
    let (p, id) = self.route(track_ref, RefKind::Track, "неизвестный трек")?;
    p.similar(id, limit).await
  }

  /// Популярные треки исполнителя — «знакомое» для своей волны (одна просьба к сервису).
  pub async fn artist_top(&self, artist_ref: &str, limit: u32) -> Result<Vec<Track>> {
    let (p, id) = self.route(artist_ref, RefKind::Artist, "неизвестный исполнитель")?;
    p.artist_top(id, limit).await
  }

  /// Яндекс подключён — можно брать его похожие и новинки.
  pub async fn has_yandex(&self) -> bool {
    self.ym.read().await.is_some()
  }

  /// Альбомы исполнителя (для «Релизов» на главной).
  pub async fn artist_albums(&self, artist_ref: &str) -> Result<Vec<Album>> {
    let (p, id) = self.route(artist_ref, RefKind::Artist, "неизвестный исполнитель")?;
    p.artist_albums(id).await
  }

  /// Новинки Яндекса — когда у любимых исполнителей свежего нет.
  pub async fn yandex_new_releases(&self, limit: usize) -> Result<Vec<Album>> {
    let s = self.ym_creds().await?;
    yandex::Yandex { http: &self.http, creds: &s.creds }.new_releases(limit).await
  }

  /// id своего аккаунта в сервисе: из сохранённого, иначе спросить у сервиса.
  async fn sc_uid(&self) -> Result<Option<(soundcloud::Creds, String)>> {
    let Some(s) = self.sc.read().await.clone() else { return Ok(None) };
    if s.creds.oauth_token.is_none() {
      return Ok(None);
    }
    let uid = match s.account.uid.clone() {
      Some(u) => u,
      None => soundcloud::SoundCloud { http: &self.http, creds: &s.creds }
        .account()
        .await?
        .uid
        .ok_or_else(|| anyhow!("SoundCloud: не узнал id аккаунта"))?,
    };
    Ok(Some((s.creds, uid)))
  }

  async fn ym_uid(&self) -> Result<Option<(yandex::Creds, String)>> {
    let Some(s) = self.ym.read().await.clone() else { return Ok(None) };
    let uid = match s.account.uid.clone() {
      Some(u) => u,
      None => yandex::Yandex { http: &self.http, creds: &s.creds }
        .account()
        .await?
        .uid
        .ok_or_else(|| anyhow!("Яндекс Музыка: не узнал id аккаунта"))?,
    };
    Ok(Some((s.creds, uid)))
  }

  /// Фантомные плейлисты подключённых аккаунтов: сначала «Лайки» сервиса, потом свои плейлисты.
  /// `service` — короткий id (`sc`) или ключ (`soundcloud`).
  pub async fn service_playlists(&self, service: &str) -> Result<Vec<ServicePlaylist>> {
    let info = by_key(service).ok_or_else(|| anyhow!("неизвестный сервис {service}"))?;
    self.provider(info.id)?.playlists().await
  }

  /// Плейлист сервиса с треками (`scpl:<id>`, `scpl:likes`, `ympl:<uid>:<kind>`, `ympl:likes`).
  pub async fn service_playlist(&self, pl_ref: &str) -> Result<PlaylistPage> {
    let (p, id) = self.route(pl_ref, RefKind::Playlist, "неизвестный плейлист")?;
    p.playlist(id).await
  }

  /// Ссылка из строки поиска → трек, альбом, артист или плейлист (providers/links.rs).
  pub async fn resolve_link(&self, raw: &str) -> Result<LinkItem> {
    use crate::providers::links::{parse, Link};
    let link = parse(raw).ok_or_else(|| anyhow!("Это не ссылка на трек, альбом, артиста или плейлист SoundCloud и Яндекс Музыки"))?;
    match link {
      Link::Ref(r) => {
        let (kind, id) = r.split_once(':').ok_or_else(|| anyhow!("плохая ссылка"))?;
        match kind {
          "ym" => {
            let s = self.ym_creds().await?;
            let t = yandex::Yandex { http: &self.http, creds: &s.creds }.tracks(&[id.to_owned()]).await?;
            let track = t.into_iter().next().ok_or_else(|| anyhow!("Яндекс Музыка: трек не найден"))?;
            Ok(LinkItem::Track { track })
          }
          "ymalb" => Ok(LinkItem::Album { album: self.album_page(&r).await?.album }),
          "yma" => Ok(LinkItem::Artist { artist: self.artist_page(&r).await?.artist }),
          _ => Ok(LinkItem::Playlist { playlist: self.service_playlist(&r).await?.playlist }),
        }
      }
      Link::SoundCloud(url) => {
        let http = &self.http;
        let url = &url;
        let v = self.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.resolve(url).await }).await?;
        let none = || anyhow!("SoundCloud: по ссылке ничего не нашлось");
        match v["kind"].as_str() {
          Some("track") => Ok(LinkItem::Track { track: self.sc_keep(vec![v]).into_iter().next().ok_or_else(none)? }),
          Some("playlist") => {
            let album = matches!(v["set_type"].as_str(), Some("album" | "ep" | "single" | "compilation")) || v["is_album"].as_bool() == Some(true);
            if album {
              Ok(LinkItem::Album { album: soundcloud::album_from_json(&v).ok_or_else(none)? })
            } else {
              Ok(LinkItem::Playlist { playlist: soundcloud::playlist_from_json(&v).ok_or_else(none)? })
            }
          }
          Some("user") => Ok(LinkItem::Artist { artist: soundcloud::artist_from_json(&v).ok_or_else(none)? }),
          _ => Err(none()),
        }
      }
    }
  }

  /// Ссылка на поток для `sc:123` / `ym:456`. `fresh` — не брать из кэша (ссылка протухла).
  pub async fn resolve(&self, track_ref: &str, fresh: bool) -> Result<Source> {
    if !fresh {
      if let Some((src, at)) = self.streams.lock().unwrap().get(track_ref) {
        if at.elapsed() < STREAM_TTL {
          return Ok(src.clone());
        }
      }
    }
    let (p, id) = self.route(track_ref, RefKind::Track, "неизвестный источник в")?;
    // трек SoundCloud — с Яндекса, если там есть тот же и так настроено
    let twin_wanted = p.id() == ServiceId::Sc && self.sc_via_yandex.load(Ordering::Relaxed) && self.ym.read().await.is_some();
    let twin = if twin_wanted { self.yandex_twin(track_ref, id).await } else { None };
    let src = match twin {
      Some(src) => src,
      None => p.stream(id, fresh).await?,
    };
    self.streams.lock().unwrap().insert(track_ref.to_owned(), (src.clone(), Instant::now()));
    Ok(src)
  }

  /// Поток SoundCloud как есть (публичный client_id обновляется при 401/403).
  async fn sc_resolve(&self, track_ref: &str, id: &str, fresh: bool) -> Result<Source> {
    let (creds, public) = self.sc_creds(false).await?;
    match self.sc_stream(&creds, track_ref, id, fresh).await {
      Err(e) if public && is_auth_error(&e) => self.sc_stream(&self.sc_creds(true).await?.0, track_ref, id, true).await,
      r => r,
    }
  }

  /// Тот же трек на Яндексе (FLAC / 320 вместо AAC 160 SoundCloud). Любая ошибка — None,
  /// и играет SoundCloud. Пара запоминается на сеанс.
  async fn yandex_twin(&self, track_ref: &str, id: &str) -> Option<Source> {
    let known = self.ym_twins.lock().unwrap().get(track_ref).cloned();
    let ym_id = match known {
      Some(None) => return None,
      Some(Some(ym)) => ym,
      None => {
        let found = self.find_yandex_twin(track_ref, id).await;
        if let Err(e) = &found {
          log::warn!("[twin] {track_ref}: {e}");
        }
        let found = found.ok().flatten();
        self.ym_twins.lock().unwrap().insert(track_ref.to_owned(), found.clone());
        found?
      }
    };
    let guard = self.ym.read().await;
    let s = guard.as_ref()?;
    match (yandex::Yandex { http: &self.http, creds: &s.creds }).stream(&ym_id, self.max_kbps.load(Ordering::Relaxed)).await {
      Ok(Source::File { url, quality }) => Some(Source::File { url, quality: format!("{quality} · Яндекс") }),
      Ok(other) => Some(other),
      Err(e) => {
        log::warn!("[twin] поток Яндекса {ym_id}: {e}");
        None
      }
    }
  }

  async fn find_yandex_twin(&self, track_ref: &str, id: &str) -> Result<Option<String>> {
    let cached = self.sc_raw.lock().unwrap().get(track_ref).cloned();
    let json = match cached {
      Some(j) => j,
      None => {
        let (creds, _) = self.sc_creds(false).await?;
        soundcloud::SoundCloud { http: &self.http, creds: &creds }.track_json(id).await?
      }
    };
    let wanted = crate::providers::matching::Wanted::soundcloud(
      json["user"]["username"].as_str().unwrap_or(""),
      json["publisher_metadata"]["artist"].as_str(),
      json["title"].as_str().unwrap_or(""),
      json["full_duration"].as_u64().or(json["duration"].as_u64()).unwrap_or(0),
    );
    let guard = self.ym.read().await;
    let Some(s) = guard.as_ref() else { return Ok(None) };
    let ym = yandex::Yandex { http: &self.http, creds: &s.creds };
    for q in wanted.queries() {
      let found = ym.search(&q, 8).await?;
      if let Some(t) = wanted.best(&found) {
        log::info!("[twin] {track_ref} → {} ({} — {})", t.ref_, t.artist, t.title);
        return Ok(Some(t.ref_.trim_start_matches("ym:").to_owned()));
      }
    }
    Ok(None)
  }
}

/// 401/403 от сервиса — ключ не подошёл (публичный client_id SoundCloud время от времени меняется).
fn is_auth_error(e: &anyhow::Error) -> bool {
  let t = e.to_string();
  t.contains("HTTP 401") || t.contains("HTTP 403")
}

/// `audio.quality` → потолок битрейта Яндекса. По умолчанию — максимум (FLAC, если есть).
pub fn quality_kbps(v: Option<&str>) -> u32 {
  match v {
    Some("low") => 192,
    Some("medium") => 256,
    Some("high") => 320,
    _ => crate::providers::yandex::LOSSLESS_KBPS,
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn err_text<T>(r: Result<T>) -> String {
    match r {
      Ok(_) => panic!("ожидалась ошибка"),
      Err(e) => e.to_string(),
    }
  }

  #[test]
  fn provider_dispatch_by_id() {
    let core = Core::new_empty();
    assert_eq!(core.provider(ServiceId::Sc).unwrap().id(), ServiceId::Sc);
    assert_eq!(core.provider(ServiceId::Ym).unwrap().id(), ServiceId::Ym);
    assert_eq!(core.provider(ServiceId::Sp).unwrap().id(), ServiceId::Sp);
  }

  #[test]
  fn provider_unimplemented_errors() {
    let core = Core::new_empty();
    for id in [ServiceId::Yt, ServiceId::Vk, ServiceId::Local] {
      let e = err_text(core.provider(id));
      assert!(e.contains("пока не поддерживается"), "{e}");
      assert!(e.starts_with(id.info().name), "{e}");
    }
  }

  #[tokio::test]
  async fn search_unknown_src_text() {
    let core = Core::new_empty();
    assert_eq!(err_text(core.search("x", "zz", 5).await), "неизвестный источник zz");
    // как и раньше, поиск принимает только короткий id
    assert_eq!(err_text(core.search("x", "soundcloud", 5).await), "неизвестный источник soundcloud");
    assert_eq!(err_text(core.search_more("x", "", 5).await), "неизвестный источник ");
    // нереализованный сервис отвечает сразу, без сети
    assert_eq!(err_text(core.search("x", "yt", 5).await), "YouTube Music: пока не поддерживается");
    assert_eq!(err_text(core.search_more("x", "vk", 5).await), "VK Музыка: пока не поддерживается");
  }

  #[tokio::test]
  async fn ref_dispatch_errors_unchanged() {
    let core = Core::new_empty();
    assert_eq!(err_text(core.artist_page("nocolon").await), "плохой ref nocolon");
    assert_eq!(err_text(core.artist_page("xx:1").await), "неизвестный исполнитель xx:1");
    assert_eq!(err_text(core.artist_tracks("sc:1").await), "неизвестный исполнитель sc:1");
    assert_eq!(err_text(core.artist_top("yta:1", 5).await), "неизвестный исполнитель yta:1");
    assert_eq!(err_text(core.artist_albums("scalb:1").await), "неизвестный исполнитель scalb:1");
    assert_eq!(err_text(core.album_page("sca:1").await), "неизвестный альбом sca:1");
    assert_eq!(err_text(core.album_page("ytalb:1").await), "неизвестный альбом ytalb:1");
    assert_eq!(err_text(core.similar("scpl:1", 5).await), "неизвестный трек scpl:1");
    assert_eq!(err_text(core.similar("yt:1", 5).await), "неизвестный трек yt:1");
    assert_eq!(err_text(core.service_playlist("pl_x").await), "плохой ref pl_x");
    assert_eq!(err_text(core.service_playlist("sc:1").await), "неизвестный плейлист sc:1");
    assert_eq!(err_text(core.service_playlist("ytpl:1").await), "неизвестный плейлист ytpl:1");
    assert_eq!(err_text(core.resolve("nocolon", false).await), "плохой ref nocolon");
    assert_eq!(err_text(core.resolve("scalb:1", false).await), "неизвестный источник в scalb:1");
    assert_eq!(err_text(core.resolve("yt:1", false).await), "неизвестный источник в yt:1");
  }

  /// Без Яндекса ветки ym доходят до своего провайдера и отвечают прежними текстами — без сети.
  #[tokio::test]
  async fn ym_dispatch_without_account() {
    let core = Core::new_empty();
    let not_connected = "Яндекс Музыка не подключена — открой Настройки → Сервисы";
    assert_eq!(err_text(core.search("x", "ym", 5).await), not_connected);
    assert_eq!(err_text(core.search_more("x", "ym", 5).await), not_connected);
    assert_eq!(err_text(core.artist_page("yma:1").await), not_connected);
    assert_eq!(err_text(core.artist_tracks("yma:1").await), not_connected);
    assert_eq!(err_text(core.artist_top("yma:1", 5).await), not_connected);
    assert_eq!(err_text(core.artist_albums("yma:1").await), not_connected);
    assert_eq!(err_text(core.album_page("ymalb:1").await), not_connected);
    assert_eq!(err_text(core.similar("ym:1", 5).await), not_connected);
    assert_eq!(err_text(core.service_playlist("ympl:42:1003").await), not_connected);
    assert_eq!(err_text(core.service_playlist("ympl:likes").await), "Яндекс Музыка не подключена");
    assert_eq!(err_text(core.service_playlist("ympl:42").await), "плохой ref ympl:42");
    assert_eq!(err_text(core.resolve("ym:1", false).await), "Яндекс Музыка не подключена");
    assert_eq!(err_text(core.resolve("ym:1", true).await), "Яндекс Музыка не подключена");
  }

  #[tokio::test]
  async fn service_playlists_accepts_short_id_and_key() {
    let core = Core::new_empty();
    for s in ["sc", "soundcloud", "ym", "yandex"] {
      assert!(core.service_playlists(s).await.unwrap().is_empty(), "{s}");
    }
    assert_eq!(err_text(core.service_playlists("zz").await), "неизвестный сервис zz");
    assert_eq!(err_text(core.service_playlists("youtube").await), "YouTube Music: пока не поддерживается");
    // лайки SoundCloud без OAuth-токена — прежний текст
    assert_eq!(err_text(core.service_playlist("scpl:likes").await), "Нужен OAuth-токен SoundCloud");
  }

  #[tokio::test]
  async fn list_shape_empty() {
    let list = Core::new_empty().list().await;
    let ids: Vec<ServiceId> = list.iter().map(|e| e.info.id).collect();
    assert_eq!(ids, [ServiceId::Sc, ServiceId::Ym, ServiceId::Yt, ServiceId::Vk, ServiceId::Sp, ServiceId::Local]);
    assert!(list.iter().all(|e| !e.connected && e.account_name.is_none() && e.avatar_url.is_none() && e.premium.is_none()));
    let json = serde_json::to_value(&list).unwrap();
    let keys = [
      "id", "key", "name", "color", "icon", "icon_mono", "prefixes", "caps", "implemented", "connected", "account_name",
      "avatar_url", "premium",
    ];
    for entry in json.as_array().unwrap() {
      let obj = entry.as_object().unwrap();
      let mut got: Vec<&str> = obj.keys().map(String::as_str).collect();
      let mut want = keys.to_vec();
      got.sort_unstable();
      want.sort_unstable();
      assert_eq!(got, want);
    }
    assert_eq!(json[0]["id"], "sc");
    assert_eq!(json[0]["key"], "soundcloud");
    assert_eq!(json[0]["prefixes"]["playlist"], "scpl");
    assert_eq!(json[2]["caps"]["key"], false);
    assert_eq!(json[5]["icon"], Value::Null);
    assert_eq!(json[5]["prefixes"]["album"], Value::Null);
  }

  #[tokio::test]
  async fn list_with_soundcloud() {
    let creds = soundcloud::Creds { client_id: "id".into(), oauth_token: None };
    let core = Core::with_soundcloud(creds);
    *core.sc.write().await = Some(Stored {
      creds: soundcloud::Creds { client_id: "id".into(), oauth_token: None },
      account: Account { name: Some("dj".into()), ..Account::default() },
    });
    let list = core.list().await;
    assert!(list[0].connected);
    assert_eq!(list[0].account_name.as_deref(), Some("dj"));
    assert!(!list[1].connected);
    assert!(list[2..].iter().all(|e| !e.connected));
    let st = core.status().await;
    assert!(st.soundcloud.connected && st.soundcloud.premium.is_none());
  }

  #[test]
  fn status_carries_premium() {
    let stored = Some(Stored { creds: (), account: Account { premium: Some(true), ..Account::default() } });
    assert_eq!(status(&stored).premium, Some(true));
    assert_eq!(status::<()>(&None).premium, None);
  }

  /// Без ключа Spotify ветки sp доходят до провайдера и отвечают «не подключён» — без сети.
  #[tokio::test]
  async fn sp_dispatch_without_account() {
    let core = Core::new_empty();
    let nc = spotify::NOT_CONNECTED;
    assert_eq!(err_text(core.search("x", "sp", 5).await), nc);
    assert_eq!(err_text(core.search_more("x", "sp", 5).await), nc);
    assert_eq!(err_text(core.artist_page("spa:1").await), nc);
    assert_eq!(err_text(core.artist_tracks("spa:1").await), nc);
    assert_eq!(err_text(core.album_page("spalb:1").await), nc);
    assert_eq!(err_text(core.service_playlist("sppl:1").await), nc);
    assert_eq!(err_text(core.service_playlist("sppl:likes").await), nc);
    // плейлисты аккаунта без ключа — пусто, похожих у Spotify нет
    assert!(core.service_playlists("spotify").await.unwrap().is_empty());
    assert!(core.similar("sp:1", 5).await.unwrap().is_empty());
  }

  /// Трек Spotify без Premium-сборки не играет, а просит резервный сервис — без паники и сети.
  #[cfg(not(feature = "spotify-playback"))]
  #[tokio::test]
  async fn sp_stream_needs_fallback() {
    let core = Core::new_empty();
    assert_eq!(err_text(core.resolve("sp:4uLU6hMCjMI75M1A2tKUQC", false).await), spotify::NEEDS_FALLBACK);
    *core.sp.write().await = Some(Stored {
      creds: spotify::Creds { sp_dc: "x".repeat(40) },
      account: Account { premium: Some(true), ..Account::default() },
    });
    assert_eq!(err_text(core.resolve("sp:4uLU6hMCjMI75M1A2tKUQC", true).await), spotify::NEEDS_FALLBACK);
  }

  #[tokio::test]
  async fn connect_spotify_rejects_garbage_without_network() {
    let core = Core::new_empty();
    assert_eq!(err_text(core.connect_spotify("  ").await), "Вставь значение cookie sp_dc с open.spotify.com");
    assert_eq!(err_text(core.connect_spotify("sp_dc=a b").await), "Вставь значение cookie sp_dc с open.spotify.com");
  }

  #[tokio::test]
  async fn status_and_list_show_spotify() {
    let core = Core::new_empty();
    *core.sp.write().await = Some(Stored {
      creds: spotify::Creds { sp_dc: "x".repeat(40) },
      account: Account { name: Some("F".into()), premium: Some(false), ..Account::default() },
    });
    let st = core.status().await;
    assert!(st.spotify.connected && st.spotify.premium == Some(false));
    let list = core.list().await;
    let sp = list.iter().find(|e| e.info.id == ServiceId::Sp).unwrap();
    assert!(sp.connected && sp.account_name.as_deref() == Some("F"));
    let json = serde_json::to_value(&st).unwrap();
    assert_eq!(json["spotify"]["name"], "F");
  }

  #[tokio::test]
  async fn disconnect_accepts_short_id() {
    let core = Core::new_empty();
    assert_eq!(err_text(core.disconnect("zz").await), "неизвестный сервис zz");
    assert_eq!(err_text(core.disconnect("").await), "неизвестный сервис ");
    // нереализованный сервис — тот же текст, keyring не трогаем
    assert_eq!(err_text(core.disconnect("yt").await), "неизвестный сервис yt");
    assert_eq!(err_text(core.disconnect("youtube").await), "неизвестный сервис youtube");
  }
}

#[cfg(test)]
mod live_twin {
  use super::*;

  #[tokio::test]
  #[ignore = "живые SoundCloud и Яндекс на ключах из keyring: печатает только формат"]
  async fn sc_tracks_play_from_yandex() {
    let core = Core::new();
    for q in ["EsDeeKid 4 Raws", "ONDA ANDAR FIRE", "kizaru дежавю", "lil peep star shopping"] {
      let found = core.search(q, "sc", 3).await.unwrap();
      let Some(t) = found.first() else { continue };
      let src = core.resolve(&t.ref_, false).await.unwrap();
      let quality = match src {
        Source::File { quality, .. } | Source::Hls { quality, .. } => quality,
      };
      println!("{q}: SC «{} — {}» → {quality}", t.artist, t.title);
    }
  }
}
